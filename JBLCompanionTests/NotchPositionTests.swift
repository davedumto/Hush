import XCTest
@testable import JBLCompanion

final class NotchPositionTests: XCTestCase {
    // MARK: - PositionClamp

    func testClampLeavesInBoundsPositionUnchanged() {
        let position = NotchPosition(x: 50, y: 10)
        let clamped = PositionClamp.clamp(position, shapeSize: CGSize(width: 20, height: 20), displaySize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped, position)
    }

    func testClampPullsBackFromRightEdge() {
        // displayWidth=1920, shapeWidth=20 -> maxX = 1920/2 - 10 = 950
        let position = NotchPosition(x: 2000, y: 0)
        let clamped = PositionClamp.clamp(position, shapeSize: CGSize(width: 20, height: 20), displaySize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped.x, 950)
    }

    func testClampPullsBackFromLeftEdge() {
        // minX = 10 - 960 = -950
        let position = NotchPosition(x: -2000, y: 0)
        let clamped = PositionClamp.clamp(position, shapeSize: CGSize(width: 20, height: 20), displaySize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped.x, -950)
    }

    func testClampPullsNegativeYUpToZero() {
        let position = NotchPosition(x: 0, y: -50)
        let clamped = PositionClamp.clamp(position, shapeSize: CGSize(width: 20, height: 20), displaySize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped.y, 0)
    }

    func testClampPullsYBackFromBottomEdge() {
        // maxY = 1080 - 20 = 1060
        let position = NotchPosition(x: 0, y: 5000)
        let clamped = PositionClamp.clamp(position, shapeSize: CGSize(width: 20, height: 20), displaySize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped.y, 1060)
    }

    func testClampCentersWhenShapeWiderThanDisplay() {
        let position = NotchPosition(x: 999, y: 0)
        let clamped = PositionClamp.clamp(position, shapeSize: CGSize(width: 2000, height: 20), displaySize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped.x, 0)
    }

    // MARK: - RectClamp

    func testRectClampLeavesInBoundsOriginUnchanged() {
        let origin = CGPoint(x: 100, y: 50)
        let clamped = RectClamp.clampOrigin(origin, size: CGSize(width: 300, height: 120), within: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped, origin)
    }

    func testRectClampPullsBackFromRightEdge() {
        let origin = CGPoint(x: 1900, y: 0)
        let clamped = RectClamp.clampOrigin(origin, size: CGSize(width: 300, height: 120), within: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped.x, 1620) // 1920 - 300
    }

    func testRectClampPullsBackFromBottomEdge() {
        let origin = CGPoint(x: 0, y: 1079)
        let clamped = RectClamp.clampOrigin(origin, size: CGSize(width: 300, height: 120), within: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped.y, 960) // 1080 - 120
    }

    func testRectClampPullsNegativeOriginToZero() {
        let origin = CGPoint(x: -50, y: -10)
        let clamped = RectClamp.clampOrigin(origin, size: CGSize(width: 300, height: 120), within: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(clamped, .zero)
    }

    // MARK: - NotchPositionStore keys

    func testKeysDifferForDifferentDisplayUUIDs() {
        let keyA = NotchPositionStore.key(forDisplayUUID: "AAAA-1111")
        let keyB = NotchPositionStore.key(forDisplayUUID: "BBBB-2222")
        XCTAssertNotEqual(keyA, keyB)
    }

    func testKeyIsStableForTheSameDisplayUUID() {
        let keyA = NotchPositionStore.key(forDisplayUUID: "AAAA-1111")
        let keyB = NotchPositionStore.key(forDisplayUUID: "AAAA-1111")
        XCTAssertEqual(keyA, keyB)
    }

    // MARK: - NotchPositionStore round trip

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "NotchPositionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return defaults
    }

    func testLoadReturnsNilWhenNothingSaved() {
        let defaults = makeIsolatedDefaults()
        XCTAssertNil(NotchPositionStore.load(forDisplayUUID: "some-uuid", defaults: defaults))
    }

    func testSaveThenLoadRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let position = NotchPosition(x: 42, y: -8)
        NotchPositionStore.save(position, forDisplayUUID: "display-1", defaults: defaults)
        XCTAssertEqual(NotchPositionStore.load(forDisplayUUID: "display-1", defaults: defaults), position)
    }

    func testDifferentDisplaysDoNotShareStorage() {
        let defaults = makeIsolatedDefaults()
        NotchPositionStore.save(NotchPosition(x: 1, y: 1), forDisplayUUID: "display-1", defaults: defaults)
        XCTAssertNil(NotchPositionStore.load(forDisplayUUID: "display-2", defaults: defaults))
    }

    func testResetRemovesSavedPosition() {
        let defaults = makeIsolatedDefaults()
        NotchPositionStore.save(NotchPosition(x: 1, y: 1), forDisplayUUID: "display-1", defaults: defaults)
        NotchPositionStore.reset(forDisplayUUID: "display-1", defaults: defaults)
        XCTAssertNil(NotchPositionStore.load(forDisplayUUID: "display-1", defaults: defaults))
    }
}
