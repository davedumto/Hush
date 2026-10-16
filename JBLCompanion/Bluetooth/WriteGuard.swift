import Foundation
import os.log

/// Allowlist-only gate for every byte sequence this app will ever write to the headphones.
/// Default is reject. A write only goes through if it matches an entry (an exact byte frame) in
/// the allowlist the device's profile supplies. An empty allowlist rejects everything.
///
/// There is only one write destination now (the Airoha_APP RFCOMM channel), so unlike the earlier
/// BLE-era allowlist there's no service/characteristic to also match — just the frame itself.
final class WriteGuard {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "WriteGuard")
    private let allowlist: [WriteAllowlistEntry]

    init(allowlist: [WriteAllowlistEntry]) {
        self.allowlist = allowlist
    }

    /// Call this before every write. Only ever returns true for an exact allowlist match.
    func isAllowed(payload: Data) -> Bool {
        let candidate = WriteAllowlistEntry(payload: payload)
        let allowed = allowlist.contains(candidate)
        if !allowed {
            logger.warning("Rejected write — payload=\(payload.jblHexString, privacy: .public)")
        }
        return allowed
    }
}

extension Data {
    var jblHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
