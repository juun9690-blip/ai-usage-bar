import SwiftUI
import AppKit

struct PopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// SwiftUI's indicator visibility can inherit the system's always-visible preference.
// Remove native scroller controls while keeping the document scrollable.
struct HiddenScrollbars: NSViewRepresentable {
    final class Probe: NSView {
        func hideScrollers() {
            guard let scroll = enclosingScrollView else { return }
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.hideScrollers() }
        }
        override func layout() { super.layout(); hideScrollers() }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {
        DispatchQueue.main.async { [weak view] in view?.hideScrollers() }
    }
}

// Sums the natural heights of the overview's header, rows and footer so the panel can drop unused space.
struct OverviewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}
extension View {
    func reportsOverviewHeight() -> some View {
        background(GeometryReader { Color.clear.preference(key: OverviewHeightKey.self, value: $0.size.height) })
    }
}

struct ProviderLogo: View {
    var provider: Provider
    var size: CGFloat = 32
    private static let images: [Provider: NSImage] = Dictionary(uniqueKeysWithValues: Provider.allCases.compactMap { provider in
        let filename = provider == .antigravity ? "gemini-symbol.svg" : "\(provider.rawValue)-symbol.svg"
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Assets/\(filename)")
        let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/\(filename)")
        guard let image = NSImage(contentsOf: bundled ?? local) ?? NSImage(contentsOf: local) else { return nil }
        return (provider, image)
    })
    var body: some View {
        if let image = Self.images[provider] {
            Image(nsImage: image).renderingMode(provider == .codex ? .template : .original)
                .resizable().interpolation(.high).scaledToFit()
                .foregroundStyle(.primary)
                .frame(width: provider == .codex ? size : size * 0.875, height: provider == .codex ? size : size * 0.875)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

struct RootView: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        Group {
            if store.compact, let provider = store.selected {
                DetailView(provider: provider, store: store)
                    .frame(width: 392, height: store.panelHeight)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    overview.frame(width: 392, height: store.panelHeight)
                    if let provider = store.selected {
                        Divider()
                        DetailView(provider: provider, store: store).frame(width: 350, height: 600)
                    }
                }
            }
        }
        .frame(height: store.panelHeight)
        .background(PopoverMaterial().allowsHitTesting(false))
        .alert("연결 확인", isPresented: Binding(get: { store.applicationError != nil }, set: { if !$0 { store.applicationError = nil } })) {
            Button("확인") { store.applicationError = nil }
        } message: { Text(store.applicationError ?? "") }
    }
    var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI 사용량").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { store.onDismiss?() } label: {
                    Image(systemName: "xmark").frame(width: 28, height: 28)
                }.buttonStyle(.borderless).help("사용량 창 닫기").accessibilityLabel("사용량 창 닫기")
            }.padding(.horizontal, 20).padding(.vertical, 12).reportsOverviewHeight()
            Divider().padding(.horizontal, 16)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if store.visibleProviders.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 24)).foregroundStyle(.secondary)
                            Text("표시할 서비스가 없습니다").font(.system(size: 13, weight: .medium))
                            Text("아래 설정에서 서비스를 다시 추가하세요.").font(.system(size: 11)).foregroundStyle(.secondary)
                            Menu {
                                ForEach(Provider.allCases) { provider in
                                    Button(provider.title) { store.setVisible(true, for: provider) }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                    Text("서비스 추가")
                                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .medium))
                                }.font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 8).frame(height: 28)
                            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                .accessibilityLabel("서비스 추가")
                        }.frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                    ForEach(store.visibleProviders) { provider in
                        ProviderCard(provider: provider, store: store)
                        if provider != store.visibleProviders.last { Divider().padding(.horizontal, 20) }
                    }
                }.padding(.vertical, 4).reportsOverviewHeight().background(HiddenScrollbars())
            }.scrollIndicators(.hidden)
            Divider()
            HStack {
                if store.refreshing {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let pending = store.visibleProviders.filter { store.states[$0]?.refreshing == true }
                        let start = pending.compactMap { store.states[$0]?.refreshStartedAt }.min() ?? context.date
                        let seconds = max(0, Int(context.date.timeIntervalSince(start)))
                        let label = pending.count == 1 ? pending[0].title : "\(pending.count)개 서비스"
                        Text("\(label) 조회 중 · \(seconds)초")
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    Text(store.visibleProviders.isEmpty ? "서비스를 추가해 주세요" : store.automatic ? "5분마다 업데이트" : "자동 업데이트 일시 정지").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.refresh() } label: {
                    HStack(spacing: 6) {
                        if store.refreshing {
                            ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(store.refreshing ? "갱신 중…" : "새로고침")
                    }
                }
                .buttonStyle(.borderless).font(.system(size: 12))
                .padding(.horizontal, 6).frame(height: 28)
                .disabled(store.refreshing || store.visibleProviders.isEmpty).help("자동 조회가 연결된 서비스 사용량 새로고침")
                .accessibilityLabel(store.refreshing ? "사용량 갱신 중" : "전체 새로고침")
                Menu {
                    Section("표시할 서비스") {
                        ForEach(Provider.allCases) { provider in
                            Toggle(provider.title, isOn: Binding(
                                get: { !store.hiddenProviders.contains(provider) },
                                set: { store.setVisible($0, for: provider) }
                            ))
                        }
                    }
                    Divider()
                    Toggle("간결하게 보기", isOn: $store.compact)
                    Divider()
                    Toggle("자동 업데이트", isOn: $store.automatic)
                    Divider()
                    Button("AI Usage 종료") { NSApplication.shared.terminate(nil) }
                } label: { Image(systemName: "gearshape").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("설정").accessibilityLabel("설정")
            }.padding(.horizontal, 20).padding(.vertical, 8).reportsOverviewHeight()
        }
        // Two dividers sit outside the measured sections.
        .onPreferenceChange(OverviewHeightKey.self) { store.overviewContentHeight = $0 + 2 }
    }
}

