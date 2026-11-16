import XCTest
@testable import AIUsageBar

final class FailureTests: XCTestCase {
    func testParserFailureDoesNotAskForLogin() {
        let failure = UsageFailure.classify("Could not parse Claude usage: Missing Current session.")
        XCTAssertEqual(failure, .parsing)
        XCTAssertTrue(failure.retryable)
        XCTAssertFalse(failure.userMessage.contains("로그인"))
    }
    func testExplicitAuthenticationFailureIsNotRetried() {
        let failure = UsageFailure.classify("Claude OAuth credentials not found. Run claude to authenticate.")
        XCTAssertEqual(failure, .authentication)
        XCTAssertFalse(failure.retryable)
    }
    func testTransientAndUnknownFailuresStayDistinct() {
        XCTAssertTrue(UsageFailure.classify("Claude CLI probe timed out.").retryable)
        XCTAssertTrue(UsageFailure.classify("HTTP 503 temporarily unavailable").retryable)
        XCTAssertEqual(UsageFailure.classify("unexpected provider error"), .unknown)
        XCTAssertFalse(UsageFailure.unknown.retryable)
    }
}
