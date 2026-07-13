import XCTest
import CoreAudio
@testable import UnifiedAudioControl

/// Tests for the pure decision functions extracted from `MenuBarManager`:
/// icon selection, device/display matching, and volume resolution.
/// These are unit tests only — no AppKit/CoreAudio hardware access is exercised.
final class MenuBarManagerLogicTests: XCTestCase {

    // MARK: - iconName(isMuted:volume:)

    func test_iconName_returnsMutedIcon_whenMuted_regardlessOfVolume() {
        XCTAssertEqual(MenuBarManager.iconName(isMuted: true, volume: 0.0), "speaker.slash.fill")
        XCTAssertEqual(MenuBarManager.iconName(isMuted: true, volume: 1.0), "speaker.slash.fill")
    }

    func test_iconName_returnsZeroVolumeIcon_whenVolumeIsZero() {
        XCTAssertEqual(MenuBarManager.iconName(isMuted: false, volume: 0.0), "speaker.fill")
    }

    func test_iconName_returnsLowIcon_atLowerBoundary() {
        XCTAssertEqual(MenuBarManager.iconName(isMuted: false, volume: 0.01), "speaker.wave.1.fill")
        XCTAssertEqual(MenuBarManager.iconName(isMuted: false, volume: 0.33), "speaker.wave.1.fill")
    }

    func test_iconName_returnsMidIcon_atUpperOfLowRange() {
        XCTAssertEqual(MenuBarManager.iconName(isMuted: false, volume: 0.34), "speaker.wave.2.fill")
        XCTAssertEqual(MenuBarManager.iconName(isMuted: false, volume: 0.66), "speaker.wave.2.fill")
    }

    func test_iconName_returnsHighIcon_aboveMidRange() {
        XCTAssertEqual(MenuBarManager.iconName(isMuted: false, volume: 0.67), "speaker.wave.3.fill")
        XCTAssertEqual(MenuBarManager.iconName(isMuted: false, volume: 1.0), "speaker.wave.3.fill")
    }

    // MARK: - resolveVolume(canControlVolume:audioVolume:matchedDisplayVolume:)

    func test_resolveVolume_usesAudioVolume_whenDeviceControlsVolumeDirectly() {
        let result = MenuBarManager.resolveVolume(canControlVolume: true, audioVolume: 0.42, matchedDisplayVolume: 0.9)
        XCTAssertEqual(result, 0.42)
    }

    func test_resolveVolume_usesMatchedDisplayVolume_whenDDCControlled() {
        let result = MenuBarManager.resolveVolume(canControlVolume: false, audioVolume: 0.42, matchedDisplayVolume: 0.9)
        XCTAssertEqual(result, 0.9)
    }

    func test_resolveVolume_fallsBackToAudioVolume_whenNoDisplayMatched() {
        let result = MenuBarManager.resolveVolume(canControlVolume: false, audioVolume: 0.42, matchedDisplayVolume: nil)
        XCTAssertEqual(result, 0.42)
    }

    // MARK: - matches(selectedDevice:display:)

    func test_matches_true_whenAudioUIDContainsDisplayUUID() {
        let display = DisplayInfo(id: 1, name: "Studio Display", uuid: "05E39027-0000-0000-1C1F-0103803C2278")
        let device = makeDevice(name: "Something Else", uid: "AppleHDA:05E39027-0000-0000-1C1F-0103803C2278")

        XCTAssertTrue(MenuBarManager.matches(selectedDevice: device, display: display))
    }

    func test_matches_true_whenBothBuiltIn() {
        let display = DisplayInfo(id: 1, name: "Built-in Retina Display", uuid: "", isBuiltIn: true)
        let device = makeDevice(name: "MacBook Pro Speakers", uid: "BuiltInSpeakerDevice", transportType: kAudioDeviceTransportTypeBuiltIn)

        XCTAssertTrue(MenuBarManager.matches(selectedDevice: device, display: display))
    }

    func test_matches_false_whenOneBuiltInAndOtherIsNot() {
        let display = DisplayInfo(id: 1, name: "Built-in Retina Display", uuid: "", isBuiltIn: true)
        let device = makeDevice(name: "External USB Speakers", uid: "USBAudioDevice", transportType: kAudioDeviceTransportTypeUSB)

        XCTAssertFalse(MenuBarManager.matches(selectedDevice: device, display: display))
    }

    func test_matches_true_whenNamesOverlap_asFallback() {
        let display = DisplayInfo(id: 1, name: "Dell U2720Q", uuid: "")
        let device = makeDevice(name: "Dell U2720Q", uid: "SomeUnrelatedUID")

        XCTAssertTrue(MenuBarManager.matches(selectedDevice: device, display: display))
    }

    func test_matches_false_whenNoUUIDBuiltInOrNameOverlap() {
        let display = DisplayInfo(id: 1, name: "LG UltraFine", uuid: "AAAA-BBBB")
        let device = makeDevice(name: "Sonos Speaker", uid: "ZZZZ-YYYY")

        XCTAssertFalse(MenuBarManager.matches(selectedDevice: device, display: display))
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
