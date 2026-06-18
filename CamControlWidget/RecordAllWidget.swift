import WidgetKit
import SwiftUI
import AppIntents

struct AllCamerasEntry: TimelineEntry {
    let date: Date
    let totalCount: Int
    let recordingCount: Int
    let unreachableCount: Int
}

struct AllCamerasProvider: TimelineProvider {
    func placeholder(in context: Context) -> AllCamerasEntry {
        AllCamerasEntry(date: .now, totalCount: 1, recordingCount: 0, unreachableCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (AllCamerasEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AllCamerasEntry>) -> Void) {
        // Self-corrects on an 8s cadence on top of the explicit reloadAllTimelines()
        // calls every intent makes — see CamControlWidget.Provider for why.
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(8))))
    }

    private func entry() -> AllCamerasEntry {
        let cameras = SharedState.pairedCameras
        let recording = cameras.filter { SharedState.isRecording($0.id) }.count
        let unreachable = cameras.filter { SharedState.isUnreachable($0.id) }.count
        return AllCamerasEntry(date: .now, totalCount: cameras.count, recordingCount: recording, unreachableCount: unreachable)
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
        let statusColor: Color = entry.recordingCount > 0 ? .red : (entry.unreachableCount > 0 ? .orange : .green)
        let statusText = entry.recordingCount > 0
            ? "\(entry.recordingCount)/\(entry.totalCount) REC"
            : (entry.unreachableCount > 0 ? "\(entry.unreachableCount)/\(entry.totalCount) Unreachable" : "\(entry.totalCount) Ready")

        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.caption2.bold())
                    .foregroundStyle(statusColor)
            }

            // Diagnostic: self-updating, no extra refresh cost — reveals
            // whether stale status is a real data bug or just a display lag.
            Text(entry.date, style: .relative)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            WidgetActionButton(title: "Record All", icon: "record.circle.fill", color: .red,
                                intent: RecordAllIntent(), isDisabled: entry.recordingCount == entry.totalCount)
            WidgetActionButton(title: "Stop All", icon: "stop.circle.fill", color: .primary,
                                intent: StopAllIntent(), isDisabled: entry.recordingCount == 0)
            WidgetActionButton(title: "Photo All", icon: "camera.circle.fill", color: .blue, intent: PhotoAllIntent())
        }
        .padding(8)
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
