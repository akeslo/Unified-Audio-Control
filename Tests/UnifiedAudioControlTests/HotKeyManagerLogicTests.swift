import XCTest
@testable import UnifiedAudioControl

/// Tests for HotKeyManager pure logic functions.
/// These are unit tests only — no Carbon hotkey registration is exercised.
final class HotKeyManagerLogicTests: XCTestCase {

    // MARK: - storedHotKey(keyCodeObject:modifiersObject:)

    func test_storedHotKey_returnsNil_whenNothingPersisted() {
        XCTAssertNil(HotKeyManager.storedHotKey(keyCodeObject: nil, modifiersObject: nil))
    }

    /// Regression: restore was gated on `keyCode != 0`, but `kVK_ANSI_A == 0`, so a
    /// hotkey bound to the A key was persisted and then silently never re-registered
    /// on the next launch. A stored 0 is a real key, not an absent value.
    func test_storedHotKey_restoresKeyCodeZero() {
        let result = HotKeyManager.storedHotKey(keyCodeObject: 0, modifiersObject: 1_048_576)
        XCTAssertEqual(result?.keyCode, 0)
        XCTAssertEqual(result?.modifiers, 1_048_576)
    }

    func test_storedHotKey_restoresOrdinaryKeyCode() {
        let result = HotKeyManager.storedHotKey(keyCodeObject: 49, modifiersObject: 524_288)
        XCTAssertEqual(result?.keyCode, 49)
        XCTAssertEqual(result?.modifiers, 524_288)
    }

    func test_storedHotKey_defaultsModifiersToZero_whenAbsent() {
        let result = HotKeyManager.storedHotKey(keyCodeObject: 12, modifiersObject: nil)
        XCTAssertEqual(result?.keyCode, 12)
        XCTAssertEqual(result?.modifiers, 0)
    }

    func test_storedHotKey_returnsNil_whenKeyCodeIsNotAnInt() {
        XCTAssertNil(HotKeyManager.storedHotKey(keyCodeObject: "49", modifiersObject: 0))
    }
}
