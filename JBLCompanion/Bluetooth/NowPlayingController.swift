import AppKit
import Foundation
import MediaRemoteAdapter
import os.log

/// Transport commands the now-playing media dock's own buttons send — MediaDockControls' own doc
/// comment, threaded up through ExpandedCard/NotchView/NotchPanel to AppDelegate the same way
/// onSelectNoiseMode is.
enum NowPlayingCommand {
    case togglePlayPause
    case next
    case previous
}

/// One snapshot of "what's currently playing system-wide" — NowPlayingController's own translation
/// of MediaRemoteAdapter's TrackInfo.Payload into just the fields the media dock needs. A distinct
/// type from the package's own `TrackInfo`, not a type alias: nothing outside MediaRemoteAdapterBridge
/// (below) should need to know that package's own shape at all, matching FocusModeWatcher's own
/// isolation of its private-API dependency.
struct NowPlayingTrackInfo {
    let title: String?
    let artist: String?
    let bundleIdentifier: String?
    let isPlaying: Bool
    let artwork: NSImage?
    /// Owner spec, 2026-11-07: a progress bar with elapsed/remaining time, matching the adapter's
    /// own `TrackInfo.Payload.durationMicros`/`currentElapsedTime` (the latter already
    /// interpolates a live position from a snapshot + playback rate, so this app doesn't have to).
    /// Default `nil` (not a required param) so every existing call site/test that doesn't care
    /// about progress keeps compiling unchanged.
    let durationSeconds: TimeInterval?
    let elapsedSeconds: TimeInterval?

    init(
        title: String?, artist: String?, bundleIdentifier: String?, isPlaying: Bool, artwork: NSImage?,
        durationSeconds: TimeInterval? = nil, elapsedSeconds: TimeInterval? = nil
    ) {
        self.title = title
        self.artist = artist
        self.bundleIdentifier = bundleIdentifier
        self.isPlaying = isPlaying
        self.artwork = artwork
        self.durationSeconds = durationSeconds
        self.elapsedSeconds = elapsedSeconds
    }
}

/// Narrow seam over MediaRemoteAdapter's own `MediaController` — isolates every call this app makes
/// into that private-API-dependent package behind one interface, the same way FocusModeWatcher
/// isolates its own undocumented-file-format dependency. Lets NowPlayingControllerTests exercise
/// every real decision NowPlayingController makes (when to start listening, how retries back off,
/// what gets forwarded where) against a scripted fake, with no dependency on anything actually
/// playing or on the real Perl-bridged listener process existing at all.
protocol NowPlayingAdapting: AnyObject {
    var onTrackInfo: ((NowPlayingTrackInfo?) -> Void)? { get set }
    /// MediaRemoteAdapter's own `onListenerTerminated` — fires if its background listener process
    /// dies unexpectedly. NowPlayingController's own doc comment on how this feeds the retry loop.
    var onListenerTerminated: (() -> Void)? { get set }
    func startListening()
    func stopListening()
    /// One-shot fetch, used only as a capability probe before the first `startListening()` call —
    /// see NowPlayingController.probeThenListen()'s own doc comment.
    func getTrackInfo(completion: @escaping (NowPlayingTrackInfo?) -> Void)
    func play()
    func pause()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
}

/// The one file in this app that imports MediaRemoteAdapter directly — everything else (including
/// every test) only ever sees it through NowPlayingAdapting, so if this package is ever replaced or
/// its API shifts, this is the only place that has to change.
final class MediaRemoteAdapterBridge: NowPlayingAdapting {
    private let controller = MediaController()

    var onTrackInfo: ((NowPlayingTrackInfo?) -> Void)? {
        didSet { controller.onTrackInfoReceived = { [weak self] in self?.onTrackInfo?(Self.map($0)) } }
    }
    var onListenerTerminated: (() -> Void)? {
        didSet { controller.onListenerTerminated = onListenerTerminated }
    }

    func startListening() { controller.startListening() }
    func stopListening() { controller.stopListening() }

    func getTrackInfo(completion: @escaping (NowPlayingTrackInfo?) -> Void) {
        controller.getTrackInfo { completion(Self.map($0)) }
    }

    func play() { controller.play() }
    func pause() { controller.pause() }
    func togglePlayPause() { controller.togglePlayPause() }
    func nextTrack() { controller.nextTrack() }
    func previousTrack() { controller.previousTrack() }

