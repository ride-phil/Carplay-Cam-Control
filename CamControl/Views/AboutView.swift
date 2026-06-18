import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.aperture")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)
                        Text("Cam Control")
                            .font(.title2.bold())
                        Text("Version \(version) (\(build))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section("About") {
                    Text("Control action cameras over Bluetooth LE from your phone, a Home Screen widget, or CarPlay's Dashboard — without unlocking your phone.")
                        .font(.callout)
                }

                Section("Supported Cameras") {
                    Label("Insta360 X3, X4 — reliable, any mode", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("Insta360 Ace Pro — must be in Photo mode to take photos", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Label("GoPro Hero 7 — Record/Stop reliable; Photo starts a video instead (older camera, not being pursued further)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Label("DJI — not yet supported", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }

                Section("Battery Level") {
                    Text("GoPro only, for now — shown on each camera's row and in a dedicated Battery widget. Insta360 and DJI show as Unknown.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Known Limitations") {
                    Text("The app doesn't detect when a camera powers off in real time — it only notices on the next command attempt. If commands stop working after a power cycle, use the Reconnect button on that camera's row in the Cameras tab.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
        }
    }
}
