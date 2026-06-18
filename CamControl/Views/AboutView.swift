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
                    Label("GoPro (Hero 7 and later) — Record/Stop confirmed; Photo fix pending verification", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("DJI — not yet supported", systemImage: "xmark.circle.fill")
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
