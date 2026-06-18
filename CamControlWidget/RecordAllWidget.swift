import WidgetKit
import SwiftUI
import AppIntents

struct AllCamerasEntry: TimelineEntry {
    let date: Date
    let totalCount: Int
    let recordingCount: Int
}

struct AllCamerasProvider: TimelineProvider {
    func placeholder(in context: Context) -> AllCamerasEntry {
        AllCamerasEntry(date: .now, totalCount: 1, recordingCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (AllCamerasEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AllCamerasEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .never))
    }

    private func entry() -> AllCamerasEntry {
        let cameras = SharedState.pairedCameras
        let recording = cameras.filter { SharedState.isRecording($0.id) }.count
        return AllCamerasEntry(date: .now, totalCount: cameras.count, recordingCount: recording)
    }
}

struct AllCamerasWidgetView: View {
    let entry: AllCamerasEntry

    var body: some View {
        if entry.totalCount == 0 {
            unpaired
        } else {
            controlView
        }
    }

    private var controlView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(entry.recordingCount > 0 ? .red : .green)
                    .frame(width: 8, height: 8)
                Text(entry.recordingCount > 0 ? "\(entry.recordingCount)/\(entry.totalCount) REC" : "\(entry.totalCount) Ready")
                    .font(.caption2.bold())
                    .foregroundStyle(entry.recordingCount > 0 ? .red : .green)
            }

            Button(intent: RecordAllIntent()) {
                Label("Record All", systemImage: "record.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)

            Button(intent: StopAllIntent()) {
                Label("Stop All", systemImage: "stop.circle.fill")
                    .font(.callout.bold())
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Button(intent: PhotoAllIntent()) {
                Label("Photo All", systemImage: "camera.circle.fill")
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
            Text("No cameras\npaired")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .containerBackground(.black, for: .widget)
    }
}

struct RecordAllWidget: Widget {
    let kind = "RecordAllWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AllCamerasProvider()) { entry in
            AllCamerasWidgetView(entry: entry)
        }
        .configurationDisplayName("Record All Cameras")
        .description("Start, stop, or photograph with every paired camera at once.")
        .supportedFamilies([.systemSmall])
    }
}
