import Foundation

enum CameraError: LocalizedError {
    case bluetoothUnavailable
    case peripheralNotFound
    case connectionFailed
    case serviceNotFound
    case characteristicNotFound
    case notConnected
    case writeTimeout

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:     return "Bluetooth is not available"
        case .peripheralNotFound:       return "Camera not found — open the app to re-pair"
        case .connectionFailed:         return "Failed to connect to camera"
        case .serviceNotFound:          return "Camera BLE service not found"
        case .characteristicNotFound:   return "Camera BLE characteristic not found"
        case .notConnected:             return "Not connected to camera"
        case .writeTimeout:             return "Command timed out"
        }
    }
}
