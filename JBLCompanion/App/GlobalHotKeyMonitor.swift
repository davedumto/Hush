import Carbon
import Foundation

/// A single, fixed global keyboard shortcut (Control+Option+A, "ANC") that fires `onTriggered`
/// from anywhere in macOS, not just while Hush's own window is key — owner spec, 2026-10-28: "the
/// shortcut for turning on anc with just your keyboard."
///
/// Built on Carbon's `RegisterEventHotKey`/`InstallEventHandler`, not
/// `NSEvent.addGlobalMonitorForEvents` — the Carbon API needs no Accessibility/Input Monitoring
/// permission at all, matching this project's existing minimal-permissions posture (no
/// entitlements file, no sandbox, no hardened runtime; the only usage-description key anywhere is
/// `NSBluetoothAlwaysUsageDescription`). An `NSEvent` global monitor would silently deliver
/// nothing at all until the user separately grants Input Monitoring — exactly the kind of extra
/// permission-prompt friction already a sore point for this app (the Bluetooth prompt reappearing
/// on every reboot, since ad-hoc signing has no stable Developer ID for TCC to anchor trust to).
/// Carbon's hotkey APIs are formally deprecated symbols but remain fully functional on current
/// macOS, and are the standard community approach for exactly this reason.
final class GlobalHotKeyMonitor {
    /// Control+Option+A: avoids the far more commonly-squatted Cmd+Shift space (other apps,
    /// system shortcuts) while staying a single, easy-to-remember chord for "ANC." Not yet
    /// user-configurable — a fixed default, same as the rest of this app's keyboard surface today.
    private static let keyCode = UInt32(kVK_ANSI_A)
    private static let modifierFlags = UInt32(controlKey | optionKey)
    /// Four-char code identifying this app's own hotkey registration — doesn't need to be
    /// globally unique beyond this process, just stable and non-zero so `GetEventParameter`'s
    /// callback can tell "our hotkey fired" apart from any other hotkey some other app registered
    /// in the same process space.
    private static let hotKeySignature: FourCharCode = fourCharCode("Hush")
    private static let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    var onTriggered: (() -> Void)?

    /// Idempotent — a second `start()` while already registered is a no-op rather than silently
    /// leaking a second handler/registration.
    func start() {
        guard hotKeyRef == nil else { return }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // The callback must be a plain, non-capturing closure (Swift compiles it to a C function
        // pointer here) — `self` is threaded through via `userData`/`Unmanaged` instead, the
        // standard bridge for Carbon's C-callback-based event APIs.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                var pressedID = EventHotKeyID()
                GetEventParameter(
                    eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedID
                )
                guard pressedID.signature == GlobalHotKeyMonitor.hotKeySignature else { return noErr }
                Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue().onTriggered?()
                return noErr
            },
            1, &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        RegisterEventHotKey(Self.keyCode, Self.modifierFlags, Self.hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    /// Idempotent — safe to call even if `start()` was never called or already stopped.
    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit { stop() }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    string.utf8.prefix(4).reduce(FourCharCode(0)) { ($0 << 8) + FourCharCode($1) }
}