struct ProviderCard: View {
    var provider: Provider
    @ObservedObject var store: UsageStore
    @State private var hovering = false
    var state: ProviderState { store.states[provider] ?? ProviderState() }
    var lanes: [Lane] {
        let all = state.payload?.lanes(for: provider) ?? []
        if provider == .antigravity {
            let gemini = all.filter { $0.id.contains("gemini") }
            if !gemini.isEmpty {
                return Array(gemini.prefix(2)).map { lane in
                    var value = lane
                    value.title = value.title.replacingOccurrences(of: "Gemini ", with: "")
                    return value
                }
            }
        }
        return Array(all.prefix(2))
    }
    var body: some View {
        HStack(spacing: 0) {
        Button { store.openApplication(for: provider) } label: {
            Group {
            if store.compact { compactContent } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ProviderLogo(provider: provider)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.title).font(.system(size: 13, weight: .semibold))
                        Text(provider.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.refreshing {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let elapsed = max(0, Int(context.date.timeIntervalSince(state.refreshStartedAt ?? context.date)))
                            HStack(spacing: 5) {
                                Text("\(elapsed)초")
                                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                                ProgressView().controlSize(.mini)
                            }
                        }
                    }
                    else if state.error != nil, provider != .claude { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                    else if state.updatedAt != nil {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                            .foregroundStyle(.secondary).help("사용량 업데이트 완료")
                    }
                }
                if !provider.supportsUsageFetch {
                    Text("사용량 자동 조회 미연동 · ⓘ에서 사용량 페이지 열기").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if lanes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.refreshing ? "사용량 확인 중…" : "사용량 확인 필요").font(.system(size: 12))
                        Text(state.error ?? (state.refreshing ? "잠시만 기다려 주세요." : "제공된 한도 정보가 없습니다.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 14) {
                        ForEach(lanes) { lane in LaneView(lane: lane, compact: true) }
                    }
                    if state.stale {
                        Label("이전 값 · 최신 사용량 확인 필요", systemImage: "clock.badge.exclamationmark")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }
            }
            }
            }
            .padding(.leading, 14).padding(.vertical, 14).padding(.trailing, 6).frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("\(provider.applicationName) 앱으로 전환")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(provider.applicationName) 앱으로 전환")
        .accessibilityValue(lanes.map { "\($0.title), \($0.resetText()), \($0.percent.map { String(format: "%.0f퍼센트 사용", $0) } ?? "사용률 미제공")" }.joined(separator: ". "))
        if provider == .claude, state.error != nil || store.claudeLoginInProgress {
            Button { store.loginToClaude() } label: {
                Image(systemName: store.claudeLoginInProgress ? "person.crop.circle.badge.clock" : "exclamationmark.circle.fill")
                    .font(.system(size: 13)).foregroundStyle(.orange)
                    .frame(width: 28, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(store.claudeLoginInProgress)
            .help(store.claudeLoginInProgress ? "브라우저에서 Claude 로그인을 완료해 주세요" : "Claude 로그인 · 터미널에서 로그인 절차 열기")
            .accessibilityLabel(store.claudeLoginInProgress ? "Claude 로그인 진행 중" : "Claude 로그인")
        }
        Button { store.select(provider) } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 28, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(provider.title) 사용량 상세")
        .accessibilityLabel("\(provider.title) 사용량 상세")
        .padding(.trailing, 6)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(store.selected == provider ? 0.075 : hovering ? 0.04 : 0)))
        .padding(.horizontal, 6).padding(.vertical, 3)
        .onHover { hovering = $0 }
    }
    var compactContent: some View {
        HStack(spacing: 12) {
            ProviderLogo(provider: provider).help(provider.title)
            if !provider.supportsUsageFetch {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.title).font(.system(size: 12, weight: .medium))
                    Text("사용량 자동 조회 미연동")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            } else if lanes.isEmpty {
                Text(state.refreshing ? "사용량 확인 중…" : "사용량 확인 필요")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            } else {
                HStack(spacing: 14) {
                    ForEach(lanes) { lane in
                        CompactLaneView(lane: lane).frame(maxWidth: .infinity)
                    }
                }
            }
            if state.refreshing { ProgressView().controlSize(.mini) }
            else if provider.supportsUsageFetch, state.stale, !(provider == .claude && state.error != nil) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    .help("이전 값 · 최신 사용량 확인 필요")
            }
        }.frame(minHeight: 48)
    }

}

