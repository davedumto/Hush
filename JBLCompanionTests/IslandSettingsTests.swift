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

    // MARK: - Pill diameter

    func testPillDiameterDefaultsToDockPlacementsOwnDefaultWhenUnset() {
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.pillDiameter)
        XCTAssertEqual(IslandSettings.pillDiameter, DockPlacement.collapsedPillDiameter)
    }

    func testPillDiameterRoundTrips() {
        IslandSettings.pillDiameter = 72
        XCTAssertEqual(IslandSettings.pillDiameter, 72)
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.pillDiameter)
    }

    func testPillDiameterClampsToItsRange() {
        IslandSettings.pillDiameter = 1000
        XCTAssertEqual(IslandSettings.pillDiameter, DockPlacement.pillDiameterRange.upperBound)
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.pillDiameter)
    }

    // MARK: - Edge margin ("distance from the edge")

    func testEdgeMarginDefaultsToDockPlacementsOwnDefaultWhenUnset() {
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.edgeMargin(for: .top))
        XCTAssertEqual(IslandSettings.edgeMargin(for: .top), DockPlacement.edgeMargin(for: .top))
    }

    func testEdgeMarginRoundTrips() {
        IslandSettings.setEdgeMargin(35, for: .left)
        XCTAssertEqual(IslandSettings.edgeMargin(for: .left), 35)
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.edgeMargin(for: .left))
    }

    func testEdgeMarginClampsToItsRange() {
        IslandSettings.setEdgeMargin(1000, for: .bottom)
        XCTAssertEqual(IslandSettings.edgeMargin(for: .bottom), DockPlacement.edgeMarginRange.upperBound)
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.edgeMargin(for: .bottom))
    }

    /// The whole point of keying by edge: setting one edge's margin must never bleed into another.
    func testEdgeMarginIsIndependentPerEdge() {
        IslandSettings.setEdgeMargin(25, for: .top)
        IslandSettings.setEdgeMargin(45, for: .right)
        XCTAssertEqual(IslandSettings.edgeMargin(for: .top), 25)
        XCTAssertEqual(IslandSettings.edgeMargin(for: .right), 45)
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.edgeMargin(for: .top))
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.edgeMargin(for: .right))
    }

    // MARK: - Auto-expand on connect

    /// Unlike every other setting above, `autoExpandOnConnect` has no per-display/per-edge UUID to
    /// key by — it's one single global `UserDefaults.standard` key, the exact same domain the real
    /// app itself reads. Owner-reported, 2026-10-25: "the auto expand on connect toggle is not
    /// persistent to its settings... it keeps changing on relaunch." Root cause: these two tests
    /// used to mutate that real key directly and "clean up" with a plain `removeObject`, which
    /// doesn't restore whatever the real value was beforehand, it just deletes it — so every
    /// `xcodebuild test` run silently reset the real toggle back to off on the developer's own
    /// machine. Snapshotting the real value before each test and restoring it exactly afterward
    /// (present or absent) makes these two behave like the UUID-scoped tests above: free to mutate
    /// during the test, with zero observable effect on real app state once it ends.
    private var savedAutoExpandOnConnect: Any?

    func testAutoExpandOnConnectDefaultsToOff() {
        savedAutoExpandOnConnect = UserDefaults.standard.object(forKey: IslandSettings.Key.autoExpandOnConnect)
        // A fresh key (never set in this process) reads as Bool's own UserDefaults default: false.
        // Covered indirectly — see the task's own "default OFF" requirement — by simply asserting
        // the getter's default without ever having called the setter.
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.autoExpandOnConnect)
        XCTAssertFalse(IslandSettings.autoExpandOnConnect)
        restoreAutoExpandOnConnect()
    }

    func testAutoExpandOnConnectRoundTrips() {
        savedAutoExpandOnConnect = UserDefaults.standard.object(forKey: IslandSettings.Key.autoExpandOnConnect)
        IslandSettings.autoExpandOnConnect = true
        XCTAssertTrue(IslandSettings.autoExpandOnConnect)
        IslandSettings.autoExpandOnConnect = false
        XCTAssertFalse(IslandSettings.autoExpandOnConnect)
        restoreAutoExpandOnConnect()
    }

    private func restoreAutoExpandOnConnect() {
        if let savedAutoExpandOnConnect {
            UserDefaults.standard.set(savedAutoExpandOnConnect, forKey: IslandSettings.Key.autoExpandOnConnect)
        } else {
            UserDefaults.standard.removeObject(forKey: IslandSettings.Key.autoExpandOnConnect)
        }
    }

    // MARK: - Focus filter: switch to ANC on DND

    /// Same single global `UserDefaults.standard` key, same save/restore reasoning as
    /// `autoExpandOnConnect` above — this is also a real toggle a developer running the test suite
    /// might already have set on their own machine.
    private var savedFocusFilterANCOnDND: Any?

    func testFocusFilterANCOnDNDDefaultsToOff() {
        savedFocusFilterANCOnDND = UserDefaults.standard.object(forKey: IslandSettings.Key.focusFilterANCOnDND)
        UserDefaults.standard.removeObject(forKey: IslandSettings.Key.focusFilterANCOnDND)
        XCTAssertFalse(IslandSettings.focusFilterANCOnDND)
        restoreFocusFilterANCOnDND()
    }

    func testFocusFilterANCOnDNDRoundTrips() {
        savedFocusFilterANCOnDND = UserDefaults.standard.object(forKey: IslandSettings.Key.focusFilterANCOnDND)
        IslandSettings.focusFilterANCOnDND = true
        XCTAssertTrue(IslandSettings.focusFilterANCOnDND)
        IslandSettings.focusFilterANCOnDND = false
        XCTAssertFalse(IslandSettings.focusFilterANCOnDND)
        restoreFocusFilterANCOnDND()
    }

    private func restoreFocusFilterANCOnDND() {
        if let savedFocusFilterANCOnDND {
            UserDefaults.standard.set(savedFocusFilterANCOnDND, forKey: IslandSettings.Key.focusFilterANCOnDND)
        } else {
            UserDefaults.standard.removeObject(forKey: IslandSettings.Key.focusFilterANCOnDND)
        }
    }
}
