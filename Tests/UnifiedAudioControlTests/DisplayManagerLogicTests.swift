import XCTest
@testable import UnifiedAudioControl

/// Tests for DisplayManager pure logic functions:
/// display name resolution, UUID/name matching against audio devices.
/// These are unit tests only — no CoreGraphics/DDC hardware access is exercised.
final class DisplayManagerLogicTests: XCTestCase {

    // MARK: - resolveDisplayName(customNames:uuid:systemName:)

    func test_resolveDisplayName_usesCustomName_whenPresent() {
        let result = DisplayManager.resolveDisplayName(customNames: ["uuid1": "Custom Monitor"], uuid: "uuid1", systemName: "System Display")
        XCTAssertEqual(result, "Custom Monitor")
    }

    func test_resolveDisplayName_fallsBackToSystemName_whenNoCustomName() {
        let result = DisplayManager.resolveDisplayName(customNames: [:], uuid: "uuid1", systemName: "System Display")
        XCTAssertEqual(result, "System Display")
    }

    func test_resolveDisplayName_fallsBackToSystemName_whenCustomNameNotForThisUUID() {
        let result = DisplayManager.resolveDisplayName(customNames: ["uuid2": "Other"], uuid: "uuid1", systemName: "System Display")
        XCTAssertEqual(result, "System Display")
    }

    // MARK: - toggledIgnoredDisplayUUIDs(_:uuid:visible:)

    func test_toggledIgnoredDisplayUUIDs_removesUUID_whenMadeVisible() {
        let result = DisplayManager.toggledIgnoredDisplayUUIDs(["uuid1", "uuid2"], uuid: "uuid1", visible: true)
        XCTAssertEqual(result, ["uuid2"])
    }

    func test_toggledIgnoredDisplayUUIDs_insertsUUID_whenHidden() {
        let result = DisplayManager.toggledIgnoredDisplayUUIDs(["uuid1"], uuid: "uuid2", visible: false)
        XCTAssertEqual(Set(result), Set(["uuid1", "uuid2"]))
    }

    func test_toggledIgnoredDisplayUUIDs_visibleNoOp_whenAlreadyVisible() {
        let result = DisplayManager.toggledIgnoredDisplayUUIDs(["uuid1"], uuid: "uuid2", visible: true)
        XCTAssertEqual(result, ["uuid1"])
    }

    func test_toggledIgnoredDisplayUUIDs_hiddenNoOp_whenAlreadyHidden() {
        let result = DisplayManager.toggledIgnoredDisplayUUIDs(["uuid1", "uuid2"], uuid: "uuid2", visible: false)
        XCTAssertEqual(Set(result), Set(["uuid1", "uuid2"]))
    }

    // MARK: - toggledCustomDisplayNames(_:uuid:newName:)

    func test_toggledCustomDisplayNames_setsName_whenNonEmpty() {
        let result = DisplayManager.toggledCustomDisplayNames([:], uuid: "uuid1", newName: "My Display")
        XCTAssertEqual(result, ["uuid1": "My Display"])
    }

    func test_toggledCustomDisplayNames_removesName_whenEmpty() {
        let result = DisplayManager.toggledCustomDisplayNames(["uuid1": "My Display"], uuid: "uuid1", newName: "")
        XCTAssertEqual(result, [:])
    }

    func test_toggledCustomDisplayNames_overwritesExistingName() {
        let result = DisplayManager.toggledCustomDisplayNames(["uuid1": "Old"], uuid: "uuid1", newName: "New")
        XCTAssertEqual(result, ["uuid1": "New"])
    }

    // MARK: - sortedVisibleDisplays(_:ignoredUUIDs:)

    func test_sortedVisibleDisplays_filtersIgnoredUUIDs() {
        let displays = [
            makeDisplay(name: "Beta", uuid: "b"),
            makeDisplay(name: "Alpha", uuid: "a"),
        ]
        let result = DisplayManager.sortedVisibleDisplays(displays, ignoredUUIDs: ["a"])
        XCTAssertEqual(result.map { $0.uuid }, ["b"])
    }

    func test_sortedVisibleDisplays_sortsAlphabeticallyCaseInsensitive() {
        let displays = [
            makeDisplay(name: "zebra", uuid: "z"),
            makeDisplay(name: "Apple", uuid: "a"),
            makeDisplay(name: "banana", uuid: "b"),
        ]
        let result = DisplayManager.sortedVisibleDisplays(displays, ignoredUUIDs: [])
        XCTAssertEqual(result.map { $0.name }, ["Apple", "banana", "zebra"])
    }

    func test_sortedVisibleDisplays_emptyIgnoredSet_keepsAllDisplays() {
        let displays = [makeDisplay(name: "Only", uuid: "o")]
        let result = DisplayManager.sortedVisibleDisplays(displays, ignoredUUIDs: [])
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - Helper

    private func makeDisplay(
        name: String,
        uuid: String,
        isBuiltIn: Bool = false
    ) -> DisplayInfo {
        DisplayInfo(
            id: 1,
            name: name,
            uuid: uuid,
            brightness: 0.5,
            volume: 0.5,
            canControlVolume: true,
            isBuiltIn: isBuiltIn
        )
    }

    // MARK: - ddcFraction(current:max:)

    func test_ddcFraction_convertsNormalReading() {
        XCTAssertEqual(DisplayManager.ddcFraction(current: 50, max: 100), 0.5)
        XCTAssertEqual(DisplayManager.ddcFraction(current: 0, max: 100), 0.0)
        XCTAssertEqual(DisplayManager.ddcFraction(current: 100, max: 100), 1.0)
    }

    /// Regression: a flaky DDC channel answers with max == 0, and `current / max`
    /// produced NaN (0/0) or +Inf. Both reached `UInt16(value * 100)`, which traps.
    func test_ddcFraction_returnsNilWhenMaxIsZero() {
        XCTAssertNil(DisplayManager.ddcFraction(current: 0, max: 0))
        XCTAssertNil(DisplayManager.ddcFraction(current: 40, max: 0))
    }

    func test_ddcFraction_clampsReadingAboveMax() {
        XCTAssertEqual(DisplayManager.ddcFraction(current: 200, max: 100), 1.0)
    }

    // MARK: - ddcPercent(fromFraction:)

    func test_ddcPercent_convertsFractionToPercent() {
        XCTAssertEqual(DisplayManager.ddcPercent(fromFraction: 0.0), 0)
        XCTAssertEqual(DisplayManager.ddcPercent(fromFraction: 0.5), 50)
        XCTAssertEqual(DisplayManager.ddcPercent(fromFraction: 1.0), 100)
    }

    /// Regression: `UInt16(Float.nan * 100)` is an unconditional runtime trap, and the
    /// value arrives from a Slider binding whose store could hold a non-finite read.
    func test_ddcPercent_survivesNonFiniteInput() {
        XCTAssertEqual(DisplayManager.ddcPercent(fromFraction: .nan), 0)
        XCTAssertEqual(DisplayManager.ddcPercent(fromFraction: .infinity), 100)
        XCTAssertEqual(DisplayManager.ddcPercent(fromFraction: -.infinity), 0)
    }

    func test_ddcPercent_clampsOutOfRangeInput() {
        XCTAssertEqual(DisplayManager.ddcPercent(fromFraction: -0.4), 0)
        XCTAssertEqual(DisplayManager.ddcPercent(fromFraction: 3.0), 100)
    }
}
