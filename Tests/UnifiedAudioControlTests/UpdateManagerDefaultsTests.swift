import XCTest
@testable import UnifiedAudioControl

/// A fresh install had the launch-time update check silently off: the preference
/// key was absent, `UserDefaults.bool(forKey:)` returns false for that, and the
/// app only runs its check when the flag is true. Nothing surfaced it — the
/// updater simply never ran until the user found the toggle in Preferences.
final class UpdateManagerDefaultsTests: XCTestCase {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "UpdateManagerDefaultsTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testFreshInstallDefaultsToCheckingOnLaunch() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        UpdateManager.registerDefaults(defaults)

        XCTAssertTrue(defaults.bool(forKey: UpdateManager.autoCheckDefaultsKey))
    }

    func testAnExplicitOptOutSurvivesRegistration() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Someone who deliberately turned the check off must stay off: register()
        // supplies a value only when the key is absent.
        defaults.set(false, forKey: UpdateManager.autoCheckDefaultsKey)
        UpdateManager.registerDefaults(defaults)

        XCTAssertFalse(defaults.bool(forKey: UpdateManager.autoCheckDefaultsKey))
    }

    func testAnExplicitOptInIsPreserved() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: UpdateManager.autoCheckDefaultsKey)
        UpdateManager.registerDefaults(defaults)

        XCTAssertTrue(defaults.bool(forKey: UpdateManager.autoCheckDefaultsKey))
    }
}
