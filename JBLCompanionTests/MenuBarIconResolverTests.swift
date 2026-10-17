import XCTest
@testable import JBLCompanion

final class MenuBarIconResolverTests: XCTestCase {
    func testANCMapsToMenuBarANC() {
        XCTAssertEqual(
            MenuBarIconResolver.assetName(connection: .connected, confirmedMode: .anc),
            MenuBarIconResolver.anc
        )
    }

    func testAmbientMapsToMenuBarAmbient() {
        XCTAssertEqual(
            MenuBarIconResolver.assetName(connection: .connected, confirmedMode: .ambientAware),
            MenuBarIconResolver.ambient
        )
    }

    func testOffMapsToMenuBarOff() {
        XCTAssertEqual(
            MenuBarIconResolver.assetName(connection: .connected, confirmedMode: .off),
            MenuBarIconResolver.off
        )
    }

    func testTalkThruReusesMenuBarANC() {
        // No MenuBarTalkThru asset exists yet.
        XCTAssertEqual(
            MenuBarIconResolver.assetName(connection: .connected, confirmedMode: .talkThru),
            MenuBarIconResolver.anc
        )
    }

    func testUnknownModeWhileConnectedMapsToNoDevice() {
        // No confirmed status event has arrived yet — same treatment as no device at all.
        XCTAssertEqual(
            MenuBarIconResolver.assetName(connection: .connected, confirmedMode: .unknown),
            MenuBarIconResolver.noDevice
        )
    }

    func testDisconnectedAlwaysMapsToNoDeviceRegardlessOfMode() {
        for mode: NoiseMode in [.off, .anc, .ambientAware, .talkThru, .unknown] {
            XCTAssertEqual(
                MenuBarIconResolver.assetName(connection: .disconnected, confirmedMode: mode),
                MenuBarIconResolver.noDevice,
                "disconnected + \(mode) should still be noDevice"
            )
        }
    }
}
