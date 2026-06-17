import AppIntents
import WidgetKit

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Start recording on the paired action camera")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        // TODO(Stage B): operate on the camera this widget instance is configured for.
        guard let camera = SharedState.pairedCameras.first else {
            throw CameraError.peripheralNotFound
        }
        let driver = CameraDriverFactory.make(for: camera.type)
        try await driver.connect(peripheralID: camera.id)
        try await driver.startRecording()
        driver.disconnect()
        SharedState.setRecording(camera.id, true)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
