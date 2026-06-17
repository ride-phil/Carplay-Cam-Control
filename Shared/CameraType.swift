import Foundation

enum CameraType: String, Codable, CaseIterable {
    case insta360AcePro = "insta360_ace_pro"
    case goPro          = "go_pro"
    case dji            = "dji"

    var displayName: String {
        switch self {
        case .insta360AcePro:   return "Insta360 Ace Pro"
        case .goPro:            return "GoPro"
        case .dji:              return "DJI"
        }
    }
}
