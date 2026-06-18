import AppIntents
import WidgetKit

struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Start recording on the selected camera")
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
        try await driver.startRecording()
        driver.disconnect()
        SharedState.setRecording(paired.id, true)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
