import AppIntents
import Foundation

/// AppEntity wrapper around PairedCamera so widget configuration UI
/// (Edit Widget) can list paired cameras and let the user pick one.
struct CameraEntity: AppEntity {
    let id: UUID
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Camera"
    static var defaultQuery = CameraEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(camera: PairedCamera) {
        self.id = camera.id
        self.name = camera.name
    }
}

struct CameraEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CameraEntity] {
        SharedState.pairedCameras
            .filter { identifiers.contains($0.id) }
            .map(CameraEntity.init(camera:))
    }

    func suggestedEntities() async throws -> [CameraEntity] {
        SharedState.pairedCameras.map(CameraEntity.init(camera:))
    }
}
