import AppIntents
import WidgetKit

struct StopAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop All Cameras"
    static let description = IntentDescription("Stop recording on every paired camera")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let cameras = SharedState.pairedCameras
        guard !cameras.isEmpty else { throw CameraError.peripheralNotFound }

        await withTaskGroup(of: (UUID, Bool).self) { group in
            for camera in cameras {
                group.addTask {
                    let driver = CameraDriverFactory.make(for: camera.type)
                    do {
                        try await driver.connect(peripheralID: camera.peripheralID)
                        try await driver.stopRecording()
                        driver.disconnect()
                        return (camera.id, true)
                    } catch {
                        return (camera.id, false)
                    }
                }
            }
            // Consumed serially so SharedState writes for different cameras don't race.
            for await (id, succeeded) in group where succeeded {
                SharedState.setRecording(id, false)
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
