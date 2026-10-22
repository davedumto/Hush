import CoreBluetooth
import IOBluetooth

/// Profile for the JBL Tune 770NC, derived from the Bluetooth recon in ~/jbl-recon. Every
/// shared-RACE-protocol capability (noise modes, power-off, equalizer, device toggles, event
/// mapping) comes from `AirohaRACECompatible`'s own default implementations — this struct only
/// holds what's genuinely specific to this one device: how to find/identify it and its photo.
struct Tune770NCProfile: AirohaRACECompatible {
    let displayName = "JBL Tune 770NC"
    let classicNameMatch = "770NC"
    let knownClassicAddress: String? = "00:A4:1C:AA:44:79"
    let bleExpectedName = "JBL Tune 770NC-LE"

    // design/DESIGN_GUIDE.md §1 Headphones.
    let photoAssetNames: HeadphonePhotoAssetNames? = HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")
    let modelNumberText = "770NC"
}
