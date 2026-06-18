import Foundation

protocol CameraDriver {
    func connect(peripheralID: UUID) async throws
    func startRecording() async throws
    func stopRecording() async throws
    func takePhoto() async throws
    func disconnect()
    /// Battery percentage (0-100), if this camera/driver supports querying it.
    /// Default throws .unsupported — only override where verified against a
    /// real protocol spec, not guessed.
    func batteryPercentage() async throws -> Int
}

extension CameraDriver {
    func batteryPercentage() async throws -> Int {
        throw CameraError.unsupported
    }
}
