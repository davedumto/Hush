import AppKit
import CoreAudio
import os.log

/// Owner spec, 2026-10-25: "when media is playing, show a little animation on the noise-mode side
/// [of NotchExtensionBar] to indicate media is playing." The first implementation of this used the
/// private MediaRemote.framework (dlopen/dlsym'd `MRMediaRemoteGetNowPlayingApplicationIsPlaying`)
/// — its completion handler never fired at all, on any attempt. Researched, not guessed: Apple
/// locked this down starting macOS 15.4 — `mediaremoted` now only answers processes whose bundle
/// identifier starts with `com.apple.`; a third-party app gets silently dropped, no error, no
/// crash, the completion block just never calls back. There's no entitlement a third-party app can
/// obtain to get back in (confirmed against LyricFever #94, GhostBar #9, a Keyboard Maestro forum
/// thread on the same 15.4 break, and the ungive/mediaremote-adapter project's own README, which
/// works around it by shelling out to `/usr/bin/perl` — an Apple-owned binary `mediaremoted` still
/// trusts — a much bigger dependency than this app needs for a plain boolean).
///
/// This instead uses CoreAudio's own *public* per-process audio API (added alongside the Core
/// Audio Process Tap feature, Sonoma+): `kAudioHardwarePropertyProcessObjectList` on the system
/// object enumerates every audio-touching process as an `AudioObjectID`, and
/// `kAudioProcessPropertyIsRunningOutput` on each one reports whether that process currently has
/// active output IO. No private framework, no entitlement, no helper binary, no TCC prompt (these
/// are metadata properties on audio objects, not audio data or a capture tap). Real-world
/// precedent: the open-source per-app volume mixer SonicFlow (github.com/altuzar/sonicflow) uses
/// this same property family. Property-change listeners on these selectors are reported unreliable
/// on recent macOS (Apple Developer Forums thread 770348) — polling on a timer, not a listener, is
/// the documented-safe approach.
final class MediaPlaybackMonitor {
    static let shared = MediaPlaybackMonitor()

    /// Owner-reported, 2026-10-25: live diagnostics showed "Haptyk" (a trackpad/haptic feedback
    /// helper) permanently reporting `kAudioProcessPropertyIsRunningOutput == 1` regardless of
    /// whether any real media was playing — confirmed against Apple's own header doc comment
    /// (AudioHardware.h): `IsRunningOutput` means "there is audio IO in progress," not "the
    /// process is producing audible sound" — there's no public per-process "is actually audible"
    /// signal in this API family (kAudioHardwarePropertyProcessIsAudible, the one property named
    /// that way, queries the *calling* process's own audibility, not an arbitrary other process's —
    /// not usable for scanning every process the way this needs). Haptyk keeps an output stream
    /// permanently open for low-latency feedback, which is a real, correct IO session by this
    /// API's own definition — just never one a person would call "media playing." Excluded by
    /// name rather than trying to guess a more precise signal that doesn't exist publicly.
    private static let excludedProcessNames: Set<String> = ["Haptyk"]

    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "MediaPlaybackMonitor")
    private(set) var isPlaying: Bool = false
    var onChange: ((Bool) -> Void)?

    private var pollTimer: Timer?

    private init() {
        poll()
        // Owner-reported, 2026-10-25: "when i pause the media, it takes some seconds to switch" —
        // a 1s poll meant up to a full second of lag on top of whatever CoreAudio itself takes to
        // report the stream as stopped; 0.3s trades a bit more polling for a snappier-feeling
        // switch without being so tight it'd show every brief gap between tracks as "stopped."
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        let playing = Self.anyProcessPlayingAudio(logger: logger)
        guard playing != isPlaying else { return }
        isPlaying = playing
        onChange?(playing)
    }

    /// `kAudioHardwarePropertyProcessObjectList` → every audio-touching process as an
    /// `AudioObjectID`, then `kAudioProcessPropertyIsRunningOutput` on each — true the moment any
    /// one of them has active output IO.
    private static func anyProcessPlayingAudio(logger: Logger) -> Bool {
        var listAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else {
            logger.error("ProcessObjectList size query failed status=\(sizeStatus, privacy: .public) dataSize=\(dataSize, privacy: .public)")
            return false
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        let listStatus = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &listAddress, 0, nil, &dataSize, &processIDs)
        guard listStatus == noErr else {
            logger.error("ProcessObjectList data query failed status=\(listStatus, privacy: .public)")
            return false
        }

        var anyPlaying = false
        for processID in processIDs {
            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            _ = AudioObjectGetPropertyData(processID, &pidAddress, 0, nil, &pidSize, &pid)

            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningOutput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let runStatus = AudioObjectGetPropertyData(processID, &runningAddress, 0, nil, &size, &isRunning)
            let name = pid > 0 ? (NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid\(pid)") : "pid?"
            if runStatus == noErr, isRunning != 0, !excludedProcessNames.contains(name) { anyPlaying = true }
        }
        return anyPlaying
    }
}
