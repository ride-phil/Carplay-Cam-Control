import AppIntents
import WidgetKit

struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stop recording on the paired action camera")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        // TODO(Stage B): operate on the camera this widget instance is configured for.
        guard let camera = SharedState.pairedCameras.first else {
            throw CameraError.peripheralNotFound
        }
        let driver = CameraDriverFactory.make(for: camera.type)
        try await driver.connect(peripheralID: camera.id)
        try await driver.stopRecording()
        driver.disconnect()
        SharedState.setRecording(camera.id, false)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
