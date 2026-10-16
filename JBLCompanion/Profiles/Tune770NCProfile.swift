import CoreBluetooth
import IOBluetooth

/// Profile for the JBL Tune 770NC, derived from the Bluetooth recon in ~/jbl-recon.
struct Tune770NCProfile: DeviceProfile {
    let displayName = "JBL Tune 770NC"
    let classicAddress = "00:A4:1C:AA:44:79"

    let bleScanServiceUUID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
    let bleExpectedName = "JBL Tune 770NC-LE"

    let batteryServiceUUID = CBUUID(string: "180F")
    let batteryLevelUUID = CBUUID(string: "2A19")

    let supportsNoiseControl = true

    // SDP-confirmed (~/jbl-recon/sdp_output_rfcomm_check.txt): the "Airoha_APP" service, channel 21.
    let raceRFCOMMChannelID: BluetoothRFCOMMChannelID = 21

    // UNVERIFIED (see NoiseControlCommander.commandFrame's own doc comment): only Ambient Aware's
    // command is independently confirmed to produce the mode it claims to. Off and ANC are not —
    // flip these to true only after confirming each one by hand, e.g. via the Debug menu's
    // "Send test frame…" item.
    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool {
        mode == .ambientAware
    }

    // Derived from isModeVerified rather than hand-maintained separately from it, so there is no
    // way for this list to drift out of sync with which modes are actually trusted.
    var writeAllowlist: [WriteAllowlistEntry] {
        CommandableNoiseMode.allCases
            .filter { isModeVerified($0) }
            .map { WriteAllowlistEntry(payload: $0.commandFrame) }
    }
}