struct CompactLaneView: View {
    var lane: Lane
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(lane.title).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(lane.percent.map { String(format: "%.0f%%", $0) } ?? "—")
                    .monospacedDigit().fontWeight(.medium)
            }.font(.system(size: 11))
            if lane.percent != nil {
                ProgressView(value: lane.fill).tint((lane.percent ?? 0) >= 90 ? .red : (lane.percent ?? 0) >= 75 ? .orange : .accentColor)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(lane.resetText(now: context.date))
                    .font(.system(size: 10)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LaneView: View {
    var lane: Lane
    var compact = false
    var barColor: Color { (lane.percent ?? 0) >= 90 ? .red : (lane.percent ?? 0) >= 75 ? .orange : .accentColor }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(lane.title).foregroundStyle(.secondary).fixedSize()
                        Spacer(minLength: 4)
                        resetLabel(context.date).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lane.title).foregroundStyle(.secondary)
                        resetLabel(context.date)
                    }
                }.font(.system(size: 12))
            }
            HStack(spacing: 10) {
                if lane.percent != nil {
                    ProgressView(value: lane.fill).progressViewStyle(.linear).tint(barColor)
                        .accessibilityLabel(lane.title)
                } else {
                    Text("사용률 미제공").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }
                if let percent = lane.percent {
                    Text("\(percent, specifier: "%.0f")% 사용")
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(minWidth: 54, alignment: .trailing)
                }
            }
            if !compact, let reset = lane.window.resetsAt {
                Text(reset.formatted(.dateTime.month().day().hour().minute()))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    func resetLabel(_ now: Date) -> some View {
        Text(lane.resetText(now: now)).fontWeight(.medium).monospacedDigit()
            .foregroundStyle(.primary)
            .help(lane.window.resetsAt?.formatted(date: .complete, time: .shortened) ?? "초기화 시간 미제공")
    }
}

