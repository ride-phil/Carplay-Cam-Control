import AppIntents
import WidgetKit

struct StopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stop recording on the selected camera")
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Camera")
    var camera: CameraEntity?

    init() {}

    init(camera: CameraEntity) {
        self.camera = camera
    }

    func perform() async throws -> some IntentResult {
        guard let entity = camera,
              let paired = SharedState.pairedCameras.first(where: { $0.id == entity.id }) else {
            throw CameraError.peripheralNotFound
        }
        let driver = CameraDriverFactory.make(for: paired.type)
        try await driver.connect(peripheralID: paired.peripheralID)
        try await driver.stopRecording()
        driver.disconnect()
        SharedState.setRecording(paired.id, false)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
