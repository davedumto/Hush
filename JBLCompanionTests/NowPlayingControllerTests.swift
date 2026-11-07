import AppKit
import XCTest
@testable import JBLCompanion

final class NowPlayingControllerTests: XCTestCase {
    // MARK: - Capability probe gating

    func testStartsListeningOnlyAfterProbeResponds() {
        let adapter = FakeNowPlayingAdapter()
        // No getTrackInfoHandler set — probe never calls back, simulating an unreachable private
        // API (the same outcome a broken Perl-trust loophole would produce).
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.start()
        XCTAssertEqual(adapter.startListeningCallCount, 0)
    }

    func testBeginsListeningOnceProbeResponds() {
        let adapter = FakeNowPlayingAdapter()
        adapter.getTrackInfoHandler = { completion in completion(nil) }
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.start()
        XCTAssertEqual(adapter.startListeningCallCount, 1)
    }

    func testStartIsIdempotentWhileAlreadyRunning() {
        let adapter = FakeNowPlayingAdapter()
        adapter.getTrackInfoHandler = { completion in completion(nil) }
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.start()
        controller.start()
        XCTAssertEqual(adapter.startListeningCallCount, 1)
    }

    // MARK: - Track info forwarding

    func testForwardsTrackInfoToOnNowPlayingChanged() {
        let adapter = FakeNowPlayingAdapter()
        adapter.getTrackInfoHandler = { completion in completion(nil) }
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        var received: NowPlayingTrackInfo?
        var receivedCallCount = 0
        controller.onNowPlayingChanged = { received = $0; receivedCallCount += 1 }
        controller.start()

        let info = NowPlayingTrackInfo(title: "Nights", artist: "Frank Ocean", bundleIdentifier: "com.spotify.client", isPlaying: true, artwork: nil)
        adapter.onTrackInfo?(info)

        XCTAssertEqual(receivedCallCount, 1)
        XCTAssertEqual(received?.title, "Nights")
        XCTAssertEqual(received?.artist, "Frank Ocean")
        XCTAssertEqual(received?.isPlaying, true)
    }

    func testForwardsNilWhenNothingIsPlaying() {
        let adapter = FakeNowPlayingAdapter()
        adapter.getTrackInfoHandler = { completion in completion(nil) }
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        var callCount = 0
        var lastReceivedWasNil = false
        controller.onNowPlayingChanged = { info in
            callCount += 1
            lastReceivedWasNil = (info == nil)
        }
        controller.start()

        adapter.onTrackInfo?(nil)

        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(lastReceivedWasNil)
    }

    // MARK: - Source icon resolution

    func testResolvesSourceIconFromBundleIdentifier() {
        let adapter = FakeNowPlayingAdapter()
        adapter.getTrackInfoHandler = { completion in completion(nil) }
        let iconResolver = FakeAppIconResolver()
        let icon = NSImage(size: NSSize(width: 1, height: 1))
        iconResolver.iconsByBundleIdentifier["com.spotify.client"] = icon
        let controller = NowPlayingController(adapter: adapter, iconResolver: iconResolver)
        var resolvedIcon: NSImage?
        var resolvedCallCount = 0
        controller.onSourceIconResolved = { resolvedIcon = $0; resolvedCallCount += 1 }
        controller.start()

        adapter.onTrackInfo?(NowPlayingTrackInfo(title: nil, artist: nil, bundleIdentifier: "com.spotify.client", isPlaying: true, artwork: nil))

        XCTAssertEqual(resolvedCallCount, 1)
        XCTAssertEqual(iconResolver.requestedBundleIdentifiers, ["com.spotify.client"])
        XCTAssertTrue(resolvedIcon === icon)
    }

    func testFallsBackToNilIconForAnUnresolvableBundleIdentifier() {
        let adapter = FakeNowPlayingAdapter()
        adapter.getTrackInfoHandler = { completion in completion(nil) }
        let iconResolver = FakeAppIconResolver() // nothing registered — every lookup returns nil
        let controller = NowPlayingController(adapter: adapter, iconResolver: iconResolver)
        var resolvedIcon: NSImage??
        controller.onSourceIconResolved = { resolvedIcon = $0 }
        controller.start()

        adapter.onTrackInfo?(NowPlayingTrackInfo(title: "Song", artist: nil, bundleIdentifier: "com.unknown.app", isPlaying: true, artwork: nil))

        XCTAssertEqual(iconResolver.requestedBundleIdentifiers, ["com.unknown.app"])
        XCTAssertNil(resolvedIcon ?? nil)
    }

    func testNoIconLookupWhenNothingIsPlaying() {
        let adapter = FakeNowPlayingAdapter()
        adapter.getTrackInfoHandler = { completion in completion(nil) }
        let iconResolver = FakeAppIconResolver()
        let controller = NowPlayingController(adapter: adapter, iconResolver: iconResolver)
        controller.start()

        adapter.onTrackInfo?(nil)

        XCTAssertTrue(iconResolver.requestedBundleIdentifiers.isEmpty)
    }

    // MARK: - Stop

    func testStopPreventsFurtherUpdatesFromBeingReported() {
        let adapter = FakeNowPlayingAdapter()
        adapter.getTrackInfoHandler = { completion in completion(nil) }
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        var callCount = 0
        controller.onNowPlayingChanged = { _ in callCount += 1 }
        controller.start()
        controller.stop()

        // The adapter's own onTrackInfo closure would already have been cleared by stop(), but
        // simulate a stray late call (a race between stop() and an in-flight callback) to prove
        // the guard inside the closure itself also protects against it, not just the clearing.
        let strayCallback = adapter.onTrackInfo
        strayCallback?(NowPlayingTrackInfo(title: "Song", artist: nil, bundleIdentifier: nil, isPlaying: true, artwork: nil))

        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(adapter.stopListeningCallCount, 1)
    }

