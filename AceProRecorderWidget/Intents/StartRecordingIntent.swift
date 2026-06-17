import AppIntents
import WidgetKit

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Start recording on the paired action camera")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let uuid = SharedState.pairedPeripheralUUID,
              let type = SharedState.pairedCameraType else {
            throw CameraError.peripheralNotFound
        }
        let driver = CameraDriverFactory.make(for: type)
        try await driver.connect(peripheralID: uuid)
        try await driver.startRecording()
        driver.disconnect()
        SharedState.isRecording = true
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
