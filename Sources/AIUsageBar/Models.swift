import Foundation

enum Provider: String, CaseIterable, Identifiable, Codable {
    case codex, claude, antigravity
    var supportsUsageFetch: Bool { true }
    var usageSource: String { "cli" }
    static var usageProviders: [Provider] { allCases.filter(\.supportsUsageFetch) }
    var id: String { rawValue }
    var title: String { switch self { case .codex: "GPT"; case .claude: "Claude"; case .antigravity: "Antigravity" } }
    var subtitle: String { switch self { case .codex: "OpenAI · Work & Codex"; case .claude: "Anthropic"; case .antigravity: "Google · Gemini" } }
    var symbol: String { switch self { case .codex: "circle.hexagongrid.fill"; case .claude: "sun.max.fill"; case .antigravity: "sparkles" } }
    var applicationName: String { switch self { case .codex: "Codex"; case .claude: "Claude"; case .antigravity: "Gemini" } }
    var applicationBundleID: String { switch self { case .codex: "com.openai.codex"; case .claude: "com.anthropic.claudefordesktop"; case .antigravity: "com.google.GeminiMacOS" } }
    var usageURL: URL {
        let value = switch self {
        case .codex: "https://chatgpt.com/codex/cloud/settings/analytics#usage"
        case .claude: "https://claude.ai/settings/usage"
        case .antigravity: "https://antigravity.google/docs/cli/commands/usage/"
        }
        return URL(string: value)!
    }
    var accountURL: URL {
        let value = switch self {
        case .codex: "https://chatgpt.com/#settings"
        case .claude: "https://claude.ai/settings/account"
        case .antigravity: "https://one.google.com/"
        }
        return URL(string: value)!
    }
    var explanation: String { switch self {
        case .codex: "Work·Codex의 공유 한도입니다. 일반 ChatGPT 대화 전체의 사용량과는 별개입니다. 요금제에 따라 5시간 또는 주간 항목이 자동으로 바뀝니다."
        case .claude: "Claude Code의 /usage 응답을 읽습니다. 서비스에서 제공한 세션·주간 한도와 모델별 한도를 표시합니다."
        case .antigravity: "Antigravity 앱·CLI에서 제공하는 한도입니다. Gemini와 Claude/GPT 그룹의 한도는 각각 별개입니다. 웹 대시보드 대신 앱에서 원본을 확인하세요."
    } }
}

struct RateWindow: Codable, Equatable {
    var usedPercent: Double?
    var windowMinutes: Int?
    var resetsAt: Date?
    var resetDescription: String?
    var isSyntheticPlaceholder: Bool?
}
struct NamedWindow: Codable {
    var id: String
    var title: String
    var window: RateWindow
    var usageKnown: Bool?
}
struct Identity: Codable {
    var accountEmail: String?
    var loginMethod: String?
    var accountOrganization: String?
}
struct Usage: Codable {
    var primary: RateWindow?
    var secondary: RateWindow?
    var tertiary: RateWindow?
    var extraRateWindows: [NamedWindow]?
    var updatedAt: Date?
    var identity: Identity?
    var dataConfidence: String?
}
struct FetchError: Codable { var message: String? }
struct Payload: Codable {
    var provider: String?
    var source: String?
    var usage: Usage?
    var error: FetchError?
    var rateWindowLabels: [String: String]?

