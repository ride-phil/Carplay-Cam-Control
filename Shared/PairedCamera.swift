import Foundation

struct PairedCamera: Codable, Identifiable, Equatable {
    /// Stable app-level identity, assigned once at pairing time. Used for
    /// recording state, widget configuration, and UI — never changes, even
    /// if the camera's underlying BLE identity changes across power cycles.
    let id: UUID
    /// Current/last-known CoreBluetooth peripheral identifier. This is the
    /// volatile, hardware-assigned identity actually used to connect — it
    /// can be rebound (see PairingManager.reconnect) without losing the
    /// camera's paired identity, recording state, or widget configuration.
    var peripheralID: UUID
    let type: CameraType
    let name: String
}