struct DetailView: View {
    var provider: Provider
    @ObservedObject var store: UsageStore
    var state: ProviderState { store.states[provider] ?? ProviderState() }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if store.compact {
                    Button { store.select(nil) } label: {
                        Image(systemName: "chevron.left").frame(width: 28, height: 28)
                    }.buttonStyle(.borderless).help("사용량 요약으로 돌아가기").accessibilityLabel("사용량 요약으로 돌아가기")
                }
                Text("\(provider.title) 상세").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    if store.compact { store.onDismiss?() } else { store.select(nil) }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).frame(width: 24, height: 24)
                }.buttonStyle(.borderless).help(store.compact ? "사용량 창 닫기" : "상세 닫기")
                    .accessibilityLabel(store.compact ? "사용량 창 닫기" : "상세 닫기")
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("계정").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(state.payload?.usage?.identity?.accountEmail ?? (provider == .claude && state.error != nil ? "계정 연결 확인 필요" : "현재 로그인된 계정"))
                            .font(.system(size: 12, weight: .medium)).textSelection(.enabled)
                        if let plan = state.payload?.usage?.identity?.loginMethod {
                            Text(plan).font(.system(size: 11)).foregroundStyle(.secondary)
                        } else {
                            Text("이 연결에서는 계정 정보를 제공하지 않습니다.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    if provider == .claude {
                        VStack(alignment: .leading, spacing: 8) {
                            Button { store.loginToClaude() } label: {
                                Label(store.claudeLoginInProgress ? "로그인 진행 중…" : "Claude 로그인", systemImage: "person.crop.circle.badge.key")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(store.claudeLoginInProgress)
                            Text("터미널에서 로그인 절차를 열고 브라우저로 연결합니다. 완료하면 사용량을 자동으로 다시 확인합니다.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Button("로그인 완료 · 다시 확인") { store.refresh(.claude) }
                                .buttonStyle(.link).font(.system(size: 11)).disabled(state.refreshing)
                        }
                    }
                    if let error = state.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange)
                        if let attemptedAt = state.attemptedAt {
                            Text("최근 조회 시도: \(attemptedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 20) {
                        if state.stale, state.payload != nil { Text("이전 값 · 업데이트 필요").font(.system(size: 11)).foregroundStyle(.orange) }
                        let lanes = state.payload?.lanes(for: provider) ?? []
                        if lanes.isEmpty { Text(provider.supportsUsageFetch ? "아직 확인된 한도가 없습니다." : "사용량 자동 조회 미연동 · 아래 전체 사용량 페이지에서 확인하세요.").font(.system(size: 12)).foregroundStyle(.secondary) }
                        ForEach(lanes) { lane in LaneView(lane: lane) }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        if provider == .antigravity {
                            action("Antigravity 열기", symbol: "arrow.up.forward.app") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Antigravity.app"))
                            }
                        } else {
                            action("전체 사용량 페이지", symbol: "arrow.up.right.square") { NSWorkspace.shared.open(provider.usageURL) }
                        }
                        action("프로필 및 구독", symbol: "person.crop.circle") { NSWorkspace.shared.open(provider.accountURL) }
                    }
                    Text(provider.explanation).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    if let date = state.updatedAt {
                        Text("업데이트: \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(20).background(HiddenScrollbars())
            }.scrollIndicators(.hidden)
            Divider()
            HStack {
                Button { store.setVisible(false, for: provider) } label: {
                    Label("목록에서 숨기기", systemImage: "minus.circle")
                        .font(.system(size: 12))
                }.buttonStyle(.borderless)
                    .help("설정의 표시할 서비스에서 다시 추가할 수 있습니다. 앱과 로그인은 유지됩니다.")
                    .accessibilityLabel("\(provider.title) 목록에서 숨기기")
                Spacer()
                Text("설정에서 다시 추가").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
    }
    func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { Label(title, systemImage: symbol).font(.system(size: 12)) }
            .buttonStyle(.link)
    }
}
