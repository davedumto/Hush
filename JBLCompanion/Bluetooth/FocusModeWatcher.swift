import Foundation
import os.log

/// Owner spec, 2026-10-29: "if i turn on dnd, it goes to noise cancellation" — detects Do Not
/// Disturb turning on/off by watching `~/Library/DoNotDisturb/DB/Assertions.json`, an undocumented
/// but widely-used-by-third-party-menu-bar-apps file macOS rewrites on every Focus state change.
///
/// Not `SetFocusFilterIntent`/App Intents: confirmed via two separate implementations (an in-app
/// conformance, then a dedicated `HushFocusFilter` App Intents Extension target) that `perform()`
/// never fires on this machine's macOS version — matching an open, unresolved Apple Developer
/// Forums report of the same symptom with no fix via either approach. This file-watching approach
/// is real prior art (several open-source macOS menu-bar Focus/DND indicator tools use it) and was
/// verified directly against this machine's actual `Assertions.json` before writing this class:
/// a `storeAssertionRecords` array appears at the top level only while a Focus is active, and is
/// absent once it ends — `assertionDetailsModeIdentifier` inside it is the active mode's ID
/// (`"com.apple.donotdisturb.mode.default"` for Do Not Disturb specifically).
final class FocusModeWatcher {
    static let doNotDisturbModeIdentifier = "com.apple.donotdisturb.mode.default"
    static let defaultAssertionsFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

    /// Injectable for `FocusModeWatcherTests` — the same pattern `NoiseControlCommander`'s own
    /// `now: () -> Date` uses, pointed at a fixture file instead of the real per-user DND database.
    private let assertionsFileURL: URL
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "FocusModeWatcher")
    private var source: DispatchSourceFileSystemObject?
    private var lastKnownActive = false

    /// Fires on a background queue whenever Do Not Disturb's on/off state changes (not on every
    /// file write — de-duplicated against `lastKnownActive` so a rewrite with no actual state
    /// change, which `Assertions.json` does often, stays silent).
    var onDoNotDisturbChanged: ((Bool) -> Void)?
    /// Fires once, on a background queue, if `watch()` can't even open `Assertions.json` — there is
    /// no programmatic Full Disk Access request API (confirmed: unlike Camera/Microphone/Bluetooth,
    /// `kTCCServiceSystemPolicyAllFiles` can only be granted by the user in System Settings), so
    /// this is the signal the app uses to show its own guided prompt instead.
    var onPermissionDenied: (() -> Void)?

    init(assertionsFileURL: URL = FocusModeWatcher.defaultAssertionsFileURL) {
        self.assertionsFileURL = assertionsFileURL
    }

    func start() {
        lastKnownActive = isDoNotDisturbActive()
        watch()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    /// `DispatchSourceFileSystemObject` stops reporting events once the watched file is replaced
    /// outright rather than written in place (macOS does this for `Assertions.json`) — each
    /// `.write`/`.delete`/`.rename` callback below closes the old descriptor and re-opens/re-arms a
    /// fresh watch, so the watcher survives every kind of rewrite rather than going silent after
    /// the first one.
    private func watch() {
        let path = assertionsFileURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            let failedErrno = errno
            logger.error("Could not open \(path, privacy: .public) for watching (errno \(failedErrno))")
            if failedErrno == EPERM || failedErrno == EACCES {
                DispatchQueue.main.async { [onPermissionDenied] in
                    onPermissionDenied?()
                }
            }
            return
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .global(qos: .utility)
        )
        newSource.setEventHandler { [weak self] in
            self?.handleFileEvent()
        }
        newSource.setCancelHandler {
            close(fd)
        }
        newSource.resume()
        source = newSource
    }

    private func handleFileEvent() {
        source?.cancel()
        source = nil
        // A delete/rename event means the old inode is gone — re-open on the current path (macOS
        // atomically swaps a fresh file into place) before re-arming the watch, rather than racing
        // to re-open at the instant of this callback.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.watch()
            let isActive = self.isDoNotDisturbActive()
            guard isActive != self.lastKnownActive else { return }
            self.lastKnownActive = isActive
            DispatchQueue.main.async { [onDoNotDisturbChanged] in
                onDoNotDisturbChanged?(isActive)
            }
        }
    }

    /// Reads and parses `Assertions.json` fresh each call — this file is small (a handful of KB)
    /// and changes infrequently, so there's no need to cache/diff it beyond `lastKnownActive`.
    func isDoNotDisturbActive() -> Bool {
        Self.isDoNotDisturbActive(assertionsFileURL: assertionsFileURL)
    }

    /// Static, `FocusModeWatcherTests`-callable entry point for the pure parsing logic, independent
    /// of any instance/watcher state.
    static func isDoNotDisturbActive(assertionsFileURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: assertionsFileURL),
              let file = try? JSONDecoder().decode(AssertionsFile.self, from: data)
        else { return false }

        return file.data
            .flatMap { $0.storeAssertionRecords ?? [] }
            .contains { $0.assertionDetails.assertionDetailsModeIdentifier == doNotDisturbModeIdentifier }
    }

    private struct AssertionsFile: Decodable {
        let data: [AssertionsEntry]
    }

    private struct AssertionsEntry: Decodable {
        let storeAssertionRecords: [AssertionRecord]?
    }

    private struct AssertionRecord: Decodable {
        let assertionDetails: AssertionDetails
    }

    private struct AssertionDetails: Decodable {
        let assertionDetailsModeIdentifier: String
    }
}
