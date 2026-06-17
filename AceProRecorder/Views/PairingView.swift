import SwiftUI
import CoreBluetooth

struct PairingView: View {
    @StateObject private var manager = PairingManager()

    var body: some View {
        NavigationStack {
            Group {
                if let camera = manager.pairedCamera {
                    pairedState(camera: camera)
                } else {
                    scanState
                }
            }
            .navigationTitle("Camera Control")
            .toolbar {
                if manager.pairedCamera == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(manager.isScanning ? "Stop" : "Scan") {
                            manager.isScanning ? manager.stopScanning() : manager.startScanning()
                        }
                    }
                }
            }
        }
    }

    private func pairedState(camera: PairedCamera) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(camera.type.displayName)
                .font(.title2.bold())
            Text("Paired — widget is ready")
                .foregroundStyle(.secondary)
            Button("Unpair", role: .destructive) {
                manager.unpair()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var scanState: some View {
        List {
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

            if !manager.isScanning && manager.discoveredPeripherals.isEmpty && manager.errorMessage == nil {
                Section {
                    Text("Tap Scan to find nearby cameras.\nMake sure the camera is powered on.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
        }
    }
}
