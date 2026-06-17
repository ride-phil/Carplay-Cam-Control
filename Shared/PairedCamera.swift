import Foundation

struct PairedCamera: Codable, Identifiable, Equatable {
    let id: UUID
    let type: CameraType
    let name: String
}
