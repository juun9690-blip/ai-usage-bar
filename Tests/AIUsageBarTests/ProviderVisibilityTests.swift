import XCTest
@testable import AIUsageBar

final class ProviderVisibilityTests: XCTestCase {
    @MainActor func testHiddenSelectionClosesAndSurvivesRelaunch() {
        let name = "AIUsageBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UsageStore(defaults: defaults, startsMonitoring: false)
        XCTAssertEqual(store.visibleProviders, Provider.allCases)
        store.select(.claude)
        store.setVisible(false, for: .claude)
        XCTAssertNil(store.selected)
        let relaunched = UsageStore(defaults: defaults, startsMonitoring: false)
        XCTAssertEqual(relaunched.visibleProviders, [.codex, .antigravity])
    }

    @MainActor func testAllHiddenStopsBothBulkAndExplicitRefresh() {
        let name = "AIUsageBarTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UsageStore(defaults: defaults, startsMonitoring: false)
        for provider in Provider.allCases { store.setVisible(false, for: provider) }
        store.refresh()
        store.refresh(.claude)
        store.refreshStaleOnOpen()
        XCTAssertTrue(store.visibleProviders.isEmpty)
        XCTAssertFalse(store.refreshing)
        XCTAssertTrue(store.states.values.allSatisfy { !$0.refreshing && $0.attemptedAt == nil })
        let relaunched = UsageStore(defaults: defaults, startsMonitoring: false)
        XCTAssertTrue(relaunched.visibleProviders.isEmpty)
    }
}
