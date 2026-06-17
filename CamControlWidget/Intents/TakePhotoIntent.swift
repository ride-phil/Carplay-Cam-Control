import AppIntents
import WidgetKit

struct TakePhotoIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Photo"
    static let description = IntentDescription("Take a photo on the paired action camera")
    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard let uuid = SharedState.pairedPeripheralUUID,
              let type = SharedState.pairedCameraType else {
            throw CameraError.peripheralNotFound
        }
        let driver = CameraDriverFactory.make(for: type)
        try await driver.connect(peripheralID: uuid)
        try await driver.takePhoto()
        driver.disconnect()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
