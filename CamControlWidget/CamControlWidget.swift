import WidgetKit
import SwiftUI
import AppIntents

struct CameraEntry: TimelineEntry {
    let date: Date
    let cameraID: UUID?
    let cameraName: String
    let isRecording: Bool
    let isConfigured: Bool
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CameraEntry {
        CameraEntry(date: .now, cameraID: UUID(), cameraName: "Camera", isRecording: false, isConfigured: true)
    }

    func snapshot(for configuration: SelectCameraIntent, in context: Context) async -> CameraEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectCameraIntent, in context: Context) async -> Timeline<CameraEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    private func entry(for configuration: SelectCameraIntent) -> CameraEntry {
        guard let selected = configuration.camera else {
            return CameraEntry(date: .now, cameraID: nil, cameraName: "", isRecording: false, isConfigured: false)
        }
        guard let camera = SharedState.pairedCameras.first(where: { $0.id == selected.id }) else {
            return CameraEntry(date: .now, cameraID: nil, cameraName: selected.name, isRecording: false, isConfigured: true)
        }
        return CameraEntry(
            date: .now,
            cameraID: camera.id,
            cameraName: camera.name,
            isRecording: SharedState.isRecording(camera.id),
            isConfigured: true
        )
    }
}

struct WidgetView: View {
    let entry: CameraEntry

    var body: some View {
        if let id = entry.cameraID {
            controlView(cameraID: id)
        } else if entry.isConfigured {
            messageView(icon: "camera.badge.exclamationmark", text: "\(entry.cameraName)\nno longer paired")
        } else {
            messageView(icon: "camera.badge.ellipsis", text: "Press and hold\nto select a camera")
        }
    }

    private func controlView(cameraID: UUID) -> some View {
        let camera = CameraEntity(id: cameraID, name: entry.cameraName)

        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.isRecording ? .red : .green)
                    .frame(width: 8, height: 8)
                Text(entry.isRecording ? "REC" : "Ready")
                    .font(.caption2.bold())
                    .foregroundStyle(entry.isRecording ? .red : .green)
            }

            Text(entry.cameraName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button(intent: StartRecordingIntent(camera: camera)) {
                Label("Record", systemImage: "record.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(entry.isRecording)

            Button(intent: StopRecordingIntent(camera: camera)) {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(!entry.isRecording)

            Button(intent: TakePhotoIntent(camera: camera)) {
                Label("Photo", systemImage: "camera.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .containerBackground(.black, for: .widget)
    }

    private func messageView(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.black, for: .widget)
    }
}

struct CamControlWidget: Widget {
    let kind = "CamControlWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCameraIntent.self, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Cam Control")
        .description("Control one specific paired camera. Add multiple widgets to control multiple cameras.")
        .supportedFamilies([.systemSmall])
    }
}
