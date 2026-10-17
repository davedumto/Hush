import XCTest
@testable import JBLCompanion

final class ModeButtonResolverTests: XCTestCase {
    // MARK: - Click -> pending (task: "Ambient click goes pending")

    func testAmbientClickGoesPending() {
        // The click itself (NoiseModeRequestCoordinator.requestMode) is covered by
        // NoiseModeRequestCoordinatorTests; this is the resulting button state once
        // HeadphoneState.pendingNoiseMode reflects that click.
        let resolved = ModeButtonResolver.state(
            for: .ambientAware, isModeVerified: true, currentMode: .anc, pendingMode: .ambientAware
        )
        XCTAssertEqual(resolved, .pending)
    }

    // MARK: - 5C confirms (task: "a 5C confirms")

    func testConfirmedModeResolvesToActive() {
        let resolved = ModeButtonResolver.state(
            for: .ambientAware, isModeVerified: true, currentMode: .ambientAware, pendingMode: nil
        )
        XCTAssertEqual(resolved, .active)
    }

    // MARK: - 5B ack alone never activates (task: "a 5B ack alone never activates a mode")

    func testPendingModeNeverResolvesToActiveBeforeConfirmation() {
        // A write ack (5B) only ever reaches HeadphoneState as `pendingNoiseMode` staying set —
        // CLAUDE.md: "A 5B ack alone is never confirmation." Only `noiseMode` itself (set solely
        // by NoiseModeRequestCoordinator.handleConfirmation, on a real 5C) can produce `.active`.
        let resolved = ModeButtonResolver.state(
            for: .anc, isModeVerified: true, currentMode: .off, pendingMode: .anc
        )
        XCTAssertEqual(resolved, .pending)
        XCTAssertNotEqual(resolved, .active)
    }

    // MARK: - Timeout keeps the old mode (task: "a timeout returns to available and keeps the old mode")

    func testTimedOutModeReturnsToAvailableAndOldModeStaysActive() {
        // The mode that failed: pendingNoiseMode has already been cleared by
        // NoiseModeRequestCoordinator.handleTimeout, so from the resolver's point of view it's
        // just an ordinary verified, non-current mode.
        let failedMode = ModeButtonResolver.state(
            for: .anc, isModeVerified: true, currentMode: .ambientAware, pendingMode: nil
        )
        XCTAssertEqual(failedMode, .available)

        // The mode that was active before the failed request — unchanged throughout.
        let keptMode = ModeButtonResolver.state(
            for: .ambientAware, isModeVerified: true, currentMode: .ambientAware, pendingMode: nil
        )
        XCTAssertEqual(keptMode, .active)
    }

    func testTimedOutStatusLineNamesTheKeptModeNotTheFailedOne() {
        let content = ModeButtonResolver.statusLine(
            currentMode: .ambientAware, pendingMode: nil, timedOut: true, eventMapVerified: true
        )
        XCTAssertEqual(content.dotStyle, .stillRing)
        XCTAssertEqual(content.modeName, "Ambient")
        XCTAssertEqual(content.detail, "no response, kept current mode")
    }

    // MARK: - Disabled modes ignore clicks (task: "disabled modes ignore clicks")

    func testDisabledModeIsNotInteractive() {
        XCTAssertFalse(ModeButtonResolver.isInteractive(
            for: .off, isModeVerified: false, currentMode: .anc, pendingMode: nil
        ))
    }

    // MARK: - Hardware-initiated change, no pending step (task: "a hardware-initiated change applies with no pending step")

    func testHardwareInitiatedChangeResolvesDirectlyToActiveWithNoPendingState() {
        // No `pendingMode` is ever involved — a spontaneous 5C (earcup button press) flows
        // straight into `noiseMode`, never through `pendingNoiseMode` at all.
        let resolved = ModeButtonResolver.state(
            for: .talkThru, isModeVerified: true, currentMode: .talkThru, pendingMode: nil
        )
        XCTAssertEqual(resolved, .active)
    }

    /// Off has no command frame, so `isModeVerified(.off)` is false on every current profile — but
    /// the headphones can still spontaneously report Off themselves (a physical earcup press;
    /// Tune670NCProfile's event map independently confirms byte 0x00 for it). That must still show
    /// as active, overriding the disabled gate.
    func testHardwareReportedOffShowsActiveEvenThoughUnverified() {
        let resolved = ModeButtonResolver.state(
            for: .off, isModeVerified: false, currentMode: .off, pendingMode: nil
        )
        XCTAssertEqual(resolved, .active)
    }

