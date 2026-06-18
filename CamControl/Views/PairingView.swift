import SwiftUI
import CoreBluetooth

struct PairingView: View {
    @StateObject private var manager = PairingManager()

    var body: some View {
        NavigationStack {
            List {
                if !manager.pairedCameras.isEmpty {
                    Section("All Cameras") {
                        allCamerasRow
                    }

                    Section("Paired") {
                        ForEach(manager.pairedCameras) { camera in
                            pairedCameraRow(camera)
                        }
                    }
                }

                if manager.isScanning || manager.isPairing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(manager.isPairing ? "Pairing…" : "Scanning for cameras…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !manager.discoveredPeripherals.isEmpty {
                    Section("Found") {
                        ForEach(manager.discoveredPeripherals, id: \.identifier) { peripheral in
                            Button {
                                manager.pair(peripheral)
                            } label: {
                                HStack {
                                    Image(systemName: "camera.circle")
                                    Text(peripheral.name ?? peripheral.identifier.uuidString)
                                }
                            }
                            .disabled(manager.isPairing)
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

                if manager.pairedCameras.isEmpty && !manager.isScanning && manager.discoveredPeripherals.isEmpty && manager.errorMessage == nil {
                    Section {
                        Text("Tap Scan to find nearby cameras.\nMake sure the camera is powered on.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Camera Control")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(manager.isScanning ? "Stop" : "Scan") {
                        manager.isScanning ? manager.stopScanning() : manager.startScanning()
                    }
                }
            }
        }
    }

    private var allCamerasRow: some View {
        let recordingCount = manager.pairedCameras.filter { manager.recordingUUIDs.contains($0.id) }.count

        return VStack(alignment: .leading, spacing: 12) {
            Text(recordingCount > 0
                 ? "\(recordingCount) of \(manager.pairedCameras.count) recording"
                 : "\(manager.pairedCameras.count) camera\(manager.pairedCameras.count == 1 ? "" : "s") ready")
                .foregroundStyle(recordingCount > 0 ? .red : .green)
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

    private func pairedCameraRow(_ camera: PairedCamera) -> some View {
        let isRecording = manager.recordingUUIDs.contains(camera.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "camera.fill")
                    .foregroundStyle(isRecording ? .red : .green)
                Text(camera.name)
                    .font(.headline)
                Spacer()
                Text(isRecording ? "Recording" : "Ready")
                    .font(.caption)
                    .foregroundStyle(isRecording ? .red : .green)
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
