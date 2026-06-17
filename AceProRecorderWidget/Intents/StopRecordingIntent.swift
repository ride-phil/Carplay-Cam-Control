import AppIntents
import WidgetKit

struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stop recording on the paired action camera")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let uuid = SharedState.pairedPeripheralUUID,
              let type = SharedState.pairedCameraType else {
            throw CameraError.peripheralNotFound
        }
        let driver = CameraDriverFactory.make(for: type)
        try await driver.connect(peripheralID: uuid)
        try await driver.stopRecording()
        driver.disconnect()
        SharedState.isRecording = false
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