    // MARK: - Off disabled while unverified (task: "Off is disabled while its isModeVerified is false")

    func testOffIsDisabledWhileUnverifiedAndNotCurrent() {
        let resolved = ModeButtonResolver.state(
            for: .off, isModeVerified: false, currentMode: .anc, pendingMode: nil
        )
        XCTAssertEqual(resolved, .disabled)
        XCTAssertFalse(ModeButtonResolver.isInteractive(
            for: .off, isModeVerified: false, currentMode: .anc, pendingMode: nil
        ))
    }

    // MARK: - Other buttons ignore clicks while one is pending (task)

    func testOtherAvailableButtonsIgnoreClicksWhileOneIsPending() {
        // TalkThru is verified and not the pending mode, so it still *looks* available…
        let resolved = ModeButtonResolver.state(
            for: .talkThru, isModeVerified: true, currentMode: .off, pendingMode: .ambientAware
        )
        XCTAssertEqual(resolved, .available)
        // …but must not be clickable while Ambient is pending.
        XCTAssertFalse(ModeButtonResolver.isInteractive(
            for: .talkThru, isModeVerified: true, currentMode: .off, pendingMode: .ambientAware
        ))
    }

    func testPendingModeItselfIsNeverInteractive() {
        XCTAssertFalse(ModeButtonResolver.isInteractive(
            for: .ambientAware, isModeVerified: true, currentMode: .off, pendingMode: .ambientAware
        ))
    }

    func testActiveModeIsNeverInteractive() {
        // Clicking the already-active mode isn't a thing — §9.3: "User clicks an available button."
        XCTAssertFalse(ModeButtonResolver.isInteractive(
            for: .anc, isModeVerified: true, currentMode: .anc, pendingMode: nil
        ))
    }

    // MARK: - "(unverified)" follows eventMapVerified (task)

    func testConfirmedStatusLineIsUnverifiedOnlyWhenEventMapIsUnverified() {
        let verified = ModeButtonResolver.statusLine(
            currentMode: .anc, pendingMode: nil, timedOut: false, eventMapVerified: true
        )
        XCTAssertEqual(verified.dotStyle, .solidGlow)
        XCTAssertEqual(verified.modeName, "ANC")
        XCTAssertEqual(verified.detail, "is currently active")

        let unverified = ModeButtonResolver.statusLine(
            currentMode: .anc, pendingMode: nil, timedOut: false, eventMapVerified: false
        )
        XCTAssertEqual(unverified.dotStyle, .stillRing)
        XCTAssertEqual(unverified.modeName, "ANC")
        XCTAssertEqual(unverified.detail, "(unverified)")
    }

    /// Disconnected, or freshly connected before the first status event — nothing has ever been
    /// confirmed, so there's no "is currently active"/"(unverified)" to say (same reasoning
    /// NoiseModeStatusText already applies: never flag `.unknown` itself as unverified).
    func testUnknownModeStatusLineHasNoDetailText() {
        let content = ModeButtonResolver.statusLine(
            currentMode: .unknown, pendingMode: nil, timedOut: false, eventMapVerified: true
        )
        XCTAssertEqual(content.modeName, "—")
        XCTAssertEqual(content.detail, "")
    }

    func testPendingStatusLineIgnoresEventMapVerified() {
        // Pending is about the in-flight request, not the event map — eventMapVerified must never
        // leak into it.
        let content = ModeButtonResolver.statusLine(
            currentMode: .anc, pendingMode: .ambientAware, timedOut: false, eventMapVerified: false
        )
        XCTAssertEqual(content.dotStyle, .pulsingRing)
        XCTAssertEqual(content.modeName, "Ambient")
        XCTAssertEqual(content.detail, "waiting for headphones…")
    }

    // MARK: - hasWorkingControls

    func testHasWorkingControlsIsTrueWhenSupportedAndAtLeastOneModeVerified() {
        XCTAssertTrue(ModeButtonResolver.hasWorkingControls(supportsNoiseControl: true, isModeVerified: { $0 == .anc }))
    }

    func testHasWorkingControlsIsFalseWhenNotSupportedEvenIfModesAreVerified() {
        XCTAssertFalse(ModeButtonResolver.hasWorkingControls(supportsNoiseControl: false, isModeVerified: { $0 == .anc }))
    }

    func testHasWorkingControlsIsFalseWhenSupportedButNoModeIsVerified() {
        // GenericProfile's exact shape: supportsNoiseControl false and nothing verified.
        XCTAssertFalse(ModeButtonResolver.hasWorkingControls(supportsNoiseControl: false, isModeVerified: { _ in false }))
    }
}
