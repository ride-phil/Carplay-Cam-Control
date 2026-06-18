import AppIntents
import WidgetKit

struct PhotoAllIntent: AppIntent {
    static let title: LocalizedStringResource = "Photo — All Cameras"
    static let description = IntentDescription("Take a photo on every paired camera")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        let cameras = SharedState.pairedCameras
        guard !cameras.isEmpty else { throw CameraError.peripheralNotFound }

        await withTaskGroup(of: Void.self) { group in
            for camera in cameras {
                group.addTask {
                    let driver = CameraDriverFactory.make(for: camera.type)
                    try? await driver.connect(peripheralID: camera.peripheralID)
                    try? await driver.takePhoto()
                    driver.disconnect()
                }
            }
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