    func testStopBeforeStartIsSafe() {
        let adapter = FakeNowPlayingAdapter()
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.stop()
        XCTAssertEqual(adapter.stopListeningCallCount, 1)
    }

    // MARK: - Listener termination -> retry

    func testListenerTerminationDoesNotStopTheAdapterOutright() {
        let adapter = FakeNowPlayingAdapter()
        var probeCallCount = 0
        adapter.getTrackInfoHandler = { completion in
            probeCallCount += 1
            completion(nil)
        }
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.start()
        XCTAssertEqual(probeCallCount, 1)

        adapter.onListenerTerminated?()

        // A retry is scheduled on a real timer (capped backoff — covered in isolation by the pure
        // nextRetryDelay tests below), so the probe hasn't necessarily re-run synchronously here;
        // this only confirms termination is treated as "retry," not "give up" (stop() is never
        // called as a side effect of the listener dying on its own).
        XCTAssertEqual(adapter.stopListeningCallCount, 0)
    }

    func testListenerTerminationAfterStopIsIgnored() {
        let adapter = FakeNowPlayingAdapter()
        adapter.getTrackInfoHandler = { completion in completion(nil) }
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.start()
        let terminationHandler = adapter.onListenerTerminated
        controller.stop()

        // Same stray-callback race as testStopPreventsFurtherUpdatesFromBeingReported — this must
        // not resurrect listening after an explicit stop().
        terminationHandler?()

        XCTAssertEqual(adapter.startListeningCallCount, 1) // only the original start(), no retry
    }

    // MARK: - Command forwarding

    func testPlayForwardsToAdapterExactlyOnce() {
        let adapter = FakeNowPlayingAdapter()
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.play()
        XCTAssertEqual(adapter.playCallCount, 1)
    }

    func testPauseForwardsToAdapterExactlyOnce() {
        let adapter = FakeNowPlayingAdapter()
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.pause()
        XCTAssertEqual(adapter.pauseCallCount, 1)
    }

    func testTogglePlayPauseForwardsToAdapterExactlyOnce() {
        let adapter = FakeNowPlayingAdapter()
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.togglePlayPause()
        XCTAssertEqual(adapter.togglePlayPauseCallCount, 1)
    }

    func testNextTrackForwardsToAdapterExactlyOnce() {
        let adapter = FakeNowPlayingAdapter()
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.nextTrack()
        XCTAssertEqual(adapter.nextTrackCallCount, 1)
    }

    func testPreviousTrackForwardsToAdapterExactlyOnce() {
        let adapter = FakeNowPlayingAdapter()
        let controller = NowPlayingController(adapter: adapter, iconResolver: FakeAppIconResolver())
        controller.previousTrack()
        XCTAssertEqual(adapter.previousTrackCallCount, 1)
    }

    // MARK: - Backoff math (pure logic — see NowPlayingController.nextRetryDelay's own doc comment)

    func testRetryDelayDoublesEachAttempt() {
        XCTAssertEqual(NowPlayingController.nextRetryDelay(after: 1), 2)
        XCTAssertEqual(NowPlayingController.nextRetryDelay(after: 2), 4)
        XCTAssertEqual(NowPlayingController.nextRetryDelay(after: 4), 8)
        XCTAssertEqual(NowPlayingController.nextRetryDelay(after: 16), 30) // capped, not 32
    }

    func testRetryDelayStaysCappedOnceAtTheCeiling() {
        XCTAssertEqual(NowPlayingController.nextRetryDelay(after: 30), 30)
        XCTAssertEqual(NowPlayingController.nextRetryDelay(after: 45), 30)
    }
}

// MARK: - Test doubles

/// Test double for NowPlayingAdapting. `getTrackInfoHandler` defaults to nil (never calls its
/// completion), which is deliberately how a test opts into "simulate the private API being
/// unreachable" without any extra setup — tests that need the probe to succeed set it explicitly.
final class FakeNowPlayingAdapter: NowPlayingAdapting {
    var onTrackInfo: ((NowPlayingTrackInfo?) -> Void)?
    var onListenerTerminated: (() -> Void)?
    private(set) var startListeningCallCount = 0
    private(set) var stopListeningCallCount = 0
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var togglePlayPauseCallCount = 0
    private(set) var nextTrackCallCount = 0
    private(set) var previousTrackCallCount = 0
    var getTrackInfoHandler: ((@escaping (NowPlayingTrackInfo?) -> Void) -> Void)?

    func startListening() { startListeningCallCount += 1 }
    func stopListening() { stopListeningCallCount += 1 }
    func getTrackInfo(completion: @escaping (NowPlayingTrackInfo?) -> Void) {
        getTrackInfoHandler?(completion)
    }
    func play() { playCallCount += 1 }
    func pause() { pauseCallCount += 1 }
    func togglePlayPause() { togglePlayPauseCallCount += 1 }
    func nextTrack() { nextTrackCallCount += 1 }
    func previousTrack() { previousTrackCallCount += 1 }
}

final class FakeAppIconResolver: AppIconResolving {
    var iconsByBundleIdentifier: [String: NSImage] = [:]
    private(set) var requestedBundleIdentifiers: [String] = []

    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        requestedBundleIdentifiers.append(bundleIdentifier)
        return iconsByBundleIdentifier[bundleIdentifier]
    }
}
