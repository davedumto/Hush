import XCTest
@testable import JBLCompanion

final class FocusFilterNoiseModeCoordinatorTests: XCTestCase {
    func testActivatingSavesTheCurrentModeAndRequestsANC() {
        let coordinator = FocusFilterNoiseModeCoordinator()
        let result = coordinator.modeToRequest(whenFocusActive: true, currentMode: .ambientAware)
        XCTAssertEqual(result, .anc)
        XCTAssertEqual(coordinator.savedModeBeforeFilter, .ambientAware)
    }

    func testDeactivatingRestoresTheSavedMode() {
        let coordinator = FocusFilterNoiseModeCoordinator()
        _ = coordinator.modeToRequest(whenFocusActive: true, currentMode: .talkThru)
        let result = coordinator.modeToRequest(whenFocusActive: false, currentMode: .anc)
        XCTAssertEqual(result, .talkThru)
        XCTAssertNil(coordinator.savedModeBeforeFilter)
    }

    func testFullActivateDeactivateCycleRestoresTheOriginalMode() {
        let coordinator = FocusFilterNoiseModeCoordinator()
        XCTAssertEqual(coordinator.modeToRequest(whenFocusActive: true, currentMode: .off), .anc)
        XCTAssertEqual(coordinator.modeToRequest(whenFocusActive: false, currentMode: .anc), .off)
    }

    /// A second activation while already active (e.g. the Focus Filter firing twice, or two
    /// overlapping Focuses both using this filter) must not overwrite the already-saved "before"
    /// mode with whatever ANC itself currently reports — that would lose the real original mode.
    func testReactivatingWhileAlreadyActiveDoesNotStompTheSavedMode() {
        let coordinator = FocusFilterNoiseModeCoordinator()
        _ = coordinator.modeToRequest(whenFocusActive: true, currentMode: .talkThru)
        let secondActivation = coordinator.modeToRequest(whenFocusActive: true, currentMode: .anc)
        XCTAssertNil(secondActivation) // nothing to request — already active
        XCTAssertEqual(coordinator.savedModeBeforeFilter, .talkThru) // unchanged
    }

    /// Deactivating with nothing saved (e.g. the app relaunched mid-Focus and lost its in-memory
    /// state) must not restore an arbitrary mode — that would be a surprise, not a restore.
    func testDeactivatingWithNothingSavedIsANoOp() {
        let coordinator = FocusFilterNoiseModeCoordinator()
        let result = coordinator.modeToRequest(whenFocusActive: false, currentMode: .anc)
        XCTAssertNil(result)
    }

    /// A second deactivation after the first one already consumed the saved mode must also be a
    /// no-op, not restore the same mode twice (or crash on a force-unwrap).
    func testRedundantDeactivationIsANoOp() {
        let coordinator = FocusFilterNoiseModeCoordinator()
        _ = coordinator.modeToRequest(whenFocusActive: true, currentMode: .off)
        _ = coordinator.modeToRequest(whenFocusActive: false, currentMode: .anc)
        let secondDeactivation = coordinator.modeToRequest(whenFocusActive: false, currentMode: .off)
        XCTAssertNil(secondDeactivation)
    }
}
