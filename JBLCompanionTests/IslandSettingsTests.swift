import XCTest
@testable import JBLCompanion

final class IslandSettingsTests: XCTestCase {
    // Each test uses its own UUID so runs never collide with each other or with anything a real
    // app session might have saved under a real display's UUID.
    private func freshUUID() -> String { UUID().uuidString }

    override func tearDown() {
        // Nothing to clean up centrally — each test's UUID is unique, so a leftover value from a
        // previous run (if the suite were ever interrupted mid-test) can never affect another.
        super.tearDown()
    }

    // MARK: - Dock edge/offset round trip, per display

    func testDockEdgeDefaultsToTopForAnUnsavedDisplay() {
        XCTAssertEqual(IslandSettings.dockEdge(forDisplayUUID: freshUUID()), .top)
    }

    func testDockOffsetDefaultsToZeroForAnUnsavedDisplay() {
        XCTAssertEqual(IslandSettings.dockOffset(forDisplayUUID: freshUUID(), edge: .top), 0)
    }

    func testDockEdgeRoundTripsForASpecificDisplay() {
        let uuid = freshUUID()
        IslandSettings.setDockEdge(.left, forDisplayUUID: uuid)
        XCTAssertEqual(IslandSettings.dockEdge(forDisplayUUID: uuid), .left)
    }

    func testDockOffsetRoundTripsForASpecificDisplay() {
        let uuid = freshUUID()
        IslandSettings.setDockOffset(123.5, forDisplayUUID: uuid, edge: .left)
        XCTAssertEqual(IslandSettings.dockOffset(forDisplayUUID: uuid, edge: .left), 123.5)
    }

    /// The whole point of keying by display UUID: two displays' saved edges must never bleed into
    /// each other.
    func testDockEdgeIsIndependentPerDisplay() {
        let uuidA = freshUUID()
        let uuidB = freshUUID()
        IslandSettings.setDockEdge(.right, forDisplayUUID: uuidA)
        IslandSettings.setDockEdge(.bottom, forDisplayUUID: uuidB)
        XCTAssertEqual(IslandSettings.dockEdge(forDisplayUUID: uuidA), .right)
        XCTAssertEqual(IslandSettings.dockEdge(forDisplayUUID: uuidB), .bottom)
    }

    func testDockOffsetIsIndependentPerDisplay() {
        let uuidA = freshUUID()
        let uuidB = freshUUID()
        IslandSettings.setDockOffset(50, forDisplayUUID: uuidA, edge: .top)
        IslandSettings.setDockOffset(-50, forDisplayUUID: uuidB, edge: .top)
        XCTAssertEqual(IslandSettings.dockOffset(forDisplayUUID: uuidA, edge: .top), 50)
        XCTAssertEqual(IslandSettings.dockOffset(forDisplayUUID: uuidB, edge: .top), -50)
    }

    /// The bug this keying scheme specifically exists to prevent: a horizontal (top/bottom)
    /// offset and a vertical (left/right) one are different axes, so switching edges on the same
    /// display must never apply one edge's raw offset to another.
    func testDockOffsetIsIndependentPerEdgeOnTheSameDisplay() {
        let uuid = freshUUID()
        IslandSettings.setDockOffset(80, forDisplayUUID: uuid, edge: .top)
        IslandSettings.setDockOffset(-30, forDisplayUUID: uuid, edge: .left)
        XCTAssertEqual(IslandSettings.dockOffset(forDisplayUUID: uuid, edge: .top), 80)
        XCTAssertEqual(IslandSettings.dockOffset(forDisplayUUID: uuid, edge: .left), -30)
    }

    // MARK: - Auto-expand on connect

    func testAutoExpandOnConnectDefaultsToOff() {
        // A fresh key (never set in this process) reads as Bool's own UserDefaults default: false.
        // Covered indirectly — see the task's own "default OFF" requirement — by simply asserting
        // the getter's default without ever having called the setter.
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.autoExpandOnConnect)
        XCTAssertFalse(IslandSettings.autoExpandOnConnect)
    }

    func testAutoExpandOnConnectRoundTrips() {
        IslandSettings.autoExpandOnConnect = true
        XCTAssertTrue(IslandSettings.autoExpandOnConnect)
        IslandSettings.autoExpandOnConnect = false
        XCTAssertFalse(IslandSettings.autoExpandOnConnect)
    }
}
