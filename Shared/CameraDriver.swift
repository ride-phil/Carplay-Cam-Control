import Foundation

protocol CameraDriver {
    func connect(peripheralID: UUID) async throws
    func startRecording() async throws
    func stopRecording() async throws
    func takePhoto() async throws
    func disconnect()
}
