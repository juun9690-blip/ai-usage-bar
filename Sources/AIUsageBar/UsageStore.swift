import Foundation
import AppKit
import OSLog

enum UsageReader {
    static var executable: URL {
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("Tools/CodexBarCLI")
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tools/CodexBarCLI")
    }
    static func fetch(_ provider: Provider) throws -> Payload {
        guard provider.supportsUsageFetch else { throw ReaderError.unavailable }
        let logger = Logger(subsystem: "personal.AIUsageBar", category: "usage")
        for attempt in 1...2 {
            let payload = try fetchOnce(provider)
            if let message = payload.error?.message {
                let reason = UsageFailure.classify(message)
                logger.error("provider=\(provider.rawValue, privacy: .public) attempt=\(attempt) failure=\(reason.rawValue, privacy: .public)")
                if provider == .claude, attempt == 1, reason.retryable {
                    Thread.sleep(forTimeInterval: 2)
                    continue
                }
            }
            return payload
        }
        throw ReaderError.failed
    }
    private static func fetchOnce(_ provider: Provider) throws -> Payload {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw ReaderError.unavailable }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ai-usage-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }
        let output = dir.appendingPathComponent("usage.json")
        fm.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let config = dir.appendingPathComponent("config.json")
        let entry: [String: Any] = ["id": provider.rawValue, "enabled": true]
        let configData = try JSONSerialization.data(withJSONObject: ["version": 1, "providers": [entry]])
        guard fm.createFile(atPath: config.path, contents: configData, attributes: [.posixPermissions: 0o600]) else { throw ReaderError.failed }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["usage", "--provider", provider.rawValue, "--source", provider.usageSource, "--format", "json", "--json-only"]
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(fm.homeDirectoryForCurrentUser.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["CODEXBAR_CONFIG"] = config.path
        process.environment = env
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 100, execute: timeout)
        let killTask = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 103, execute: killTask)
        process.waitUntilExit()
        timeout.cancel(); killTask.cancel()
        if process.terminationReason == .uncaughtSignal { throw ReaderError.timeout }
        let data = try Data(contentsOf: output)
        guard data.count <= 2_000_000 else { throw ReaderError.invalidData }
        let payload = try Payload.decode(data, for: provider)
        if process.terminationStatus != 0 && payload.error == nil { throw ReaderError.failed }
        return payload
    }
}

