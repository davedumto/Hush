import XCTest
@testable import JBLCompanion

final class ExpandedCardContentTests: XCTestCase {
    // MARK: - Battery chip

    func testNoBatteryReadingShowsNoChip() {
        let content = ExpandedCardContent.resolve(connection: .connected, batteryPercent: nil)
        XCTAssertEqual(content.batteryChip, .none)
    }

    func testBatteryAt15PercentIsNormalNotLow() {
        let content = ExpandedCardContent.resolve(connection: .connected, batteryPercent: 15)
        XCTAssertEqual(content.batteryChip, .normal(percent: 15))
    }

    func testBatteryAt14PercentIsLow() {
        let content = ExpandedCardContent.resolve(connection: .connected, batteryPercent: 14)
        XCTAssertEqual(content.batteryChip, .low(percent: 14))
    }

    func testBatteryAt82PercentIsNormal() {
        let content = ExpandedCardContent.resolve(connection: .connected, batteryPercent: 82)
        XCTAssertEqual(content.batteryChip, .normal(percent: 82))
    }

    // MARK: - Name block subtitle text

    func testConnectedNormalBatterySubtitle() {
        let content = ExpandedCardContent.resolve(connection: .connected, batteryPercent: 82)
        XCTAssertEqual(content.subtitleText, "Connected")
    }

    func testConnectedLowBatterySubtitle() {
        let content = ExpandedCardContent.resolve(connection: .connected, batteryPercent: 9)
        XCTAssertEqual(content.subtitleText, "Connected · battery low")
    }

    func testDisconnectedSubtitle() {
        let content = ExpandedCardContent.resolve(connection: .disconnected, batteryPercent: nil)
        XCTAssertEqual(content.subtitleText, "Disconnected")
    }

    // MARK: - Footer text

    func testFooterLeftIsAlwaysBluetooth() {
        XCTAssertEqual(ExpandedCardContent.resolve(connection: .connected, batteryPercent: 50).footerLeftText, "BLUETOOTH")
        XCTAssertEqual(ExpandedCardContent.resolve(connection: .disconnected, batteryPercent: nil).footerLeftText, "BLUETOOTH")
    }

    func testFooterRightIsSyncedWhenConnected() {
        XCTAssertEqual(ExpandedCardContent.resolve(connection: .connected, batteryPercent: 50).footerRightText, "SYNCED")
    }

    func testFooterRightIsIdleWhenDisconnected() {
        XCTAssertEqual(ExpandedCardContent.resolve(connection: .disconnected, batteryPercent: nil).footerRightText, "IDLE")
    }

    // MARK: - Hero number text

    func testHeroNumberStripsTheLettersFrom770NC() {
        XCTAssertEqual(ExpandedCardContent.heroNumberText(from: "770NC"), "770")
    }

    func testHeroNumberStripsTheLettersFrom670NC() {
        XCTAssertEqual(ExpandedCardContent.heroNumberText(from: "670NC"), "670")
    }

    func testHeroNumberIsEmptyForAnEmptyModelNumber() {
        XCTAssertEqual(ExpandedCardContent.heroNumberText(from: ""), "")
    }

    // MARK: - CardDock

    func testTopAndBottomAreNotVertical() {
        XCTAssertFalse(CardDock.top.isVertical)
        XCTAssertFalse(CardDock.bottom.isVertical)
    }

    func testLeftAndRightAreVertical() {
        XCTAssertTrue(CardDock.left.isVertical)
        XCTAssertTrue(CardDock.right.isVertical)
    }
}
