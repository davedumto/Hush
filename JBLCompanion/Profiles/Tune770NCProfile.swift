import CoreBluetooth
import IOBluetooth

/// Profile for the JBL Tune 770NC, derived from the Bluetooth recon in ~/jbl-recon.
struct Tune770NCProfile: DeviceProfile {
    let displayName = "JBL Tune 770NC"
    let classicNameMatch = "770NC"
    let knownClassicAddress: String? = "00:A4:1C:AA:44:79"

    let bleScanServiceUUID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
    let bleExpectedName = "JBL Tune 770NC-LE"

    let batteryServiceUUID = CBUUID(string: "180F")
    let batteryLevelUUID = CBUUID(string: "2A19")

    let supportsNoiseControl = true
    let allowsRFCOMMWrites = true

    // SDP-confirmed (~/jbl-recon/sdp_output_rfcomm_check.txt): the "Airoha_APP" service, channel 21.
    let raceRFCOMMChannelID: BluetoothRFCOMMChannelID = 21

    // Hardware-verified (RaceFrameParser.StandardRaceEventByteMap's own doc comment) — this model
    // is the one the mapping was actually confirmed against.
    let eventMapVerified = true
    func noiseMode(forEventByte byte: UInt8) -> NoiseMode {
        StandardRaceEventByteMap.noiseMode(forEventByte: byte)
    }

    // Hardware-verified (see NoiseControlCommander.commandFrame's own doc comment): Ambient, ANC,
    // and TalkThru are all independently confirmed, by sending each frame and checking both the
    // resulting status event and the actual physical audio behavior. Off is not: no command frame
    // has ever been captured for it, so there's nothing to verify or enable yet.
    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool {
        switch mode {
        case .ambientAware, .anc, .talkThru: return true
        case .off: return false
        }
    }

    // writeAllowlist: no override needed — the protocol extension's default, derived from
    // isModeVerified above, is exactly right.
}
