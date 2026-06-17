import Foundation

enum CameraType: String, Codable, CaseIterable {
    case insta360 = "insta360"
    case goPro    = "go_pro"
    case dji      = "dji"

    /// Generic protocol-family label — prefer PairedCamera.name (the real BLE
    /// device name) for display; this is only a fallback.
    var displayName: String {
        switch self {
        case .insta360: return "Insta360"
        case .goPro:    return "GoPro"
        case .dji:      return "DJI"
        }
    }
}
