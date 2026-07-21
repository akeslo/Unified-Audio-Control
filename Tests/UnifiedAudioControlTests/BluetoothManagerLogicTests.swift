import XCTest
@testable import UnifiedAudioControl

/// Tests for the pure decision/matching functions extracted from `BluetoothManager`:
/// audio-service/name-keyword detection, class-of-device major-class checks, recent-connection
/// inclusion windowing, and display-name resolution. Unit tests only — no IOBluetooth hardware
/// access is exercised.
final class BluetoothManagerLogicTests: XCTestCase {

    // MARK: - serviceClassIndicatesAudio(_:)

    func test_serviceClassIndicatesAudio_true_forA2DPRange() {
        XCTAssertTrue(BluetoothManager.serviceClassIndicatesAudio("BluetoothSDPUUID16(0x110D)"))
    }

    func test_serviceClassIndicatesAudio_true_forHandsfreeRange() {
        XCTAssertTrue(BluetoothManager.serviceClassIndicatesAudio("BluetoothSDPUUID16(0x111E)"))
    }

    func test_serviceClassIndicatesAudio_false_forUnrelatedService() {
        // OBEX File Transfer (0x1200) — outside both the 0x110x and 0x111x substring matches.
        XCTAssertFalse(BluetoothManager.serviceClassIndicatesAudio("BluetoothSDPUUID16(0x1200)"))
    }

    // MARK: - nameIndicatesAudioDevice(_:)

    func test_nameIndicatesAudioDevice_true_forKnownKeyword() {
        XCTAssertTrue(BluetoothManager.nameIndicatesAudioDevice("Alice's AirPods Pro"))
        XCTAssertTrue(BluetoothManager.nameIndicatesAudioDevice("Bose QuietComfort"))
    }

    func test_nameIndicatesAudioDevice_isCaseInsensitive() {
        XCTAssertTrue(BluetoothManager.nameIndicatesAudioDevice("JABRA ELITE"))
    }

    func test_nameIndicatesAudioDevice_false_forUnrelatedName() {
        XCTAssertFalse(BluetoothManager.nameIndicatesAudioDevice("Magic Keyboard"))
    }

    func test_nameIndicatesAudioDevice_false_forEmptyName() {
        XCTAssertFalse(BluetoothManager.nameIndicatesAudioDevice(""))
    }

    // MARK: - isAudioVideoMajorClass(_:)

    func test_isAudioVideoMajorClass_true_forAudioVideoMajorClass() {
        // Major class 0x04 in bits 8-12: 0x04 << 8 = 0x0400
        XCTAssertTrue(BluetoothManager.isAudioVideoMajorClass(0x0400))
    }

    func test_isAudioVideoMajorClass_false_forOtherMajorClass() {
        // Major class 0x01 = Computer
        XCTAssertFalse(BluetoothManager.isAudioVideoMajorClass(0x0100))
    }

    func test_isAudioVideoMajorClass_ignoresMinorClassBits() {
        // Major 0x04 with minor bits set
        XCTAssertTrue(BluetoothManager.isAudioVideoMajorClass(0x0404))
    }

    // MARK: - shouldIncludeDevice(isConnected:lastConnectionDate:now:recentWindow:)

    func test_shouldIncludeDevice_true_whenCurrentlyConnected() {
        XCTAssertTrue(BluetoothManager.shouldIncludeDevice(isConnected: true, lastConnectionDate: nil))
    }

    func test_shouldIncludeDevice_false_whenDisconnectedAndNeverConnected() {
        XCTAssertFalse(BluetoothManager.shouldIncludeDevice(isConnected: false, lastConnectionDate: nil))
    }

    func test_shouldIncludeDevice_true_whenWithinRecentWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastConnection = now.addingTimeInterval(-3600) // 1 hour ago
        XCTAssertTrue(BluetoothManager.shouldIncludeDevice(isConnected: false, lastConnectionDate: lastConnection, now: now))
    }

    func test_shouldIncludeDevice_false_whenOutsideRecentWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastConnection = now.addingTimeInterval(-4 * 24 * 3600) // 4 days ago
        XCTAssertFalse(BluetoothManager.shouldIncludeDevice(isConnected: false, lastConnectionDate: lastConnection, now: now))
    }

    func test_shouldIncludeDevice_respectsCustomWindow() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastConnection = now.addingTimeInterval(-3600) // 1 hour ago
        XCTAssertFalse(BluetoothManager.shouldIncludeDevice(isConnected: false, lastConnectionDate: lastConnection, now: now, recentWindow: 1800))
    }

    // MARK: - resolveDisplayName(isConnected:currentName:storedName:)

    func test_resolveDisplayName_usesCurrentName_whenConnected() {
        let result = BluetoothManager.resolveDisplayName(isConnected: true, currentName: "Live Name", storedName: "Stored Name")
        XCTAssertEqual(result, "Live Name")
    }

    func test_resolveDisplayName_fallsBackToUnknown_whenConnectedWithNoCurrentName() {
        let result = BluetoothManager.resolveDisplayName(isConnected: true, currentName: nil, storedName: "Stored Name")
        XCTAssertEqual(result, "Unknown Device")
    }

    func test_resolveDisplayName_usesStoredName_whenDisconnected() {
        let result = BluetoothManager.resolveDisplayName(isConnected: false, currentName: "Live Name", storedName: "Stored Name")
        XCTAssertEqual(result, "Stored Name")
    }

    func test_resolveDisplayName_fallsBackToCurrentName_whenDisconnectedWithNoStoredName() {
        let result = BluetoothManager.resolveDisplayName(isConnected: false, currentName: "Live Name", storedName: nil)
        XCTAssertEqual(result, "Live Name")
    }

    func test_resolveDisplayName_fallsBackToUnknown_whenDisconnectedWithNeitherName() {
        let result = BluetoothManager.resolveDisplayName(isConnected: false, currentName: nil, storedName: nil)
        XCTAssertEqual(result, "Unknown Device")
    }

    // MARK: - sortedByName(_:)

    func test_sortedByName_sortsAlphabeticallyCaseInsensitive() {
        let devices = [
            makeDevice(name: "zebra"),
            makeDevice(name: "Apple"),
            makeDevice(name: "banana"),
        ]
        let result = BluetoothManager.sortedByName(devices)
        XCTAssertEqual(result.map { $0.name }, ["Apple", "banana", "zebra"])
    }

    // MARK: - Helpers

    private func makeDevice(name: String, isConnected: Bool = false, isPaired: Bool = true) -> BluetoothAudioDevice {
        BluetoothAudioDevice(id: name, name: name, isConnected: isConnected, isPaired: isPaired)
    }
}