    private static func map(_ trackInfo: TrackInfo?) -> NowPlayingTrackInfo? {
        guard let payload = trackInfo?.payload else { return nil }
        return NowPlayingTrackInfo(
            title: payload.title, artist: payload.artist, bundleIdentifier: payload.bundleIdentifier,
            isPlaying: payload.isPlaying ?? false, artwork: payload.artwork,
            durationSeconds: payload.durationMicros.map { $0 / 1_000_000 },
            // Already a live-interpolated position (snapshot + playback rate + timestamp), not a
            // stale snapshot — README's own doc comment on this property.
            elapsedSeconds: payload.currentElapsedTime
        )
    }
}

/// Resolves a source app's icon from its bundle identifier — a protocol (not a bare NSWorkspace
/// call at the use site) so NowPlayingControllerTests can verify the no-crash fallback for an
/// unresolvable/uninstalled bundle identifier without touching the real file system or installed
/// app list.
protocol AppIconResolving {
    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage?
}

final class WorkspaceAppIconResolver: AppIconResolving {
    func icon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Owner spec, 2026-11-07: a media dock in the expanded card showing what's playing system-wide
/// (title/artist/artwork/source app) with play/pause/next/previous control — the headline feature
/// this file exists for.
///
/// There is no public macOS API for this. `MediaRemote.framework` is the only thing that exposes
/// cross-app now-playing data and remote control, and it's private — Apple locked third-party
/// access down starting macOS 15.4 (`mediaremoted` now only answers processes whose bundle
/// identifier starts with `com.apple.`; see MediaPlaybackMonitor's own doc comment, which already
/// documented this exact break while building a *different*, lighter feature). The
/// `ejbills/mediaremote-adapter` Swift package (MediaRemoteAdapterBridge above) works around it the
/// same way `ungive/mediaremote-adapter` pioneered: shelling calls through `/usr/bin/perl`, a
/// system binary `mediaremoted` still trusts.
///
/// Researched, not guessed — and deliberately NOT merged with MediaPlaybackMonitor's own
/// CoreAudio-based `isMediaPlaying`, even though both ultimately answer "is something playing":
/// MediaPlaybackMonitor is the always-on signal behind the pill's waveform indicator, driven by a
/// public, unbreakable CoreAudio API; if the Perl-trust loophole this class depends on ever closes
/// the way the direct MediaRemote call already did once, that signal must keep working regardless.
///
/// Originally lazy in the strictest sense — `start()`/`stop()` only while the tray's own dock was
/// open — but widened same-day, with the owner's explicit sign-off, once the notch bar's own left
/// wing started showing real artwork whenever media is playing (NotchExtensionBar's own doc
/// comment): AppDelegate.updateNowPlayingControllerLifecycle() now runs this whenever *either* the
/// dock is open *or* `HeadphoneState.isMediaPlaying` is true, not app-launch-to-quit. Still never
/// permanently on — nothing runs while nothing's playing and the dock is closed — just no longer
/// scoped to the dock alone. The notch bar now shares the same private-API fragility the dock
/// already had; the always-on pill waveform itself still doesn't, since it stays on
/// MediaPlaybackMonitor regardless of any of this.
///
/// Fails silently throughout, by design: there is no fix a user could apply if Apple patches this
/// again (unlike Full Disk Access for FocusModeWatcher, which has a concrete "open Settings" fix),
/// so there's nothing useful to show them beyond the dock/notch-bar artwork just staying empty. A
/// failed probe or a terminated listener both retry forever on a capped exponential backoff
/// (`nextRetryDelay(after:)`) rather than giving up — cheap enough once capped that it's safe to
/// leave running for as long as either trigger condition holds.
final class NowPlayingController {
    static let initialRetryDelay: TimeInterval = 1
    static let maxRetryDelay: TimeInterval = 30
    /// Artwork arrives at whatever resolution the source app embedded (often 600pt+) but is only
    /// ever shown at a small fixed size in the dock — downsampled once on receipt so a full-size
    /// decoded bitmap isn't held in memory for the entire time the dock stays open.
    static let artworkMaxDimension: CGFloat = 160

    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "NowPlayingController")
    private let adapter: NowPlayingAdapting
    private let iconResolver: AppIconResolving
    private var isRunning = false
    private var retryDelay: TimeInterval = NowPlayingController.initialRetryDelay
    private var retryWorkItem: DispatchWorkItem?

    var onNowPlayingChanged: ((NowPlayingTrackInfo?) -> Void)?
    var onSourceIconResolved: ((NSImage?) -> Void)?

    init(adapter: NowPlayingAdapting, iconResolver: AppIconResolving = WorkspaceAppIconResolver()) {
        self.adapter = adapter
        self.iconResolver = iconResolver
    }

