import Foundation
import Observation

enum ConnectionState {
    case disconnected
    case connected
}

enum NoiseMode {
    case off
    case anc
    case ambientAware
    case talkThru
    case unknown
}

@Observable
@MainActor
final class HeadphoneState {
    var connection: ConnectionState = .disconnected
    var deviceName: String = ""
    var batteryPercent: Int?
    var noiseMode: NoiseMode = .unknown
    var lastUpdated: Date?
}
