import XCTest
@testable import JBLCompanion

final class PillVariantTests: XCTestCase {
    private let tune770Photo = HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")

    // MARK: - No device

    func testNoDeviceShowsNoDeviceRegardlessOfOtherInputs() {
        let variant = PillVariant.resolve(
            device: .noDevice, connection: .connecting, batteryPercent: 80, theme: .dark, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.photo, .noDevice)
        XCTAssertEqual(variant.battery, .none)
        XCTAssertEqual(variant.photoOpacity, 1)
    }

    // MARK: - Theme contrast flip

    func testLightThemeUsesTheBlackPhotoOnTheWhitePill() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connected, batteryPercent: 50,
            theme: .light, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.photo, .device(assetName: "Tune770Black"))
        XCTAssertEqual(variant.theme, .light)
    }

    func testDarkThemeUsesTheWhitePhotoOnTheBlackPill() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connected, batteryPercent: 50,
            theme: .dark, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.photo, .device(assetName: "Tune770White"))
        XCTAssertEqual(variant.theme, .dark)
    }

    // MARK: - Notch override

    func testNotchForcesDarkThemeAndTheWhitePhotoEvenWithLightThemeInput() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connected, batteryPercent: 50,
            theme: .light, dock: .top(isNotched: true)
        )
        XCTAssertEqual(variant.theme, .dark)
        XCTAssertEqual(variant.photo, .device(assetName: "Tune770White"))
    }

    func testNonNotchedTopDockKeepsTheRealTheme() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connected, batteryPercent: 50,
            theme: .light, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.theme, .light)
    }

    // MARK: - Unknown/unphotographed profile (generic mark)

    func testMatchedProfileWithNoPhotoFallsBackToTheGenericMark() {
        let variant = PillVariant.resolve(
            device: .matched(photo: nil), connection: .connected, batteryPercent: 60,
            theme: .dark, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.photo, .genericMark)
        // Still connected, so still shows a battery reading — only the photo is unavailable.
        XCTAssertEqual(variant.battery, .bar(percent: 60, isLow: false))
    }

    // MARK: - Connecting

    func testConnectingShowsDimmedPhotoAndASpinnerRegardlessOfBattery() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connecting, batteryPercent: 90,
            theme: .dark, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.photoOpacity, 0.35)
        XCTAssertEqual(variant.battery, .spinner)
    }

    // MARK: - Battery / low-battery threshold (exactly 15%)

    func testNoBatteryReadingYetShowsNoBar() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connected, batteryPercent: nil,
            theme: .dark, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.battery, .none)
    }

    func testBatteryAtExactly15PercentIsNotLow() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connected, batteryPercent: 15,
            theme: .dark, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.battery, .bar(percent: 15, isLow: false))
    }

    func testBatteryAt14PercentIsLow() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connected, batteryPercent: 14,
            theme: .dark, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.battery, .bar(percent: 14, isLow: true))
    }

    func testBatteryAt0PercentIsLow() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connected, batteryPercent: 0,
            theme: .dark, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.battery, .bar(percent: 0, isLow: true))
    }

    func testBatteryAt100PercentIsNotLow() {
        let variant = PillVariant.resolve(
            device: .matched(photo: tune770Photo), connection: .connected, batteryPercent: 100,
            theme: .dark, dock: .top(isNotched: false)
        )
        XCTAssertEqual(variant.battery, .bar(percent: 100, isLow: false))
    }

    func testLowBatteryThresholdConstantIs15() {
        XCTAssertEqual(PillVariant.lowBatteryThreshold, 15)
    }

    // MARK: - PillDock

    func testTopAndBottomDocksAreHorizontal() {
        XCTAssertFalse(PillDock.top(isNotched: false).isVertical)
        XCTAssertFalse(PillDock.top(isNotched: true).isVertical)
        XCTAssertFalse(PillDock.bottom.isVertical)
    }

    func testLeftAndRightDocksAreVertical() {
        XCTAssertTrue(PillDock.left.isVertical)
        XCTAssertTrue(PillDock.right.isVertical)
    }

    func testOnlyANotchedTopDockIsNotch() {
        XCTAssertTrue(PillDock.top(isNotched: true).isNotch)
        XCTAssertFalse(PillDock.top(isNotched: false).isNotch)
        XCTAssertFalse(PillDock.bottom.isNotch)
        XCTAssertFalse(PillDock.left.isNotch)
        XCTAssertFalse(PillDock.right.isNotch)
    }
}
