import XCTest
import CoreAudio
@testable import UnifiedAudioControl

/// Tests for the pure decision/matching functions extracted from `AudioDeviceManager`:
/// UID persistence parsing, name resolution, device sorting/filtering, and aggregate-device
/// volume/settability aggregation. Unit tests only — no CoreAudio hardware access is exercised.
final class AudioDeviceManagerLogicTests: XCTestCase {

    // MARK: - parseIgnoredUIDs(_:)

    func test_parseIgnoredUIDs_emptyString_returnsEmptySet() {
        XCTAssertEqual(AudioDeviceManager.parseIgnoredUIDs(""), [])
    }

    func test_parseIgnoredUIDs_splitsOnComma() {
        XCTAssertEqual(AudioDeviceManager.parseIgnoredUIDs("uid1,uid2,uid3"), ["uid1", "uid2", "uid3"])
    }

    func test_parseIgnoredUIDs_singleValue() {
        XCTAssertEqual(AudioDeviceManager.parseIgnoredUIDs("onlyOne"), ["onlyOne"])
    }

    // MARK: - toggledIgnoredUIDs(_:uid:visible:)

    func test_toggledIgnoredUIDs_removesUID_whenMadeVisible() {
        let result = AudioDeviceManager.toggledIgnoredUIDs(["a", "b"], uid: "a", visible: true)
        XCTAssertEqual(result, ["b"])
    }

    func test_toggledIgnoredUIDs_insertsUID_whenHidden() {
        let result = AudioDeviceManager.toggledIgnoredUIDs(["a"], uid: "b", visible: false)
        XCTAssertEqual(result, ["a", "b"])
    }

    func test_toggledIgnoredUIDs_visibleNoOp_whenAlreadyVisible() {
        let result = AudioDeviceManager.toggledIgnoredUIDs(["a"], uid: "z", visible: true)
        XCTAssertEqual(result, ["a"])
    }

    // MARK: - toggledCustomNames(_:uid:newName:)

    func test_toggledCustomNames_setsName_whenNonEmpty() {
        let result = AudioDeviceManager.toggledCustomNames([:], uid: "uid1", newName: "My Speaker")
        XCTAssertEqual(result, ["uid1": "My Speaker"])
    }

    func test_toggledCustomNames_removesName_whenEmpty() {
        let result = AudioDeviceManager.toggledCustomNames(["uid1": "My Speaker"], uid: "uid1", newName: "")
        XCTAssertEqual(result, [:])
    }

    func test_toggledCustomNames_overwritesExistingName() {
        let result = AudioDeviceManager.toggledCustomNames(["uid1": "Old"], uid: "uid1", newName: "New")
        XCTAssertEqual(result, ["uid1": "New"])
    }

    // MARK: - resolveDisplayName(customNames:uid:systemName:)

    func test_resolveDisplayName_usesCustomName_whenPresent() {
        let result = AudioDeviceManager.resolveDisplayName(customNames: ["uid1": "Custom"], uid: "uid1", systemName: "System Name")
        XCTAssertEqual(result, "Custom")
    }

    func test_resolveDisplayName_fallsBackToSystemName_whenNoCustomName() {
        let result = AudioDeviceManager.resolveDisplayName(customNames: [:], uid: "uid1", systemName: "System Name")
        XCTAssertEqual(result, "System Name")
    }

    // MARK: - sortedVisibleDevices(_:ignoredUIDs:)

    func test_sortedVisibleDevices_filtersIgnoredUIDs() {
        let devices = [
            makeDevice(name: "Beta", uid: "b"),
            makeDevice(name: "Alpha", uid: "a"),
        ]
        let result = AudioDeviceManager.sortedVisibleDevices(devices, ignoredUIDs: ["a"])
        XCTAssertEqual(result.map { $0.uid }, ["b"])
    }

