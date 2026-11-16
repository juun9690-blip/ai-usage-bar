import AppKit
import SwiftUI

@main struct AIUsageBarApp {
    @MainActor static func main() {
        if ProcessInfo.processInfo.arguments.contains("--check") {
            var failed = false
            let arguments = ProcessInfo.processInfo.arguments
            let selectedProvider = arguments.first(where: { $0.hasPrefix("--provider=") }).flatMap { Provider(rawValue: String($0.dropFirst("--provider=".count))) }
            for provider in selectedProvider.map({ [$0] }) ?? Provider.usageProviders {
                do {
                    let payload = try UsageReader.fetch(provider)
                    guard payload.error == nil, payload.usage != nil else { throw ReaderError.failed }
                    let lanes = payload.lanes(for: provider)
                    print("\(provider.rawValue): " + lanes.map { "\($0.title)=\($0.percent.map { String(format: "%.0f%%", $0) } ?? "unknown")" }.joined(separator: ", "))
                } catch { failed = true; print("\(provider.rawValue): failed (\((error as? ReaderError).map { String(describing: $0) } ?? String(describing: type(of: error))))") }
            }
            exit(failed ? 1 : 0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

// A single key-capable panel owns the content. Preview and menu-bar entry points
// must never create competing hosting trees sharing the same selection state.
final class UsagePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}
final class ClickHostingView: NSHostingView<RootView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct StatusLogoView: View {
    var providers: [Provider]
    @Environment(\.displayScale) private var displayScale
    private static let logoSize: CGFloat = 20
    private static let step: CGFloat = 11.5
    static func width(for count: Int) -> CGFloat { count == 0 ? 18 : logoSize + CGFloat(count - 1) * step }
    private func xPosition(_ index: Int) -> CGFloat {
        let correction: CGFloat = providers[index] == .claude && providers.count > 1 ? 1 / displayScale : 0
        return CGFloat(index) * Self.step + correction
    }
    var body: some View {
        Group {
            if providers.isEmpty {
                Image(systemName: "plus.circle").font(.system(size: 16)).foregroundStyle(.primary)
            } else {
                ZStack(alignment: .leading) {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                        ProviderLogo(provider: provider, size: Self.logoSize)
                            .compositingGroup()
                            .shadow(color: .black.opacity(index == 0 ? 0.45 : 0.30), radius: 1, x: 0.5, y: 1)
                            // Knock out the whole foreground footprint, including its transparent holes.
                            // This keeps the menu-bar background visible without revealing the logos behind it.
                            .mask {
                                ZStack {
                                    Rectangle().fill(.white)
                                    ForEach(0..<index, id: \.self) { foreground in
                                        // Soften Claude's right overlap more, keeping its interior fully occluded.
                                        let edgeRadius: CGFloat = providers[foreground] == .claude ? 10.75 : 10
                                        Circle().fill(RadialGradient(colors: [.black, .clear],
                                            center: .center, startRadius: 9, endRadius: edgeRadius))
                                            .frame(width: edgeRadius * 2, height: edgeRadius * 2)
                                            .offset(x: xPosition(foreground) - xPosition(index))
                                            .blendMode(.destinationOut)
                                    }
                                }.compositingGroup()
                            }
                            .offset(x: xPosition(index))
                            .zIndex(Double(providers.count - index))
                    }
                }.frame(width: Self.width(for: providers.count), height: 22, alignment: .leading)
            }
        }
        .frame(width: Self.width(for: providers.count), height: 22)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// Keep the native status button responsible for clicking and menu-bar highlighting.
final class StatusLogoHostingView: NSHostingView<StatusLogoView> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusLogoHost: StatusLogoHostingView?
    private let store = UsageStore()
    private var panel: UsagePanel!
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var menuTrackingDepth = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = ""
            button.target = self
            button.action = #selector(toggle)
            let host = StatusLogoHostingView(rootView: StatusLogoView(providers: store.visibleProviders))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                host.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            statusLogoHost = host
        }
        updateStatusLogos()
        store.onVisibilityChange = { [weak self] in self?.updateStatusLogos() }
        panel = UsagePanel(contentRect: NSRect(x: 0, y: 0, width: 392, height: 600),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "AI Usage"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let host = ClickHostingView(rootView: RootView(store: store))
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        panel.contentView = host
        store.onDismiss = { [weak self] in self?.panel.orderOut(nil) }
        store.onSelection = { [weak self] in
            // Resize after SwiftUI observes the new selection, not during the click.
            DispatchQueue.main.async { self?.resizePanel() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(menuBeganTracking), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEndedTracking), name: NSMenu.didEndTrackingNotification, object: nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.menuTrackingDepth == 0, self.panel.isVisible, event.window !== self.panel,
               event.window !== self.statusItem.button?.window {
                self.panel.orderOut(nil)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.menuTrackingDepth == 0 else { return }
            self.panel.orderOut(nil)
        }
        store.startSessionRefresh()
        if !ProcessInfo.processInfo.arguments.contains("--background") {
            DispatchQueue.main.async { self.showPanel() }
        }
    }
    private func updateStatusLogos() {
        let providers = store.visibleProviders
        statusItem.length = StatusLogoView.width(for: providers.count) + 8
        statusLogoHost?.rootView = StatusLogoView(providers: providers)
        let names = providers.map { $0 == .antigravity ? "Gemini" : $0.title }.joined(separator: " · ")
        let label = names.isEmpty ? "AI 사용량 · 서비스 추가" : "AI 사용량 · \(names)"
        statusItem.button?.toolTip = label
        statusItem.button?.setAccessibilityLabel(label)
    }
    @objc private func menuBeganTracking(_ notification: Notification) { menuTrackingDepth += 1 }
    @objc private func menuEndedTracking(_ notification: Notification) { menuTrackingDepth = max(0, menuTrackingDepth - 1) }
    private func resizePanel() {
        guard let panel else { return }
        let width = store.panelWidth
        let height = store.panelHeight
        let old = panel.frame
        let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? old
        let x = min(max(screen.minX, old.maxX - width), screen.maxX - width)
        panel.setFrame(NSRect(x: x, y: old.maxY - height, width: width, height: height), display: true)
    }
    private func showPanel() {
        let height = store.panelHeight
        let width = store.panelWidth
        if let button = statusItem.button, let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            let x = min(max(screen.minX + 8, anchor.maxX - width), screen.maxX - width - 8)
            panel.setFrame(NSRect(x: x, y: max(screen.minY + 8, screen.maxY - height - 6), width: width, height: height), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        store.refreshStaleOnOpen()
    }
    @objc func toggle() {
        if panel.isVisible { panel.orderOut(nil) } else { showPanel() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }
}
