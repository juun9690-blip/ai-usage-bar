import XCTest
@testable import AIUsageBar

final class RecoveryTests: XCTestCase {
    @MainActor func testRecoverySkipsHealthyAndInFlightProviders() {
        var healthy = ProviderState()
        healthy.payload = Payload(usage: Usage(primary: RateWindow(usedPercent: 10), updatedAt: .now))
        var busy = ProviderState()
        busy.refreshing = true
        var failed = healthy
        failed.error = "Network unavailable"
        XCTAssertEqual(UsageStore.recoveryProviders(in: [.codex: healthy, .claude: failed, .antigravity: busy]), [.claude])
    }
    @MainActor func testRecoveryIncludesInitialFailureWithoutSnapshot() {
        XCTAssertEqual(UsageStore.recoveryProviders(in: [.claude: ProviderState()]), [.claude])
    }
}
