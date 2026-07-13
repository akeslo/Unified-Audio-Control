import XCTest
@testable import UnifiedAudioControl

/// Tests for `PreferencesStore`, the persistence layer backing the preferences UI
/// (`GeneralSettingsView`'s `@AppStorage` bindings use the same keys/UserDefaults).
/// Each test uses an isolated, uniquely-named `UserDefaults` suite so tests never
/// touch the real app's preferences and can run in any order/in parallel.
final class PreferencesStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: PreferencesStore!

    override func setUp() {
        super.setUp()
        suiteName = "com.unifiedaudiocontrol.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = PreferencesStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    func test_launchAtLogin_defaultsToFalse() {
        XCTAssertFalse(store.launchAtLogin)
    }

    func test_launchAtLogin_roundTripsThroughUserDefaults() {
        store.launchAtLogin = true
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertTrue(defaults.bool(forKey: PreferencesKeys.launchAtLogin))

        store.launchAtLogin = false
        XCTAssertFalse(store.launchAtLogin)
    }

    func test_showHUD_defaultsToTrue_whenUnset() {
        // Matches `@AppStorage("showHUD") private var showHUD = true` in GeneralSettingsView.
        XCTAssertTrue(store.showHUD)
    }

    func test_showHUD_roundTripsThroughUserDefaults() {
        store.showHUD = false
        XCTAssertFalse(store.showHUD)
        XCTAssertEqual(defaults.object(forKey: PreferencesKeys.showHUD) as? Bool, false)

        store.showHUD = true
        XCTAssertTrue(store.showHUD)
    }

    func test_independentStores_onDifferentSuites_doNotShareState() {
        let otherSuiteName = "com.unifiedaudiocontrol.tests.\(UUID().uuidString)"
        let otherDefaults = UserDefaults(suiteName: otherSuiteName)!
        let otherStore = PreferencesStore(defaults: otherDefaults)
        defer { otherDefaults.removePersistentDomain(forName: otherSuiteName) }

        store.launchAtLogin = true
        XCTAssertFalse(otherStore.launchAtLogin)
    }
}
