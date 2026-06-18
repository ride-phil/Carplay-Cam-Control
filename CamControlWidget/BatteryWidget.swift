import WidgetKit
import SwiftUI
import AppIntents

struct BatteryEntry: TimelineEntry {
    let date: Date
    let cameraID: UUID?
    let cameraName: String
    let batteryPercent: Int?
    let isUnreachable: Bool
    let isConfigured: Bool
}

struct BatteryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: .now, cameraID: UUID(), cameraName: "Camera", batteryPercent: 80, isUnreachable: false, isConfigured: true)
    }

    func snapshot(for configuration: SelectCameraIntent, in context: Context) async -> BatteryEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: SelectCameraIntent, in context: Context) async -> Timeline<BatteryEntry> {
        // Same 8s self-correcting backstop as the other widgets — battery is
        // only refreshed opportunistically (piggybacked on other commands) or
        // via this widget's own Refresh button, so this just keeps the
        // *display* in sync with whatever SharedState last recorded.
        Timeline(entries: [entry(for: configuration)], policy: .after(.now.addingTimeInterval(8)))
    }

    private func entry(for configuration: SelectCameraIntent) -> BatteryEntry {
        guard let selected = configuration.camera else {
            return BatteryEntry(date: .now, cameraID: nil, cameraName: "", batteryPercent: nil, isUnreachable: false, isConfigured: false)
        }
        guard let camera = SharedState.pairedCameras.first(where: { $0.id == selected.id }) else {
            return BatteryEntry(date: .now, cameraID: nil, cameraName: selected.name, batteryPercent: nil, isUnreachable: false, isConfigured: true)
        }
        return BatteryEntry(
            date: .now,
            cameraID: camera.id,
            cameraName: camera.name,
            batteryPercent: SharedState.batteryLevel(camera.id),
            isUnreachable: SharedState.isUnreachable(camera.id),
            isConfigured: true
        )
    }
}

struct BatteryWidgetView: View {
    let entry: BatteryEntry

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
        let (icon, color) = batteryIconAndColor

        return VStack(spacing: 6) {
            Text(entry.cameraName)
                .font(.caption2.bold())
                .lineLimit(1)

            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color)

            Text(batteryText)
                .font(.caption.bold())
                .foregroundStyle(color)

            Text(entry.date, style: .relative)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            WidgetActionButton(title: "Refresh", icon: "arrow.clockwise", color: .blue,
                                intent: CheckBatteryIntent(camera: camera))
        }
        .padding(8)
        .containerBackground(.black, for: .widget)
    }

    private var batteryText: String {
        if entry.isUnreachable { return "Unreachable" }
        guard let percent = entry.batteryPercent else { return "Unknown" }
        return "\(percent)%"
    }

    private var batteryIconAndColor: (String, Color) {
        if entry.isUnreachable { return ("battery.0", .orange) }
        guard let percent = entry.batteryPercent else { return ("battery.0", .secondary) }
        switch percent {
        case 0..<15:  return ("battery.0", Color.red)
        case 15..<40: return ("battery.25", Color.orange)
        case 40..<65: return ("battery.50", Color.yellow)
        case 65..<90: return ("battery.75", Color.green)
        default:      return ("battery.100", Color.green)
        }
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

struct BatteryWidget: Widget {
    let kind = "BatteryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectCameraIntent.self, provider: BatteryProvider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName("Camera Battery")
        .description("Battery level for one selected paired camera. Currently GoPro only — other camera types show Unknown.")
        .supportedFamilies([.systemSmall])
    }
}
