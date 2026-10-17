import XCTest
@testable import JBLCompanion

final class ExpandedCardContentTests: XCTestCase {
    // MARK: - Battery chip

    func testNoBatteryReadingShowsNoChip() {
        let content = ExpandedCardContent.resolve(batteryPercent: nil)
        XCTAssertEqual(content.batteryChip, .none)
    }

    func testBatteryAt15PercentIsNormalNotLow() {
        let content = ExpandedCardContent.resolve(batteryPercent: 15)
        XCTAssertEqual(content.batteryChip, .normal(percent: 15))
    }

    func testBatteryAt14PercentIsLow() {
        let content = ExpandedCardContent.resolve(batteryPercent: 14)
        XCTAssertEqual(content.batteryChip, .low(percent: 14))
    }

    func testBatteryAt82PercentIsNormal() {
        let content = ExpandedCardContent.resolve(batteryPercent: 82)
        XCTAssertEqual(content.batteryChip, .normal(percent: 82))
    }

    // MARK: - Name block subtitle text

    func testConnectedNormalBatterySubtitle() {
        let content = ExpandedCardContent.resolve(batteryPercent: 82)
        XCTAssertEqual(content.subtitleText, "Connected")
    }

    func testConnectedLowBatterySubtitle() {
        let content = ExpandedCardContent.resolve(batteryPercent: 9)
        XCTAssertEqual(content.subtitleText, "Connected · battery low")
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
