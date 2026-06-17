import Foundation

// DJI BLE control is not publicly documented and varies significantly by model.
// DJI Action 4 exposes some BLE services but the command protocol is undiscovered.
// Wi-Fi SDK control is NOT viable here — it would drop mobile data during CarPlay.
//
// This stub throws .peripheralNotFound until BLE protocol is reverse-engineered.
// Tracking: https://github.com/ride-phil/Carplay-Cam-Control/issues (open an issue when investigating)
final class DJIDriver: CameraDriver {
    func connect(peripheralID: UUID) async throws  { throw CameraError.peripheralNotFound }
    func startRecording() async throws             { throw CameraError.notConnected }
    func stopRecording() async throws              { throw CameraError.notConnected }
    func takePhoto() async throws                  { throw CameraError.notConnected }
    func disconnect()                              {}
}
