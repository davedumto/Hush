import CoreBluetooth
import Foundation
import os.log

/// Allowlist-only gate for every characteristic write this app will ever make.
/// Default is reject. A write only goes through if it matches an entry
/// (service UUID, characteristic UUID, and exact byte frame) in the allowlist
/// the device's profile supplies. An empty allowlist rejects everything.
final class WriteGuard {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "WriteGuard")
    private let allowlist: [WriteAllowlistEntry]

    init(allowlist: [WriteAllowlistEntry]) {
        self.allowlist = allowlist
    }

    /// Call this before every write. Only ever returns true for an exact allowlist match.
    func isAllowed(serviceUUID: CBUUID, characteristicUUID: CBUUID, payload: Data) -> Bool {
        let candidate = WriteAllowlistEntry(
            serviceUUID: serviceUUID,
            characteristicUUID: characteristicUUID,
            payload: payload
        )
        let allowed = allowlist.contains(candidate)
        if !allowed {
            logger.warning(
                "Rejected write — service=\(serviceUUID.uuidString, privacy: .public) characteristic=\(characteristicUUID.uuidString, privacy: .public) payload=\(payload.jblHexString, privacy: .public)"
            )
        }
        return allowed
    }
}

extension Data {
    var jblHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
