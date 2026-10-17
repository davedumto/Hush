import XCTest
@testable import JBLCompanion

final class IslandGeometryTests: XCTestCase {
    // MARK: - IslandCapsuleFit (even width, whole height/drop, clamped + rounded)

    func testCapsuleFitRoundsWidthToEvenPoints() {
        let fit = IslandCapsuleFit(width: 5, height: 0, drop: 0)
        XCTAssertEqual(Int(fit.width) % 2, 0)
    }

    func testCapsuleFitClampsWidthToItsRange() {
        let fit = IslandCapsuleFit(width: 1000, height: 0, drop: 0)
        XCTAssertEqual(fit.width, IslandCapsuleFit.widthRange.upperBound)
    }

    func testCapsuleFitClampsHeightToItsRange() {
        let fit = IslandCapsuleFit(width: 0, height: -1000, drop: 0)
        XCTAssertEqual(fit.height, IslandCapsuleFit.heightRange.lowerBound)
    }

    func testCapsuleFitClampsDropToItsRange() {
        let fit = IslandCapsuleFit(width: 0, height: 0, drop: 1000)
        XCTAssertEqual(fit.drop, IslandCapsuleFit.dropRange.upperBound)
    }

    func testCapsuleFitUsesFallbackForNonFiniteInput() {
        let fit = IslandCapsuleFit(width: .infinity, height: .nan, drop: .infinity)
        XCTAssertEqual(fit.width, 0)
        XCTAssertEqual(fit.height, 0)
        XCTAssertEqual(fit.drop, 0)
    }

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

    // MARK: - Simulated cutout width (no camera) scales with menu-bar height

    func testSimulatedCutoutWidthScalesWithMenuBarHeight() {
        let shortBar = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 24, silhouette: .notch)
        let tallBar = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 48, silhouette: .notch)
        XCTAssertGreaterThan(tallBar.cameraWidth, shortBar.cameraWidth)
    }

    func testMenuBarHeightIsClampedTo16To64() {
        let tooShort = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 2)
        let tooTall = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, menuBarHeight: 500)
        XCTAssertGreaterThanOrEqual(tooShort.menuBarHeight, 16)
        XCTAssertLessThanOrEqual(tooTall.menuBarHeight, 64)
    }

    // MARK: - Capsule vs notch silhouette

    func testCapsuleOnNonNotchedDisplayFloats() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, silhouette: .capsule)
        XCTAssertTrue(geometry.floats)
        XCTAssertNotNil(geometry.floatingGap)
    }

    func testNotchSilhouetteNeverFloats() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, silhouette: .notch)
        XCTAssertFalse(geometry.floats)
        XCTAssertNil(geometry.floatingGap)
    }

    func testRealCameraAlwaysHangsRegardlessOfChosenSilhouette() {
        // A physical camera always hangs the island from the top edge — capsule only replaces a
        // *simulated* cutout.
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 200, silhouette: .capsule)
        XCTAssertFalse(geometry.floats)
    }

    // MARK: - Collapsed sizing and the frame formula

    func testCollapsedSizeMatchesCameraDimensions() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 200)
        XCTAssertEqual(geometry.collapsedSize, CGSize(width: geometry.cameraWidth, height: geometry.cameraHeight))
    }

    func testFrameIsCenteredOnScreenAndPinnedToTopEdge() {
        let geometry = IslandGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0)
        let size = CGSize(width: 100, height: 50)
        let frame = geometry.frame(for: size)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.01)
        XCTAssertEqual(frame.maxY, screen.maxY, accuracy: 0.01) // floatingDrop is 0 without a capsule fit
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
