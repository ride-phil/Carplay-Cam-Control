import Foundation

enum CameraDriverFactory {
    static func make(for type: CameraType) -> CameraDriver {
        switch type {
        case .insta360:         return Insta360Driver()
        case .goPro:            return GoProDriver()
        case .dji:              return DJIDriver()
        }
    }
}
