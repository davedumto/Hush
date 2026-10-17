import XCTest
@testable import JBLCompanion

final class IslandGeometryTests: XCTestCase {
    // MARK: - IslandGeometry camera detection

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testNoSafeAreaMeansNotNotched() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0)
        XCTAssertFalse(geometry.isNotched)
    }

    func testPositiveSafeAreaAndCameraWidthMeansNotched() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 200)
        XCTAssertTrue(geometry.isNotched)
    }

    func testPositiveSafeAreaWithZeroCameraWidthIsNotNotched() {
        // A safe area alone (e.g. a software menu-bar inset) without an actual camera gap
        // shouldn't count as a physical notch.
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 0)
        XCTAssertFalse(geometry.isNotched)
    }

    func testMenuBarHeightIsClampedTo16To64() {
        let tooShort = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 2)
        let tooTall = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 500)
        XCTAssertGreaterThanOrEqual(tooShort.menuBarHeight, 16)
        XCTAssertLessThanOrEqual(tooTall.menuBarHeight, 64)
    }

    // MARK: - Floating vs flush — no silhouette choice anymore: only a real camera hangs flush

    func testNonNotchedDisplayAlwaysFloats() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0)
        XCTAssertTrue(geometry.floats)
        XCTAssertNotNil(geometry.floatingGap)
    }

    func testRealCameraAlwaysHangsFlush() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 200)
        XCTAssertFalse(geometry.floats)
        XCTAssertNil(geometry.floatingGap)
    }

    // MARK: - Collapsed sizing and the frame formula

    func testCollapsedSizeMatchesCameraDimensions() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 200)
        XCTAssertEqual(geometry.collapsedSize, CGSize(width: geometry.cameraWidth, height: geometry.cameraHeight))
    }

    func testRealCameraFrameIsCenteredOnScreenAndFlushToTopEdge() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 200)
        let size = CGSize(width: 100, height: 50)
        let frame = geometry.frame(for: size)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.01)
        XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.01)
    }

    func testNonNotchedFrameDropsBelowTheScreensPhysicalTopEdge() {
        // A window frame flush with the screen's own physical top edge clipped the collapsed
        // pill's rounded top corner outright (no sub-pixel room for antialiasing to resolve into)
        // — a flat "chip" across what should be a full circle. A few points of real drop fixes it.
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0)
        let size = CGSize(width: 100, height: 50)
        let frame = geometry.frame(for: size)
        XCTAssertLessThan(frame.maxY, screen.maxY)
    }

    func testTopMarginIsUserAdjustable() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, topMargin: 40)
        XCTAssertEqual(geometry.floatingDrop, 40)
    }

    func testTopMarginIsClampedToDockPlacementsOwnRange() {
        let tooSmall = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, topMargin: 0)
        let tooBig = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, topMargin: 1000)
        XCTAssertEqual(tooSmall.floatingDrop, DockPlacement.edgeMarginRange.lowerBound)
        XCTAssertEqual(tooBig.floatingDrop, DockPlacement.edgeMarginRange.upperBound)
    }

    func testTopMarginIsIgnoredForARealCameraNotch() {
        // A real camera always hangs flush (floatingDrop 0), regardless of what topMargin asks for.
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 200, topMargin: 40)
        XCTAssertEqual(geometry.floatingDrop, 0)
    }

    // MARK: - MenuBarMeasurements

    func testShowsBarDetectsGapWithinRange() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertTrue(MenuBarMeasurements.showsBar(frame: frame, visibleTop: 1080 - 24))
        XCTAssertFalse(MenuBarMeasurements.showsBar(frame: frame, visibleTop: 1080)) // no gap at all
    }

    func testHeightRemembersLastKnownGoodReadingWhileBarIsHidden() {
        var measurements = MenuBarMeasurements()
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let shown = measurements.height(displayID: 1, frame: frame, visibleTop: 1080 - 30, scale: 2, statusBarThickness: 30)
        XCTAssertEqual(shown, 30)

        // Bar auto-hides (no gap); a *different* status bar thickness (40) is passed to prove the
        // cached reading (30) is what's actually returned, not a fresh fallback value.
        let hidden = measurements.height(displayID: 1, frame: frame, visibleTop: 1080, scale: 2, statusBarThickness: 40)
        XCTAssertEqual(hidden, 30)
    }

    func testRetainDisplaysDropsReadingsForDisconnectedDisplays() {
        var measurements = MenuBarMeasurements()
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // Cache a reading of 30 for display 1 while its bar is shown.
        let cached = measurements.height(displayID: 1, frame: frame, visibleTop: 1080 - 30, scale: 2, statusBarThickness: 30)
        XCTAssertEqual(cached, 30)

        measurements.retainDisplays([]) // display 1 is no longer connected

        // Bar now reads as hidden (no gap) with a *different* status bar thickness (40). If the
        // old cached 30 survived the drop, this would wrongly return 30 instead of 40.
        let afterDrop = measurements.height(displayID: 1, frame: frame, visibleTop: 1080, scale: 2, statusBarThickness: 40)
        XCTAssertEqual(afterDrop, 40)
    }
}
