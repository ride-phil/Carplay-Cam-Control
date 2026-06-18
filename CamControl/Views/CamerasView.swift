import SwiftUI

struct CamerasView: View {
    @ObservedObject var manager: PairingManager

    var body: some View {
        NavigationStack {
            List {
                if manager.pairedCameras.isEmpty {
                    emptyState
                } else {
                    Section("All Cameras") {
                        allCamerasRow
                    }

                    Section("Paired") {
                        ForEach(manager.pairedCameras) { camera in
                            pairedCameraRow(camera)
                        }
                    }
                }

                if let error = manager.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if let debug = manager.lastDebugResponse {
                    Section("Debug — Last Camera Response") {
                        Text(debug)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Cameras")
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No cameras paired yet")
                    .font(.headline)
                Text("Go to the Connect tab to scan for nearby cameras.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .listRowBackground(Color.clear)
        }
    }

    private var allCamerasRow: some View {
        let total = manager.pairedCameras.count
        let recordingCount = manager.pairedCameras.filter { manager.recordingUUIDs.contains($0.id) }.count
        let unreachableCount = manager.pairedCameras.filter { manager.unreachableCameraIDs.contains($0.id) }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text(allCamerasSummary(total: total, recording: recordingCount, unreachable: unreachableCount))
                .foregroundStyle(recordingCount > 0 ? .red : (unreachableCount > 0 ? .orange : .green))
                .font(.callout)

            HStack(spacing: 12) {
                Button {
                    Task { await manager.startRecordingAll() }
                } label: {
                    Label("Record All", systemImage: "record.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(manager.isSendingCommand)

                Button {
                    Task { await manager.stopRecordingAll() }
                } label: {
                    Label("Stop All", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isSendingCommand)
            }

            Button {
                Task { await manager.takePhotoAll() }
            } label: {
                Label("Photo — All Cameras", systemImage: "camera.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(manager.isSendingCommand)
        }
        .padding(.vertical, 4)
    }

    private func allCamerasSummary(total: Int, recording: Int, unreachable: Int) -> String {
        if recording > 0 { return "\(recording) of \(total) recording" }
        if unreachable > 0 { return "\(unreachable) of \(total) unreachable" }
        return "\(total) camera\(total == 1 ? "" : "s") ready"
    }

    private func pairedCameraRow(_ camera: PairedCamera) -> some View {
        let isRecording = manager.recordingUUIDs.contains(camera.id)
        let isUnreachable = manager.unreachableCameraIDs.contains(camera.id)
        let statusColor: Color = isUnreachable ? .orange : (isRecording ? .red : .green)
        let statusText = isUnreachable ? "Unreachable" : (isRecording ? "Recording" : "Ready")

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "camera.fill")
                    .foregroundStyle(statusColor)
                Text(camera.name)
                    .font(.headline)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 8) {
                Button {
                    Task { await manager.startRecording(camera) }
                } label: {
                    Image(systemName: "record.circle.fill")
                }
                .tint(.red)
                .disabled(isRecording || manager.isSendingCommand)

                Button {
                    Task { await manager.stopRecording(camera) }
                } label: {
                    Image(systemName: "stop.circle.fill")
                }
                .disabled(!isRecording || manager.isSendingCommand)

                Button {
                    Task { await manager.takePhoto(camera) }
                } label: {
                    Image(systemName: "camera.circle.fill")
                }
                .disabled(manager.isSendingCommand)

                Spacer()

                Button {
                    manager.reconnect(camera)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .disabled(manager.reconnectingCameraID == camera.id)

                Button(role: .destructive) {
                    manager.unpair(camera)
                } label: {
                    Image(systemName: "xmark.circle")
                }
            }
            .buttonStyle(.bordered)

            if manager.reconnectingCameraID == camera.id {
                Text("Reconnecting…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if camera.name.localizedCaseInsensitiveContains("Ace Pro") {
                Text("Switch to Photo mode before taking a photo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
