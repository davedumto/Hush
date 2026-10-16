import XCTest
@testable import JBLCompanion

final class RaceFrameParserTests: XCTestCase {
    // All hex below is lifted verbatim from ~/jbl-recon/protocol.md (§4 noise-control frames,
    // §5 battery frame), payload-only form (the "05 <type> ..." bytes after the ATT notification
    // header is stripped).

    private func hexData(_ hex: String) -> Data {
        var data = Data()
        var h = hex
        while h.count >= 2 {
            let byteString = String(h.prefix(2))
            h.removeFirst(2)
            data.append(UInt8(byteString, radix: 16)!)
        }
        return data
    }

    // MARK: - Single frame

    func testParsesSingleCommandFrame() {
        // protocol.md §4: ANC on command
        let data = hexData("055A0600060E000A0904")
        let frames = RaceFrameParser.parseFrames(from: data)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].type, .command)
        XCTAssertEqual(frames[0].id, 0x0E06) // bytes "06 0E" LE
        XCTAssertEqual(frames[0].payload, hexData("000A0904"))
    }

    func testParsesSingleStatusFrame() {
        // protocol.md §5: battery status event, 0x46 = 70%
        let data = hexData("055D0500D60C000046")
        let frames = RaceFrameParser.parseFrames(from: data)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].type, .status)
        XCTAssertEqual(frames[0].id, 0x0CD6) // bytes "D6 0C" LE
        XCTAssertEqual(frames[0].payload, hexData("000046"))
    }

    // MARK: - Multi-frame notification

    func testParsesMultipleFramesPackedInOneBuffer() {
        // protocol.md §5, frame 915: three commands bundled in one ATT write —
        // D6 0C / 09 00 / 0B 00. The frame format doesn't care about direction, so this proves
        // the parser handles a buffer carrying more than one frame back-to-back.
        let data = hexData("055A0300D60C00" + "055A0300090000" + "055A02000B00")
        let frames = RaceFrameParser.parseFrames(from: data)

        XCTAssertEqual(frames.count, 3)

        XCTAssertEqual(frames[0].type, .command)
        XCTAssertEqual(frames[0].id, 0x0CD6)
        XCTAssertEqual(frames[0].payload, hexData("00"))

        XCTAssertEqual(frames[1].type, .command)
        XCTAssertEqual(frames[1].id, 0x0009)
        XCTAssertEqual(frames[1].payload, hexData("00"))

        XCTAssertEqual(frames[2].type, .command)
        XCTAssertEqual(frames[2].id, 0x000B)
        XCTAssertEqual(frames[2].payload, Data())
    }

    // MARK: - Truncated frame

    func testTruncatedFrameMissingPayloadBytesIsDropped() {
        // Ambient Aware event frame (protocol.md §4) with its final two payload bytes cut off:
        // len says 6 bytes follow the id16, but only 4 are actually present (8 bytes total instead
        // of the full 10).
        let truncated = hexData("055C060001090500")
        XCTAssertTrue(RaceFrameParser.parseFrames(from: truncated).isEmpty)
    }

    func testBufferShorterThanMinimumHeaderIsDropped() {
        let tooShort = hexData("055C0600") // only 4 bytes — can't even read id16
        XCTAssertTrue(RaceFrameParser.parseFrames(from: tooShort).isEmpty)
    }

    func testUnknownSyncByteIsDropped() {
        let badSync = hexData("FF5C0600010905000A")
        XCTAssertTrue(RaceFrameParser.parseFrames(from: badSync).isEmpty)
    }

    func testUnknownTypeByteIsDropped() {
        let badType = hexData("05990600010905000A")
        XCTAssertTrue(RaceFrameParser.parseFrames(from: badType).isEmpty)
    }

    // MARK: - Noise-mode event recognition (protocol.md §4; extracts the raw byte only — mapping
    // it to a NoiseMode is per-profile now, see DeviceProfileEventMapTests/StandardRaceEventByteMap)

    func testRecognizesOff() {
        // Live-confirmed: user set the headphones to Off (neither ANC, Ambient, nor TalkThru
        // active) and the device reported 0x00.
        let frame = RaceFrameParser.parseFrames(from: hexData("055C06000109050000" + "00")).first!
        XCTAssertEqual(RaceEventRecognizer.recognize(frame), .noiseMode(rawByte: 0x00))
    }

    func testRecognizesANC() {
        // Live-confirmed: user had ANC physically on; device reported 0x01.
        let frame = RaceFrameParser.parseFrames(from: hexData("055C06000109050000" + "01")).first!
        XCTAssertEqual(RaceEventRecognizer.recognize(frame), .noiseMode(rawByte: 0x01))
    }

    func testRecognizesTalkThru() {
        // Live-confirmed: user had TalkThru physically active; device reported 0x09.
        let frame = RaceFrameParser.parseFrames(from: hexData("055C06000109050000" + "09")).first!
        XCTAssertEqual(RaceEventRecognizer.recognize(frame), .noiseMode(rawByte: 0x09))
    }

    func testRecognizesAmbientAware() {
        // Unchanged from the original capture — never disputed by the live re-test.
        let frame = RaceFrameParser.parseFrames(from: hexData("055C06000109050000" + "0A")).first!
        XCTAssertEqual(RaceEventRecognizer.recognize(frame), .noiseMode(rawByte: 0x0A))
    }

    func testRecognizesAnyByteIncludingUnmappedOnes() {
        // recognize() only extracts the raw byte now — it never judges whether the byte is a
        // known mode, so even 0xFF is still "recognized" as a noise-mode event.
        let frame = RaceFrameParser.parseFrames(from: hexData("055C06000109050000" + "FF")).first!
        XCTAssertEqual(RaceEventRecognizer.recognize(frame), .noiseMode(rawByte: 0xFF))
    }

    // MARK: - StandardRaceEventByteMap (the 770NC's hardware-verified mapping)

    func testStandardByteMapMatchesHardwareVerifiedValues() {
        XCTAssertEqual(StandardRaceEventByteMap.noiseMode(forEventByte: 0x00), .off)
        XCTAssertEqual(StandardRaceEventByteMap.noiseMode(forEventByte: 0x01), .anc)
        XCTAssertEqual(StandardRaceEventByteMap.noiseMode(forEventByte: 0x09), .talkThru)
        XCTAssertEqual(StandardRaceEventByteMap.noiseMode(forEventByte: 0x0A), .ambientAware)
    }

    func testStandardByteMapTreatsAnyOtherByteAsUnknown() {
        XCTAssertEqual(StandardRaceEventByteMap.noiseMode(forEventByte: 0xFF), .unknown)
    }

    func testDoesNotRecognizeNonEventFrameAsNoiseMode() {
        // Same id/payload shape but wrong type (response, not event) must not be recognized.
        let data = hexData("055B06000109050000" + "09")
        let frame = RaceFrameParser.parseFrames(from: data).first!
        XCTAssertNil(RaceEventRecognizer.recognize(frame))
    }

    func testDoesNotRecognizeUnrelatedEventID() {
        // Correct type and payload shape, wrong id — must not be mistaken for a noise-mode event.
        let data = hexData("055C0600AABB05000009")
        let frame = RaceFrameParser.parseFrames(from: data).first!
        XCTAssertNil(RaceEventRecognizer.recognize(frame))
    }
}
