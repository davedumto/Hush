import XCTest
@testable import JBLCompanion

final class DeviceToggleTests: XCTestCase {
    func testMaxVolumeLimiterFramesMatchTheCapturedBytes() {
        XCTAssertEqual(DeviceToggle.maxVolumeLimiter.commandFrame(on: true), Data([0x05, 0x5A, 0x03, 0x00, 0x15, 0x00, 0x01]))
        XCTAssertEqual(DeviceToggle.maxVolumeLimiter.commandFrame(on: false), Data([0x05, 0x5A, 0x03, 0x00, 0x15, 0x00, 0x00]))
    }

    func testVoicePromptFramesMatchTheCapturedBytes() {
        XCTAssertEqual(DeviceToggle.voicePrompt.commandFrame(on: true), Data([0x05, 0x5A, 0x05, 0x00, 0x82, 0x2C, 0x09, 0x00, 0x00]))
        XCTAssertEqual(DeviceToggle.voicePrompt.commandFrame(on: false), Data([0x05, 0x5A, 0x05, 0x00, 0x82, 0x2C, 0x09, 0x00, 0xFF]))
    }

    func testBothStateFramesContainsExactlyOnAndOff() {
        for toggle in [DeviceToggle.maxVolumeLimiter, DeviceToggle.voicePrompt] {
            XCTAssertEqual(toggle.bothStateFrames, [toggle.commandFrame(on: true), toggle.commandFrame(on: false)])
            XCTAssertNotEqual(toggle.commandFrame(on: true), toggle.commandFrame(on: false))
        }
    }

    func testEveryFrameStartsWithTheRaceCommandHeader() {
        for toggle in [DeviceToggle.maxVolumeLimiter, DeviceToggle.voicePrompt] {
            for frame in toggle.bothStateFrames {
                XCTAssertEqual(frame.first, 0x05)
                XCTAssertEqual(frame.dropFirst().first, 0x5A)
            }
        }
    }
}