@MainActor final class UsageStore: ObservableObject {
    @Published var states: [Provider: ProviderState] = Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, ProviderState()) })
    @Published var selected: Provider?
    @Published private(set) var hiddenProviders: Set<Provider>
    private let defaults: UserDefaults
    var visibleProviders: [Provider] { Provider.allCases.filter { !hiddenProviders.contains($0) } }
    var activeUsageProviders: [Provider] { visibleProviders.filter(\.supportsUsageFetch) }

    func setVisible(_ visible: Bool, for provider: Provider) {
        guard visible == hiddenProviders.contains(provider) else { return }
        if visible { hiddenProviders.remove(provider) } else { hiddenProviders.insert(provider) }
        defaults.set(Provider.allCases.filter { hiddenProviders.contains($0) }.map(\.rawValue), forKey: "hiddenProviders")
        if !visible, selected == provider { selected = nil }
        onVisibilityChange?()
        onSelection?()
        if visible { refresh(provider) }
    }
    @Published var applicationError: String?
    @Published var claudeLoginInProgress = false
    @Published var automatic = true
    @Published var compact = UserDefaults.standard.object(forKey: "compactLayout") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(compact, forKey: "compactLayout")
            onSelection?()
        }
    }
    @Published var overviewContentHeight: CGFloat = 0 {
        didSet { if abs(overviewContentHeight - oldValue) >= 1 { onSelection?() } }
    }
    // Fit the rows, but never grow past the original fixed size; the list scrolls beyond that.
    var overviewHeight: CGFloat {
        let limit: CGFloat = compact ? 472 : 600
        return overviewContentHeight > 0 ? min(limit, ceil(overviewContentHeight)) : limit
    }
    var panelHeight: CGFloat { selected != nil ? (compact ? max(360, overviewHeight) : 600) : overviewHeight }
    var panelWidth: CGFloat { compact || selected == nil ? 392 : 743 }
    private var timer: Timer?
    private var sessionObservers: [NSObjectProtocol] = []
    private var recoveryTask: Task<Void, Never>?
    var onSelection: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onVisibilityChange: (() -> Void)?

    init(defaults: UserDefaults = .standard, startsMonitoring: Bool = true) {
        self.defaults = defaults
        hiddenProviders = Set((defaults.stringArray(forKey: "hiddenProviders") ?? []).compactMap(Provider.init(rawValue:)))
        guard startsMonitoring else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in if self?.automatic == true { self?.refresh() } }
        }
        for notification in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            sessionObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.automatic else { return }
                    self.startSessionRefresh()
                }
            })
        }
    }
    func startSessionRefresh() {
        refresh()
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            // Retry failed providers at 20, 60 and 180 seconds after launch/unlock.
            // A restored login or network can become available after the first request.
            for delay in [20, 40, 120] {
                do { try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000) }
                catch { return }
                guard let self, self.automatic else { return }
                for provider in Self.recoveryProviders(in: self.states) { self.refresh(provider) }
            }
        }
    }
    static func recoveryProviders(in states: [Provider: ProviderState]) -> [Provider] {
        Provider.usageProviders.filter { provider in
            guard let state = states[provider], !state.refreshing else { return false }
            return state.error != nil || state.payload?.usage == nil
        }
    }

    var refreshing: Bool { activeUsageProviders.contains { states[$0]?.refreshing == true } }
    func refreshStaleOnOpen(now: Date = .now) {
        guard automatic else { return }
        for provider in activeUsageProviders {
            guard let state = states[provider], !state.refreshing,
                  state.updatedAt == nil || state.error != nil || now.timeIntervalSince(state.updatedAt!) >= 300,
                  state.attemptedAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { continue }
            refresh(provider)
        }
    }
    func loginToClaude() {
        guard !claudeLoginInProgress else { return }
        let fm = FileManager.default
        let candidates = [fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path,
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        guard let executable = candidates.first(where: { fm.isExecutableFile(atPath: $0) }),
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            applicationError = "Claude Code 또는 터미널 앱을 찾지 못했습니다. 설치 상태를 확인해 주세요."
            return
        }
        let directory = fm.temporaryDirectory.appendingPathComponent("ai-usage-login-\(UUID().uuidString)")
        let command = directory.appendingPathComponent("Claude 로그인.command")
        let result = directory.appendingPathComponent("result")
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try ClaudeLogin.script(executable: executable, result: result.path).write(to: command, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: command.path)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            applicationError = "로그인 창을 준비하지 못했습니다. 다시 시도해 주세요."
            return
        }
        claudeLoginInProgress = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([command], withApplicationAt: terminal, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil {
                    self.claudeLoginInProgress = false
                    try? FileManager.default.removeItem(at: directory)
                    self.applicationError = "터미널 로그인 창을 열지 못했습니다. 다시 시도해 주세요."
                    return
                }
                self.onDismiss?()
                defer {
                    self.claudeLoginInProgress = false
                    try? FileManager.default.removeItem(at: directory)
                }
                // Bound the wait if the user closes Terminal or abandons browser login.
                for _ in 0..<600 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let status = try? String(contentsOf: result, encoding: .utf8),
                          let code = Int(status.trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                    if code == 0 {
                        // Let any previous probe finish so its stale result cannot overwrite this fetch.
                        while self.states[.claude]?.refreshing == true {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                        self.refresh(.claude)
                    } else {
                        self.applicationError = "Claude 로그인이 완료되지 않았습니다. 로그인 버튼으로 다시 시도해 주세요."
                    }
                    return
                }
                self.applicationError = "로그인 대기가 끝났습니다. 이미 로그인했다면 새로고침을 눌러 주세요."
            }
        }
    }
    func openApplication(for provider: Provider) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: provider.applicationBundleID) else {
            applicationError = "\(provider.applicationName) 앱을 찾지 못했습니다. 설치 위치를 확인해 주세요."
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if error != nil {
                    self?.applicationError = "\(provider.applicationName) 앱을 열지 못했습니다. 다시 시도해 주세요."
                } else {
                    self?.onDismiss?()
                }
            }
        }
    }
    func select(_ provider: Provider?) { selected = selected == provider ? nil : provider; onSelection?() }
    func refresh(_ only: Provider? = nil) {
        for provider in (only.map({ [$0] }) ?? activeUsageProviders).filter({ $0.supportsUsageFetch && !hiddenProviders.contains($0) }) {
            guard states[provider]?.refreshing != true else { continue }
            states[provider]?.refreshing = true
            states[provider]?.refreshStartedAt = .now
            Task {
                let result = await Task.detached(priority: .utility) {
                    Result { try UsageReader.fetch(provider) }
                }.value
                states[provider]?.refreshing = false
                states[provider]?.attemptedAt = .now
                switch result {
                case .success(let payload):
                    if let failure = payload.error {
                        // Keep last good values, but make stale state unmistakable.
                        states[provider]?.error = provider == .claude ? UsageFailure.classify(failure.message ?? "").userMessage : "사용량을 읽지 못했습니다. 앱 로그인과 네트워크를 확인하세요."
                    } else if payload.usage == nil {
                        states[provider]?.error = "사용량 응답이 없습니다."
                    } else {
                        states[provider]?.payload = payload
                        states[provider]?.error = nil
                    }
                case .failure(let error):
                    switch error as? ReaderError {
                    case .timeout: states[provider]?.error = "응답 시간이 초과됐습니다. 다시 시도하세요."
                    default: states[provider]?.error = "연결을 확인한 뒤 새로고침하세요."
                    }
                }
            }
        }
    }
}
