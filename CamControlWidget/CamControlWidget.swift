import WidgetKit
import SwiftUI
import AppIntents

struct CameraEntry: TimelineEntry {
    let date: Date
    let isPaired: Bool
    let isRecording: Bool
    let cameraName: String
    let otherCameraCount: Int
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CameraEntry {
        CameraEntry(date: .now, isPaired: true, isRecording: false, cameraName: "Camera", otherCameraCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (CameraEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CameraEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    // TODO(Stage B): this widget is being made configurable to a specific
    // paired camera. Until then it controls the first paired camera only.
    private func entry() -> CameraEntry {
        let cameras = SharedState.pairedCameras
        let primary = cameras.first
        return CameraEntry(
            date: .now,
            isPaired: primary != nil,
            isRecording: primary.map { SharedState.isRecording($0.id) } ?? false,
            cameraName: primary?.name ?? "Camera",
            otherCameraCount: max(cameras.count - 1, 0)
        )
    }
}

struct WidgetView: View {
    let entry: CameraEntry

    var body: some View {
        if entry.isPaired {
            controlView
        } else {
            unpaired
        }
    }

    private var controlView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.isRecording ? .red : .green)
                    .frame(width: 8, height: 8)
                Text(entry.isRecording ? "REC" : "Ready")
                    .font(.caption2.bold())
                    .foregroundStyle(entry.isRecording ? .red : .green)
            }

            Text(entry.otherCameraCount > 0 ? "\(entry.cameraName) +\(entry.otherCameraCount)" : entry.cameraName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button(intent: StartRecordingIntent()) {
                Label("Record", systemImage: "record.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .disabled(entry.isRecording)

            Button(intent: StopRecordingIntent()) {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(!entry.isRecording)

            Button(intent: TakePhotoIntent()) {
                Label("Photo", systemImage: "camera.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .containerBackground(.black, for: .widget)
    }

    private var unpaired: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open app\nto pair camera")
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
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Cam Control")
        .description("Start and stop your action camera.")
        .supportedFamilies([.systemSmall])
    }
}
