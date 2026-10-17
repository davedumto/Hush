import XCTest
@testable import JBLCompanion

final class CardConditionResolverTests: XCTestCase {
    // MARK: - resolve

    func testNoClassicConnectionIsNoDevice() {
        let condition = CardConditionResolver.resolve(
            classicConnected: false, firstStatusEventReceived: false, batteryPercent: nil, controlsAvailable: false
        )
        XCTAssertEqual(condition, .noDevice)
    }

    func testClassicConnectedButNoStatusEventYetIsConnecting() {
        let condition = CardConditionResolver.resolve(
            classicConnected: true, firstStatusEventReceived: false, batteryPercent: nil, controlsAvailable: true
        )
        XCTAssertEqual(condition, .connecting)
    }

    func testConnectedWithWorkingControlsAndNormalBatteryIsConnected() {
        let condition = CardConditionResolver.resolve(
            classicConnected: true, firstStatusEventReceived: true, batteryPercent: 82, controlsAvailable: true
        )
        XCTAssertEqual(condition, .connected)
    }

    func testConnectedWithWorkingControlsAndNoBatteryReadingIsConnected() {
        // No BLE reading yet is not the same thing as "low" — nil never counts as low battery.
        let condition = CardConditionResolver.resolve(
            classicConnected: true, firstStatusEventReceived: true, batteryPercent: nil, controlsAvailable: true
        )
        XCTAssertEqual(condition, .connected)
    }

    func testBatteryUnder15IsLowBattery() {
        let condition = CardConditionResolver.resolve(
            classicConnected: true, firstStatusEventReceived: true, batteryPercent: 14, controlsAvailable: true
        )
        XCTAssertEqual(condition, .lowBattery)
    }

    func testBatteryAtExactly15IsNotLowBattery() {
        let condition = CardConditionResolver.resolve(
            classicConnected: true, firstStatusEventReceived: true, batteryPercent: 15, controlsAvailable: true
        )
        XCTAssertEqual(condition, .connected)
    }

    func testNoWorkingControlsIsControlsUnavailable() {
        let condition = CardConditionResolver.resolve(
            classicConnected: true, firstStatusEventReceived: true, batteryPercent: 82, controlsAvailable: false
        )
        XCTAssertEqual(condition, .controlsUnavailable)
    }

    /// Controls-unavailable wins over low-battery when both are true at once — a bigger structural
    /// layout difference (the whole mode-buttons area swaps to a note row) than the battery chip
    /// simply turning orange, which still happens regardless (ExpandedCardContent resolves that
    /// independently of this enum).
    func testControlsUnavailableTakesPriorityOverLowBattery() {
        let condition = CardConditionResolver.resolve(
            classicConnected: true, firstStatusEventReceived: true, batteryPercent: 9, controlsAvailable: false
        )
        XCTAssertEqual(condition, .controlsUnavailable)
    }

    func testNoClassicConnectionTakesPriorityOverEverythingElse() {
        let condition = CardConditionResolver.resolve(
            classicConnected: false, firstStatusEventReceived: true, batteryPercent: 9, controlsAvailable: false
        )
        XCTAssertEqual(condition, .noDevice)
    }

    // MARK: - showsModeButtons / "no tappable mode button while connecting"

    func testNoTappableModeButtonWhileConnecting() {
        XCTAssertFalse(CardCondition.connecting.showsModeButtons)
    }

    func testNoTappableModeButtonWithNoDevice() {
        XCTAssertFalse(CardCondition.noDevice.showsModeButtons)
    }

    func testModeButtonsShowForTheOtherThreeConditions() {
        XCTAssertTrue(CardCondition.controlsUnavailable.showsModeButtons)
        XCTAssertTrue(CardCondition.lowBattery.showsModeButtons)
        XCTAssertTrue(CardCondition.connected.showsModeButtons)
    }

    // MARK: - Footer text for each condition

    func testFooterLeftIsAlwaysBluetooth() {
        for condition: CardCondition in [.noDevice, .connecting, .controlsUnavailable, .lowBattery, .connected] {
            XCTAssertEqual(CardConditionResolver.footerLeftText(for: condition), "BLUETOOTH")
        }
    }

    func testFooterRightTextPerCondition() {
        XCTAssertEqual(CardConditionResolver.footerRightText(for: .noDevice), "IDLE")
        XCTAssertEqual(CardConditionResolver.footerRightText(for: .connecting), "HANDSHAKE")
        XCTAssertEqual(CardConditionResolver.footerRightText(for: .controlsUnavailable), "SYNCED")
        XCTAssertEqual(CardConditionResolver.footerRightText(for: .lowBattery), "SYNCED")
        XCTAssertEqual(CardConditionResolver.footerRightText(for: .connected), "SYNCED")
    }

    // MARK: - "Last seen" text

    func testLastSeenTextWrapsTheProfileName() {
        XCTAssertEqual(CardConditionResolver.lastSeenText(lastMatchedProfileDisplayName: "JBL Tune 770NC"), "Last seen: JBL Tune 770NC")
    }

    func testLastSeenTextIsNilWhenNothingHasEverMatched() {
        XCTAssertNil(CardConditionResolver.lastSeenText(lastMatchedProfileDisplayName: nil))
    }

    func testLastSeenTextIsNilForAnEmptyName() {
        XCTAssertNil(CardConditionResolver.lastSeenText(lastMatchedProfileDisplayName: ""))
    }
}
