import SwiftUI
import CoreBluetooth

struct ConnectView: View {
    @ObservedObject var manager: PairingManager

    var body: some View {
        NavigationStack {
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

                Section {
                    Label("GoPro: enable Connections → Connect Device → GoPro App on the camera before scanning, the first time you pair it.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connect")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(manager.isScanning ? "Stop" : "Scan") {
                        manager.isScanning ? manager.stopScanning() : manager.startScanning()
                    }
                }
            }
        }
    }
}
