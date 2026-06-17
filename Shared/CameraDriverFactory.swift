import Foundation

enum CameraDriverFactory {
    static func make(for type: CameraType) -> CameraDriver {
        switch type {
        case .insta360AcePro:   return Insta360AceProDriver()
        case .goPro:            return GoProDriver()
        case .dji:              return DJIDriver()
        }
    }
}
