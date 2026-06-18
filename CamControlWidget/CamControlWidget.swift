import WidgetKit
import SwiftUI
import AppIntents

struct CameraEntry: TimelineEntry {
    let date: Date
    let cameraID: UUID?
    let cameraName: String
    let isRecording: Bool
    let isUnreachable: Bool
    let isConfigured: Bool
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CameraEntry {
        CameraEntry(date: .now, cameraID: UUID(), cameraName: "Camera", isRecording: false, isUnreachable: false, isConfigured: true)
    }

    func snapshot(for configuration: SelectCameraIntent, in context: Context) async -> CameraEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectCameraIntent, in context: Context) async -> Timeline<CameraEntry> {
        // Self-corrects on an 8s cadence on top of the explicit reloadAllTimelines()
        // calls every intent makes — WidgetCenter reloads triggered from another
        // widget/the app are subject to iOS's own refresh budget and aren't
        // guaranteed to land promptly, so this is a bounded-time backstop.
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(8)))
    }

    private func entry(for configuration: SelectCameraIntent) -> CameraEntry {
        guard let selected = configuration.camera else {
            return CameraEntry(date: .now, cameraID: nil, cameraName: "", isRecording: false, isUnreachable: false, isConfigured: false)
        }
        guard let camera = SharedState.pairedCameras.first(where: { $0.id == selected.id }) else {
            return CameraEntry(date: .now, cameraID: nil, cameraName: selected.name, isRecording: false, isUnreachable: false, isConfigured: true)
        }
        return CameraEntry(
            date: .now,
            cameraID: camera.id,
            cameraName: camera.name,
            isRecording: SharedState.isRecording(camera.id),
            isUnreachable: SharedState.isUnreachable(camera.id),
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

        let statusColor: Color = entry.isUnreachable ? .orange : (entry.isRecording ? .red : .green)
        let statusText = entry.isUnreachable ? "Unreachable" : (entry.isRecording ? "REC" : "Ready")

        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(entry.cameraName)
                    .font(.caption2.bold())
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor)
            }

            // Diagnostic: self-updating, no extra refresh cost — reveals
            // whether stale status is a real data bug or just a display lag.
            Text(entry.date, style: .relative)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            WidgetActionButton(title: "Record", icon: "record.circle.fill", color: .red,
                                intent: StartRecordingIntent(camera: camera), isDisabled: entry.isRecording)

            WidgetActionButton(title: "Stop", icon: "stop.circle.fill", color: .primary,
                                intent: StopRecordingIntent(camera: camera), isDisabled: !entry.isRecording)

            WidgetActionButton(title: "Photo", icon: "camera.circle.fill", color: .blue,
                                intent: TakePhotoIntent(camera: camera))
        }
        .padding(8)
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