    func test_sortedVisibleDevices_sortsAlphabeticallyCaseInsensitive() {
        let devices = [
            makeDevice(name: "zebra", uid: "z"),
            makeDevice(name: "Apple", uid: "a"),
            makeDevice(name: "banana", uid: "b"),
        ]
        let result = AudioDeviceManager.sortedVisibleDevices(devices, ignoredUIDs: [])
        XCTAssertEqual(result.map { $0.name }, ["Apple", "banana", "zebra"])
    }

    func test_sortedVisibleDevices_emptyIgnoredSet_keepsAllDevices() {
        let devices = [makeDevice(name: "Only", uid: "o")]
        let result = AudioDeviceManager.sortedVisibleDevices(devices, ignoredUIDs: [])
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - hasOutputStreams(propertySize:)

    func test_hasOutputStreams_true_whenPropertySizePositive() {
        XCTAssertTrue(AudioDeviceManager.hasOutputStreams(propertySize: 32))
    }

    func test_hasOutputStreams_false_whenPropertySizeZero() {
        XCTAssertFalse(AudioDeviceManager.hasOutputStreams(propertySize: 0))
    }

    // MARK: - hasOutputStreams(status:propertySize:)

    func test_hasOutputStreams_true_whenQuerySucceedsWithStreams() {
        XCTAssertTrue(AudioDeviceManager.hasOutputStreams(status: noErr, propertySize: 32))
    }

    func test_hasOutputStreams_false_whenQuerySucceedsWithNoStreams() {
        XCTAssertFalse(AudioDeviceManager.hasOutputStreams(status: noErr, propertySize: 0))
    }

    /// Regression: the caller seeded `propertySize` to 256 and discarded the status,
    /// so a failed query returned the seed — and the seed meant "has output streams".
    /// Input-only devices could be listed as outputs and made the system default.
    func test_hasOutputStreams_false_whenQueryFails_regardlessOfSizeSeed() {
        XCTAssertFalse(AudioDeviceManager.hasOutputStreams(status: OSStatus(-1), propertySize: 256))
        XCTAssertFalse(AudioDeviceManager.hasOutputStreams(status: OSStatus(-1), propertySize: 0))
    }

    // MARK: - isAggregateTransportType(_:)

    func test_isAggregateTransportType_true_forAggregateConstant() {
        XCTAssertTrue(AudioDeviceManager.isAggregateTransportType(kAudioDeviceTransportTypeAggregate))
    }

    func test_isAggregateTransportType_false_forOtherTransports() {
        XCTAssertFalse(AudioDeviceManager.isAggregateTransportType(kAudioDeviceTransportTypeUSB))
        XCTAssertFalse(AudioDeviceManager.isAggregateTransportType(kAudioDeviceTransportTypeBuiltIn))
    }

    // MARK: - maxVolume(_:)

    func test_maxVolume_returnsZero_whenEmpty() {
        XCTAssertEqual(AudioDeviceManager.maxVolume([]), 0.0)
    }

    func test_maxVolume_returnsMaximum() {
        XCTAssertEqual(AudioDeviceManager.maxVolume([0.2, 0.8, 0.5]), 0.8)
    }

    func test_maxVolume_singleValue() {
        XCTAssertEqual(AudioDeviceManager.maxVolume([0.33]), 0.33)
    }

    // MARK: - anySettable(_:)

    func test_anySettable_false_whenEmpty() {
        XCTAssertFalse(AudioDeviceManager.anySettable([]))
    }

    func test_anySettable_true_whenAnyTrue() {
        XCTAssertTrue(AudioDeviceManager.anySettable([false, false, true]))
    }

    func test_anySettable_false_whenAllFalse() {
        XCTAssertFalse(AudioDeviceManager.anySettable([false, false]))
    }

    // MARK: - Helpers

    private func makeDevice(
        name: String,
        uid: String,
        transportType: UInt32 = kAudioDeviceTransportTypeUSB
    ) -> AudioDevice {
        AudioDevice(
            id: AudioDeviceID(1),
            name: name,
            systemName: name,
            uid: uid,
            isAggregate: false,
            transportType: transportType
        )
    }
}
