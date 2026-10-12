import XCTest
@testable import UnifiedAudioControl

/// Tests for IntelDDC's pure packet building/parsing helpers.
/// No IOKit/framebuffer access is exercised.
final class IntelDDCPacketTests: XCTestCase {

    // MARK: - writePacket

    func test_writePacket_layout_forBrightness() {
        // VCP 0x10 (brightness) = 50
        let p = IntelDDC.writePacket(command: 0x10, value: 50)
        XCTAssertEqual(p.count, 7)
        XCTAssertEqual(Array(p[0...5]), [0x51, 0x84, 0x03, 0x10, 0x00, 50])
    }

    func test_writePacket_splitsValueIntoHighAndLowBytes() {
        let p = IntelDDC.writePacket(command: 0x62, value: 0x1234)
        XCTAssertEqual(p[4], 0x12)
        XCTAssertEqual(p[5], 0x34)
    }

    func test_writePacket_checksumIsXorOfSeed6EAndPayload() {
        for (cmd, val) in [(UInt8(0x10), UInt16(0)), (0x62, 100), (0xD6, 0xFFFF), (0x8D, 1)] {
            let p = IntelDDC.writePacket(command: cmd, value: val)
            let expected = p[0..<6].reduce(UInt8(0x6E)) { $0 ^ $1 }
            XCTAssertEqual(p[6], expected, "cmd \(cmd) value \(val)")
        }
    }

    func test_writePacket_knownChecksum() {
        // 0x6E ^ 0x51 ^ 0x84 ^ 0x03 ^ 0x10 ^ 0x00 ^ 0x32 = 0x9A
        XCTAssertEqual(IntelDDC.writePacket(command: 0x10, value: 0x32).last, 0x9A)
    }

    // MARK: - readRequestPacket

    func test_readRequestPacket_layoutAndChecksum() {
        let p = IntelDDC.readRequestPacket(command: 0x62)
        XCTAssertEqual(Array(p[0...3]), [0x51, 0x82, 0x01, 0x62])
        XCTAssertEqual(p[4], 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x62)
        XCTAssertEqual(p.count, 5)
    }

    // MARK: - parseReadReply

    /// Builds an 11-byte reply with a valid checksum (seed 0x50).
    private func reply(type: UInt8 = 0x02, result: UInt8 = 0x00, max: UInt8 = 100, current: UInt8 = 40) -> [UInt8] {
        var r: [UInt8] = [0x6E, 0x88, type, result, 0x62, 0x00, 0x00, max, 0x00, current, 0x00]
        var c: UInt8 = 0x50
        for b in r[0..<10] { c ^= b }
        r[10] = c
        return r
    }

    func test_parseReadReply_validReply_returnsCurrentAndMax() {
        XCTAssertEqual(IntelDDC.parseReadReply(reply(max: 100, current: 40)), .value(current: 40, max: 100))
    }

    func test_parseReadReply_badChecksum_isReported() {
        var r = reply()
        r[10] ^= 0xFF
        guard case let .checksumMismatch(expected, calculated) = IntelDDC.parseReadReply(r) else {
            return XCTFail("expected checksumMismatch")
        }
        XCTAssertEqual(expected, r[10])
        XCTAssertNotEqual(expected, calculated)
    }

    func test_parseReadReply_wrongResponseType_isReported() {
        XCTAssertEqual(IntelDDC.parseReadReply(reply(type: 0x03)), .wrongResponseType(got: 0x03))
    }

    func test_parseReadReply_nonZeroResultCode_isUnsupported() {
        XCTAssertEqual(IntelDDC.parseReadReply(reply(result: 0x01)), .unsupported)
    }

    func test_parseReadReply_checksumIsCheckedBeforeResponseType() {
        var r = reply(type: 0x03)
        r[10] ^= 0x01
        if case .checksumMismatch = IntelDDC.parseReadReply(r) { return }
        XCTFail("checksum must be validated first")
    }
}
