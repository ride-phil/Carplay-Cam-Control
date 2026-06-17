import WidgetKit
import SwiftUI
import AppIntents

struct CameraEntry: TimelineEntry {
    let date: Date
    let isPaired: Bool
    let isRecording: Bool
    let cameraName: String
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> CameraEntry {
        CameraEntry(date: .now, isPaired: true, isRecording: false, cameraName: "Ace Pro")
    }

    func getSnapshot(in context: Context, completion: @escaping (CameraEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CameraEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> CameraEntry {
        CameraEntry(
            date: .now,
            isPaired: SharedState.pairedPeripheralUUID != nil,
            isRecording: SharedState.isRecording,
            cameraName: SharedState.pairedCameraType?.displayName ?? "Camera"
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
                    .fill(entry.isRecording ? .red : .gray)
                    .frame(width: 8, height: 8)
                Text(entry.isRecording ? "REC" : "Ready")
                    .font(.caption2.bold())
                    .foregroundStyle(entry.isRecording ? .red : .secondary)
            }

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

struct AceProRecorderWidget: Widget {
    let kind = "AceProRecorderWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Cam Control")
        .description("Start and stop your action camera.")
        .supportedFamilies([.systemSmall])
    }
}
