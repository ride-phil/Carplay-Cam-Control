import AppIntents
import WidgetKit

struct PhotoAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Photo — All Cameras"
    static let description = IntentDescription("Take a photo on every paired camera")
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
                        try await driver.takePhoto()
                        driver.disconnect()
                        return (camera.id, nil)
                    } catch {
                        return (camera.id, error)
                    }
                }
            }
            for await (id, error) in group {
                if let error, case CameraError.peripheralNotFound = error {
                    SharedState.setUnreachable(id, true)
                } else if error == nil {
                    SharedState.setUnreachable(id, false)
                }
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
