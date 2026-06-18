import AppIntents

struct SelectCameraIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Camera"
    static let description = IntentDescription("Choose which paired camera this widget controls")

    @Parameter(title: "Camera")
    var camera: CameraEntity?
}
