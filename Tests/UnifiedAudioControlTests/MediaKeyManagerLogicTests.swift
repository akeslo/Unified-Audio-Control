import XCTest
import Carbon.HIToolbox
@testable import UnifiedAudioControl

/// Tests for MediaKeyManager's pure data1 decoding. No event tap is created.
final class MediaKeyManagerLogicTests: XCTestCase {

    private func data1(keyCode: Int, flags: Int) -> Int {
        (keyCode << 16) | flags
    }

    func test_decode_keyDown_soundUp() {
        let r = MediaKeyManager.decodeMediaKey(data1: data1(keyCode: Int(NX_KEYTYPE_SOUND_UP), flags: 0x0A00))
        XCTAssertEqual(r.keyCode, Int(NX_KEYTYPE_SOUND_UP))
        XCTAssertTrue(r.keyDown)
    }

    func test_decode_keyUp_isNotKeyDown() {
        let r = MediaKeyManager.decodeMediaKey(data1: data1(keyCode: Int(NX_KEYTYPE_SOUND_DOWN), flags: 0x0B00))
        XCTAssertEqual(r.keyCode, Int(NX_KEYTYPE_SOUND_DOWN))
        XCTAssertFalse(r.keyDown)
    }

    func test_decode_mute_keyDown() {
        let r = MediaKeyManager.decodeMediaKey(data1: data1(keyCode: Int(NX_KEYTYPE_MUTE), flags: 0x0A00))
        XCTAssertEqual(r.keyCode, Int(NX_KEYTYPE_MUTE))
        XCTAssertTrue(r.keyDown)
    }

    func test_decode_ignoresLowFlagBitsAndReservedBits() {
        // Repeat flag (low byte) must not change key-down detection; bits 24-31 are ignored.
        let raw = (0x7F << 24) | data1(keyCode: Int(NX_KEYTYPE_SOUND_UP), flags: 0x0A01)
        let r = MediaKeyManager.decodeMediaKey(data1: raw)
        XCTAssertEqual(r.keyCode, Int(NX_KEYTYPE_SOUND_UP))
        XCTAssertTrue(r.keyDown)
    }
}
