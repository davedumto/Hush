import XCTest
@testable import JBLCompanion

final class EqualizerPresetTests: XCTestCase {
    func testEveryPresetHasExactlyTwelveFrames() {
        for preset in EqualizerPreset.allCases {
            XCTAssertEqual(preset.transaction.count, 12, "\(preset.displayName) should have 12 captured frames")
        }
    }

    func testEveryFrameStartsWithTheRaceCommandHeader() {
        for preset in EqualizerPreset.allCases {
            for frame in preset.transaction {
                XCTAssertEqual(frame.first, 0x05, "\(preset.displayName) frame missing the 05 RACE marker")
                XCTAssertEqual(frame.dropFirst().first, 0x5A, "\(preset.displayName) frame isn't a 5A command")
            }
        }
    }

    /// Hardware-verified, one preset at a time (EqualizerPreset's own doc comment) — this is the
    /// regression guard: an early attempt that inferred preset identity from tap order in a
    /// multi-tap batch capture produced a real, confirmed-wrong mapping (Club's data labeled
    /// "ExtremeBass"). Every preset's own ~432-byte curve frame must be genuinely distinct from
    /// every other's, not an accidental duplicate.
    func testEveryPresetsCurveFrameIsDistinctFromEveryOtherPresets() {
        func curveFrame(_ preset: EqualizerPreset) -> Data {
            preset.transaction.max { $0.count < $1.count }!
        }
        let presets = EqualizerPreset.allCases
        for i in presets.indices {
            for j in presets.indices where j > i {
                XCTAssertNotEqual(
                    curveFrame(presets[i]), curveFrame(presets[j]),
                    "\(presets[i].displayName) and \(presets[j].displayName) have identical curve data"
                )
            }
        }
    }

    /// EqualizerPreset's own doc comment: turning the Equalizer off sends .studio's own
    /// transaction verbatim — there is no separate "off" transaction, confirmed byte-for-byte
    /// identical capture-to-capture. AppDelegate.requestEqualizerOff relies on exactly this.
    func testThereIsNoSeparateOffTransactionByDesign() {
        // Documents the design decision directly on the type that encodes it, rather than
        // asserting against a nonexistent `.off` case.
        XCTAssertFalse(EqualizerPreset.allCases.contains { $0.rawValue == "off" })
    }
}
