import Foundation

/// Decides what HeadphoneState should show for a raw BLE battery reading, given whether the
/// connected profile trusts a 0% reading from its hardware (DeviceProfile.trustsZeroBatteryReading).
/// Pure and testable — AppDelegate only wires the result into HeadphoneState and the logger.
struct BatteryReadingPolicy {
    struct Result: Equatable {
        /// What HeadphoneState.batteryPercent should become. nil for an untrusted zero reading —
        /// the card must not claim to know the battery is actually empty.
        let displayPercent: Int?
        /// True when this reading was suppressed specifically because it was an untrusted zero —
        /// distinct from "no reading at all" (disconnected), so the card can show "--" instead of
        /// the usual "—" placeholder.
        let isUnverifiedZero: Bool
    }

    static func apply(rawPercent: Int, trustsZeroBatteryReading: Bool) -> Result {
        if rawPercent == 0, !trustsZeroBatteryReading {
            return Result(displayPercent: nil, isUnverifiedZero: true)
        }
        return Result(displayPercent: rawPercent, isUnverifiedZero: false)
    }
}
