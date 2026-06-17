import Foundation

struct SharedState {
    private static let suite = "group.com.ridephilippines.aceprorecorder"
    private static var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    private enum Keys {
        static let peripheralUUID = "pairedPeripheralUUID"
        static let cameraType     = "pairedCameraType"
        static let isRecording    = "isRecording"
    }

    static var pairedPeripheralUUID: UUID? {
        get {
            guard let str = defaults.string(forKey: Keys.peripheralUUID) else { return nil }
            return UUID(uuidString: str)
        }
        set { defaults.set(newValue?.uuidString, forKey: Keys.peripheralUUID) }
    }

    static var pairedCameraType: CameraType? {
        get {
            guard let raw = defaults.string(forKey: Keys.cameraType) else { return nil }
            return CameraType(rawValue: raw)
        }
        set { defaults.set(newValue?.rawValue, forKey: Keys.cameraType) }
    }

    static var isRecording: Bool {
        get { defaults.bool(forKey: Keys.isRecording) }
        set { defaults.set(newValue, forKey: Keys.isRecording) }
    }
}