    static func decode(_ data: Data, for provider: Provider) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions.insert(.withFractionalSeconds)
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
        }
        let rows = try decoder.decode([Payload].self, from: data)
        guard let row = rows.first(where: { $0.provider == provider.rawValue }) else { throw ReaderError.invalidData }
        return row
    }

    func lanes(for provider: Provider) -> [Lane] {
        guard provider.supportsUsageFetch else { return [] }
        guard let usage else { return [] }
        let extras = usage.extraRateWindows ?? []
        // Antigravity's primary/secondary are summary aliases, not session/weekly slots.
        if provider == .antigravity, !extras.isEmpty {
            return extras.filter { $0.window.isSyntheticPlaceholder != true }.map {
                Lane(id: $0.id, title: Self.localized($0.title), window: $0.window, known: $0.usageKnown != false)
            }
        }
        var result: [Lane] = []
        for (key, window) in [("primary", usage.primary), ("secondary", usage.secondary), ("tertiary", usage.tertiary)] {
            guard let window, window.isSyntheticPlaceholder != true else { continue }
            let label = rateWindowLabels?[key]
            let cadence = Self.cadence(window.windowMinutes)
            let title: String
            if provider == .antigravity, let label { title = Self.localized(label) + (cadence.map { " · \($0)" } ?? "") }
            else if key == "tertiary", let label { title = Self.localized(label) + (cadence.map { " · \($0)" } ?? "") }
            else { title = cadence ?? label.map(Self.localized) ?? "기간 미제공" }
            result.append(Lane(id: key, title: title, window: window, known: true))
        }
        result += extras.filter { $0.window.isSyntheticPlaceholder != true }.map {
            Lane(id: $0.id, title: Self.localized($0.title), window: $0.window, known: $0.usageKnown != false)
        }
        return result
    }
    static func cadence(_ minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        switch minutes {
        case 300: return "5시간"
        case 10080: return "주간"
        case 1440: return "일간"
        default: return minutes % 60 == 0 ? "\(minutes / 60)시간" : "\(minutes)분"
        }
    }
    static func localized(_ text: String) -> String {
        text.replacingOccurrences(of: "5-hour", with: "5시간")
            .replacingOccurrences(of: "Weekly", with: "주간")
            .replacingOccurrences(of: "weekly", with: "주간")
            .replacingOccurrences(of: "Session", with: "세션")
    }
}
struct Lane: Identifiable {
    var id: String
    var title: String
    var window: RateWindow
    var known: Bool
    var percent: Double? {
        guard known, let p = window.usedPercent, p.isFinite, p >= 0 else { return nil }
        return p
    }
    var fill: Double { min(100, max(0, percent ?? 0)) / 100 }
    func resetText(now: Date = .now) -> String {
        guard let reset = window.resetsAt else { return window.resetDescription ?? "초기화 시간 미제공" }
        let seconds = reset.timeIntervalSince(now)
        guard seconds > 0 else { return "초기화 시각 지남 · 새로고침 필요" }
        let minutes = Int(ceil(seconds / 60))
        if minutes >= 1440 {
            let hours = (minutes % 1440) / 60
            return "\(minutes / 1440)일" + (hours > 0 ? " \(hours)시간" : "") + " 후 초기화"
        }
        if minutes >= 60 {
            let remainder = minutes % 60
            return "\(minutes / 60)시간" + (remainder > 0 ? " \(remainder)분" : "") + " 후 초기화"
        }
        return "\(minutes)분 후 초기화"
    }
}
struct ProviderState {
    var payload: Payload?
    var error: String?
    var refreshing = false
    var refreshStartedAt: Date?
    var attemptedAt: Date?
    var updatedAt: Date? { payload?.usage?.updatedAt }
    var stale: Bool { error != nil || updatedAt.map { Date().timeIntervalSince($0) > 660 } ?? true }
}
enum ReaderError: Error { case unavailable, invalidData, timeout, failed }

enum UsageFailure: String {
    case authentication, timeout, parsing, network, unknown
    static func classify(_ message: String) -> Self {
        let text = message.lowercased()
        if ["credentials not found", "not logged in", "login required", "unauthorized", "authentication failed", "token expired"].contains(where: text.contains) { return .authentication }
        if ["timed out", "timeout"].contains(where: text.contains) { return .timeout }
        if ["could not parse", "parse failed", "missing current session", "still loading", "startup output"].contains(where: text.contains) { return .parsing }
        if ["network", "connection", "temporarily", "503", "502", "429"].contains(where: text.contains) { return .network }
        return .unknown
    }
    var retryable: Bool { self == .timeout || self == .parsing || self == .network }
    var userMessage: String {
        switch self {
        case .authentication: "사용량 조회용 로그인을 확인하지 못했습니다. Claude Code의 로그인 상태를 확인하세요."
        case .timeout: "Claude 사용량 응답 시간이 초과됐습니다. 잠시 후 다시 시도하세요."
        case .parsing: "Claude 사용량 화면을 읽지 못했습니다. 잠시 후 다시 시도하세요."
        case .network: "Claude 사용량 서버 연결이 지연되고 있습니다. 잠시 후 다시 시도하세요."
        case .unknown: "Claude 사용량 조회에 실패했습니다. 로그인 문제인지는 확인되지 않았습니다."
        }
    }
}
