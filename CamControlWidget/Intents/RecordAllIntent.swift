import AppIntents
import WidgetKit

struct RecordAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Record All Cameras"
    static let description = IntentDescription("Start recording on every paired camera")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let cameras = SharedState.pairedCameras
        guard !cameras.isEmpty else { throw CameraError.peripheralNotFound }

        await withTaskGroup(of: (UUID, Error?).self) { group in
            for camera in cameras {
                group.addTask {
                    let driver = CameraDriverFactory.make(for: camera.type)
                    do {
                        try await driver.connect(peripheralID: camera.peripheralID)
                        try await driver.startRecording()
                        driver.disconnect()
                        return (camera.id, nil)
                    } catch {
                        return (camera.id, error)
                    }
                }
            }
            // Consumed serially so SharedState writes for different cameras don't race.
            for await (id, error) in group {
                if let error {
                    if case CameraError.peripheralNotFound = error {
                        SharedState.setUnreachable(id, true)
                    }
                } else {
                    SharedState.setRecording(id, true)
                    SharedState.setUnreachable(id, false)
                }
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