    convenience init() {
        self.init(adapter: MediaRemoteAdapterBridge())
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        retryDelay = Self.initialRetryDelay
        probeThenListen()
    }

    func stop() {
        isRunning = false
        retryWorkItem?.cancel()
        retryWorkItem = nil
        adapter.onTrackInfo = nil
        adapter.onListenerTerminated = nil
        adapter.stopListening()
    }

    func play() { adapter.play() }
    func pause() { adapter.pause() }
    func togglePlayPause() { adapter.togglePlayPause() }
    func nextTrack() { adapter.nextTrack() }
    func previousTrack() { adapter.previousTrack() }

    /// "Probe before construct" — research precedent: boringNotch's own MediaChecker runs a
    /// capability check before ever constructing its now-playing controller, rather than
    /// constructing it and discovering it doesn't work later. This fork of the adapter has no
    /// dedicated capability-check method, so a one-shot `getTrackInfo` stands in for one: any
    /// response at all (even `nil`, meaning nothing's currently playing) proves the Perl-bridged
    /// channel to `mediaremoted` is actually reachable, and only then does `startListening()` get
    /// called. If the channel is broken, `getTrackInfo` simply never calls back — no response ever
    /// arrives, `startListening()` never runs, and the dock just stays on its empty placeholder,
    /// identical to "nothing's playing right now."
    private func probeThenListen() {
        // The probe's own result is discarded on purpose (`_`, not `info`) — it exists only to
        // prove the channel is reachable at all, not as a real update. Forwarding it through
        // `handle(_:)` here would double-report the first track (once from this one-shot probe,
        // once more from `beginListening()`'s own listener a moment later) to every consumer.
        adapter.getTrackInfo { [weak self] _ in
            runOnMain {
                guard let self, self.isRunning else { return }
                self.retryDelay = Self.initialRetryDelay
                self.beginListening()
            }
        }
    }

    private func beginListening() {
        adapter.onTrackInfo = { [weak self] info in
            runOnMain {
                guard let self, self.isRunning else { return }
                self.retryDelay = Self.initialRetryDelay
                self.handle(info)
            }
        }
        adapter.onListenerTerminated = { [weak self] in
            runOnMain {
                guard let self, self.isRunning else { return }
                self.logger.warning("NowPlaying listener terminated unexpectedly; scheduling a retry")
                self.scheduleRetry()
            }
        }
        adapter.startListening()
    }

    private func scheduleRetry() {
        guard isRunning else { return }
        let delay = retryDelay
        let workItem = DispatchWorkItem { [weak self] in self?.probeThenListen() }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        retryDelay = Self.nextRetryDelay(after: retryDelay)
    }

    /// Capped exponential backoff: doubles each attempt, never past `maxRetryDelay` — never gives
    /// up, but never hammers a persistently broken channel either. A pure function (no timer
    /// involved) so the backoff math itself is unit-testable without any real wall-clock waiting.
    static func nextRetryDelay(after previous: TimeInterval) -> TimeInterval {
        min(previous * 2, maxRetryDelay)
    }

    private func handle(_ info: NowPlayingTrackInfo?) {
        let downsampled = info.map { info in
            NowPlayingTrackInfo(
                title: info.title, artist: info.artist, bundleIdentifier: info.bundleIdentifier,
                isPlaying: info.isPlaying, artwork: info.artwork.map { Self.downsample($0, maxDimension: Self.artworkMaxDimension) },
                durationSeconds: info.durationSeconds, elapsedSeconds: info.elapsedSeconds
            )
        }
        onNowPlayingChanged?(downsampled)

        guard let bundleIdentifier = downsampled?.bundleIdentifier else {
            onSourceIconResolved?(nil)
            return
        }
        onSourceIconResolved?(iconResolver.icon(forBundleIdentifier: bundleIdentifier))
    }

    private static func downsample(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension, size.width > 0, size.height > 0 else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
        resized.unlockFocus()
        return resized
    }
}

/// Runs `work` synchronously if already on the main thread, otherwise hops to it — MediaRemoteAdapter
/// doesn't document which thread its callbacks fire on, so every callback this app receives from it
/// goes through this rather than assuming. The synchronous fast path (not a blanket
/// `DispatchQueue.main.async`, which always defers at least one runloop turn even when called from
/// the main thread) is what lets NowPlayingControllerTests assert on state immediately after
/// invoking a fake adapter's callback, with no expectation/wait machinery needed.
private func runOnMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
