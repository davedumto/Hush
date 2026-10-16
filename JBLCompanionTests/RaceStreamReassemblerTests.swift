import XCTest
@testable import JBLCompanion

final class RaceStreamReassemblerTests: XCTestCase {
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

    // Ambient Aware event frame (protocol.md §4): 05 5C 06 00 01 09 05 00 00 0A
    private let ambientEventHex = "055C06000109050000" + "0A"
    // ANC event frame, live-reconfirmed mapping: mode byte 0x01.
    private let ancEventHex = "055C06000109050000" + "01"

    // MARK: - Merged frames in one chunk

    func testTwoCompleteFramesInOneChunkBothComeBackAtOnce() {
        let reassembler = RaceStreamReassembler()
        let chunk = hexData(ambientEventHex + ancEventHex)

        let frames = reassembler.feed(chunk)

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(RaceEventRecognizer.recognize(frames[0]), .noiseMode(.ambientAware, rawByte: 0x0A))
        XCTAssertEqual(RaceEventRecognizer.recognize(frames[1]), .noiseMode(.anc, rawByte: 0x01))
        XCTAssertTrue(reassembler.pendingBytes.isEmpty)
    }

    func testThreeCompleteFramesInOneChunk() {
        let reassembler = RaceStreamReassembler()
        let chunk = hexData(ambientEventHex + ancEventHex + ambientEventHex)

        let frames = reassembler.feed(chunk)

        XCTAssertEqual(frames.count, 3)
        XCTAssertTrue(reassembler.pendingBytes.isEmpty)
    }

    // MARK: - A single frame split across multiple feeds

    func testFrameSplitAcrossTwoChunks() {
        let reassembler = RaceStreamReassembler()
        let full = hexData(ambientEventHex)
        let firstHalf = full.prefix(5)
        let secondHalf = full.suffix(from: full.startIndex + 5)

        let firstResult = reassembler.feed(Data(firstHalf))
        XCTAssertTrue(firstResult.isEmpty, "nothing should parse yet — the frame isn't complete")
        XCTAssertEqual(reassembler.pendingBytes, Data(firstHalf))

        let secondResult = reassembler.feed(Data(secondHalf))
        XCTAssertEqual(secondResult.count, 1)
        XCTAssertEqual(RaceEventRecognizer.recognize(secondResult[0]), .noiseMode(.ambientAware, rawByte: 0x0A))
        XCTAssertTrue(reassembler.pendingBytes.isEmpty)
    }

    func testFrameSplitByteByByteAcrossManyChunks() {
        let reassembler = RaceStreamReassembler()
        let full = [UInt8](hexData(ambientEventHex))

        var lastResult: [RaceFrame] = []
        for byte in full {
            lastResult = reassembler.feed(Data([byte]))
        }

        XCTAssertEqual(lastResult.count, 1, "the frame should only complete on the very last byte")
        XCTAssertEqual(RaceEventRecognizer.recognize(lastResult[0]), .noiseMode(.ambientAware, rawByte: 0x0A))
        XCTAssertTrue(reassembler.pendingBytes.isEmpty)
    }

    func testSecondFrameArrivesSplitRightAfterAFirstCompleteFrame() {
        let reassembler = RaceStreamReassembler()
        let full = hexData(ambientEventHex)
        let firstChunk = hexData(ambientEventHex) + full.prefix(4) // complete frame + partial second
        let secondChunk = full.suffix(from: full.startIndex + 4)

        let firstResult = reassembler.feed(firstChunk)
        XCTAssertEqual(firstResult.count, 1, "only the complete first frame should come back")
        XCTAssertEqual(reassembler.pendingBytes, Data(full.prefix(4)))

        let secondResult = reassembler.feed(Data(secondChunk))
        XCTAssertEqual(secondResult.count, 1)
        XCTAssertTrue(reassembler.pendingBytes.isEmpty)
    }

    // MARK: - Partial frame left hanging

    func testPartialFrameStaysPendingAndIsFlaggable() {
        let reassembler = RaceStreamReassembler()
        let partial = hexData(ambientEventHex).prefix(6) // header-ish, missing the back half

        let result = reassembler.feed(Data(partial))

        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(reassembler.pendingBytes.isEmpty, "a caller closing the channel now should see this and flag it")
        XCTAssertEqual(reassembler.pendingBytes, Data(partial))
    }

    func testEmptyFeedChangesNothing() {
        let reassembler = RaceStreamReassembler()
        XCTAssertTrue(reassembler.feed(Data()).isEmpty)
        XCTAssertTrue(reassembler.pendingBytes.isEmpty)
    }
}
