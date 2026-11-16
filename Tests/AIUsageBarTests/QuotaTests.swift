import XCTest
@testable import AIUsageBar

final class QuotaTests: XCTestCase {
    func parse(_ json: String, _ provider: Provider = .codex) throws -> [Lane] {
        try Payload.decode(Data(json.utf8), for: provider).lanes(for: provider)
    }
    func testWeeklyInPrimaryIsNotCalledFiveHours() throws {
        let lanes = try parse("""
        [{"provider":"codex","usage":{"primary":{"usedPercent":11,"windowMinutes":10080},"secondary":null}}]
        """)
        XCTAssertEqual(lanes.count, 1)
        XCTAssertEqual(lanes[0].title, "주간")
    }
    func testFiveHourWindowCanReturnWithoutPlanBranch() throws {
        let lanes = try parse("""
        [{"provider":"codex","usage":{"primary":{"usedPercent":25,"windowMinutes":300},"secondary":{"usedPercent":55,"windowMinutes":10080}}}]
        """)
        XCTAssertEqual(lanes.map(\.title), ["5시간", "주간"])
    }
    func testAntigravityAliasesAreNotDuplicated() throws {
        let lanes = try parse("""
        [{"provider":"antigravity","usage":{"primary":{"usedPercent":20,"windowMinutes":10080},"extraRateWindows":[{"id":"gemini-week","title":"Gemini weekly","window":{"usedPercent":20,"windowMinutes":10080}},{"id":"claude-week","title":"Claude/GPT weekly","window":{"usedPercent":0,"windowMinutes":10080}}]}}]
        """, .antigravity)
        XCTAssertEqual(lanes.count, 2)
        XCTAssertEqual(lanes[0].title, "Gemini 주간")
    }
    func testMissingAndUnknownAreNotZero() throws {
        let lanes = try parse("""
        [{"provider":"antigravity","usage":{"extraRateWindows":[{"id":"unknown","title":"Gemini weekly","usageKnown":false,"window":{"usedPercent":100}},{"id":"missing","title":"Gemini 5-hour","window":{}}]}}]
        """, .antigravity)
        XCTAssertNil(lanes[0].percent)
        XCTAssertNil(lanes[1].percent)
    }
    func testSyntheticClaudeSessionIsOmittedAndRealZeroKept() throws {
        let lanes = try parse("""
        [{"provider":"claude","usage":{"primary":{"usedPercent":0,"windowMinutes":300,"isSyntheticPlaceholder":true},"secondary":{"usedPercent":0,"windowMinutes":10080}}}]
        """, .claude)
        XCTAssertEqual(lanes.count, 1)
        XCTAssertEqual(lanes[0].percent, 0)
    }
    func testResetPassingDoesNotFabricateNewQuota() throws {
        let lanes = try parse("""
        [{"provider":"codex","usage":{"primary":{"usedPercent":100,"windowMinutes":300,"resetsAt":"2020-01-01T00:00:00.000Z"}}}]
        """)
        XCTAssertEqual(lanes[0].percent, 100)
        XCTAssertTrue(lanes[0].resetText().contains("새로고침 필요"))
    }
    func testOverflowOnlyClampsBar() throws {
        let lanes = try parse("""
        [{"provider":"codex","usage":{"primary":{"usedPercent":110,"windowMinutes":300}}}]
        """)
        XCTAssertEqual(lanes[0].percent, 110)
        XCTAssertEqual(lanes[0].fill, 1)
    }
    func testErrorAndProviderMismatch() throws {
        let data = Data("[{\"provider\":\"claude\",\"error\":{\"message\":\"auth required\"}}]".utf8)
        let payload = try Payload.decode(data, for: .claude)
        XCTAssertTrue(payload.lanes(for: .claude).isEmpty)
        XCTAssertNotNil(payload.error)
        XCTAssertThrowsError(try Payload.decode(data, for: .codex))
    }
}
