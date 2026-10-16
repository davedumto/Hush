import Foundation

/// Matches a classic Bluetooth device, by its own reported name and address, to one of the app's
/// known DeviceProfiles. Name is the primary signal (`classicNameMatch`, checked as a substring of
/// the device's actual name); a profile's `knownClassicAddress`, when set, is checked only as a
/// confirmation for diagnostics — a device whose address differs from the known one still matches
/// by name, so a profile isn't limited to one specific physical unit.
///
/// Pure and testable: takes plain strings, not IOBluetoothDevice, so it needs no real hardware.
struct DeviceProfileMatcher {
    struct Match {
        let profile: DeviceProfile
        let addressConfirmed: Bool
    }

    /// Returns the first profile (in list order) whose `classicNameMatch` is a non-empty substring
    /// of `name`, or nil if none match — which is exactly what a device like the Charge 4, or any
    /// other unrelated device, gets.
    static func match(name: String, address: String, against profiles: [DeviceProfile]) -> Match? {
        let normalizedAddress = ClassicConnectionMonitor.normalize(address)
        for profile in profiles {
            guard !profile.classicNameMatch.isEmpty, name.contains(profile.classicNameMatch) else { continue }
            let addressConfirmed: Bool
            if let known = profile.knownClassicAddress {
                addressConfirmed = ClassicConnectionMonitor.normalize(known) == normalizedAddress
            } else {
                addressConfirmed = false
            }
            return Match(profile: profile, addressConfirmed: addressConfirmed)
        }
        return nil
    }
}
