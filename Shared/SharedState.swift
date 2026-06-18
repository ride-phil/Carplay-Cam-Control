import Foundation

struct SharedState {
    private static let suite = "group.io.camcontrol.app"
    private static var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    private enum Keys {
        static let pairedCameras     = "pairedCameras"
        static let recordingUUIDs    = "recordingCameraUUIDs"
        static let unreachableUUIDs  = "unreachableCameraUUIDs"
    }

    static var pairedCameras: [PairedCamera] {
        get {
            guard let data = defaults.data(forKey: Keys.pairedCameras),
                  let cameras = try? JSONDecoder().decode([PairedCamera].self, from: data) else {
                return []
            }
            return cameras
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: Keys.pairedCameras)
            CrossProcessNotifier.notifyStateChanged()
        }
    }

    static var recordingCameraUUIDs: Set<UUID> {
        get { Set((defaults.stringArray(forKey: Keys.recordingUUIDs) ?? []).compactMap(UUID.init)) }
        set {
            defaults.set(newValue.map(\.uuidString), forKey: Keys.recordingUUIDs)
            CrossProcessNotifier.notifyStateChanged()
        }
    }

    static func isRecording(_ id: UUID) -> Bool {
        recordingCameraUUIDs.contains(id)
    }

    static func setRecording(_ id: UUID, _ recording: Bool) {
        var uuids = recordingCameraUUIDs
        if recording { uuids.insert(id) } else { uuids.remove(id) }
        recordingCameraUUIDs = uuids
    }

    /// Cameras confirmed unreachable (peripheral not found) by a failed
    /// command or reconnect attempt — reflects current connectivity, not a
    /// stored property of the pairing itself.
    static var unreachableCameraUUIDs: Set<UUID> {
        get { Set((defaults.stringArray(forKey: Keys.unreachableUUIDs) ?? []).compactMap(UUID.init)) }
        set {
            defaults.set(newValue.map(\.uuidString), forKey: Keys.unreachableUUIDs)
            CrossProcessNotifier.notifyStateChanged()
        }
    }

    static func isUnreachable(_ id: UUID) -> Bool {
        unreachableCameraUUIDs.contains(id)
    }

    static func setUnreachable(_ id: UUID, _ unreachable: Bool) {
        var uuids = unreachableCameraUUIDs
        if unreachable { uuids.insert(id) } else { uuids.remove(id) }
        unreachableCameraUUIDs = uuids
    }
}
