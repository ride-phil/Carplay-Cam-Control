import Foundation
import CoreBluetooth
import WidgetKit

@MainActor
final class PairingManager: NSObject, ObservableObject {
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var pairedCameras: [PairedCamera] = []
    @Published var recordingUUIDs: Set<UUID> = []
    @Published var isScanning = false
    @Published var isPairing = false
    @Published var isSendingCommand = false
    @Published var errorMessage: String?
    /// Raw bytes from the camera's last BLE response after a photo command —
    /// diagnostic only, for investigating mode-dependent behavior (e.g. Ace Pro).
    @Published var lastDebugResponse: String?

    private var central: CBCentralManager!
    private var pairingTarget: CBPeripheral?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        pairedCameras = SharedState.pairedCameras
        recordingUUIDs = SharedState.recordingCameraUUIDs
    }

    func startScanning() {
        guard central.state == .poweredOn else { errorMessage = "Bluetooth is not available"; return }
        discoveredPeripherals = []
        errorMessage = nil
        isScanning = true
        // Scan for all supported camera service UUIDs
        let services = [BLEConstants.Insta360.serviceUUID, BLEConstants.GoPro.serviceUUID]
        central.scanForPeripherals(withServices: services)
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
    }

    func pair(_ peripheral: CBPeripheral) {
        stopScanning()
        isPairing = true
        errorMessage = nil
        pairingTarget = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func unpair(_ camera: PairedCamera) {
        pairedCameras.removeAll { $0.id == camera.id }
        SharedState.pairedCameras = pairedCameras
        recordingUUIDs.remove(camera.id)
        SharedState.setRecording(camera.id, false)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func startRecording(_ camera: PairedCamera) async {
        await runCommand(camera) { driver in try await driver.startRecording() }
        if errorMessage == nil { setRecording(camera.id, true) }
    }

    func stopRecording(_ camera: PairedCamera) async {
        await runCommand(camera) { driver in try await driver.stopRecording() }
        if errorMessage == nil { setRecording(camera.id, false) }
    }

    func takePhoto(_ camera: PairedCamera) async {
        await runCommand(camera) { driver in try await driver.takePhoto() }
        if camera.type == .insta360 {
            lastDebugResponse = Insta360Driver.lastNotifyHex
        }
    }

    func startRecordingAll() async {
        await runCommandAll({ driver in try await driver.startRecording() },
                             onSuccess: { [weak self] id in self?.setRecording(id, true) })
    }

    func stopRecordingAll() async {
        await runCommandAll({ driver in try await driver.stopRecording() },
                             onSuccess: { [weak self] id in self?.setRecording(id, false) })
    }

    func takePhotoAll() async {
        await runCommandAll({ driver in try await driver.takePhoto() }, onSuccess: { _ in })
    }

    private func setRecording(_ id: UUID, _ recording: Bool) {
        SharedState.setRecording(id, recording)
        if recording { recordingUUIDs.insert(id) } else { recordingUUIDs.remove(id) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func runCommand(_ camera: PairedCamera, _ action: @escaping (CameraDriver) async throws -> Void) async {
        isSendingCommand = true
        errorMessage = nil
        let driver = CameraDriverFactory.make(for: camera.type)
        do {
            try await driver.connect(peripheralID: camera.id)
            try await action(driver)
            driver.disconnect()
        } catch {
            errorMessage = "\(camera.name): \(error.localizedDescription)"
        }
        isSendingCommand = false
    }

    /// Runs `action` against every paired camera concurrently and reports any
    /// per-camera failures together rather than failing the whole batch.
    private func runCommandAll(
        _ action: @escaping (CameraDriver) async throws -> Void,
        onSuccess: @escaping (UUID) -> Void
    ) async {
        let cameras = pairedCameras
        guard !cameras.isEmpty else { return }
        isSendingCommand = true
        errorMessage = nil

        var failures: [String] = []
        await withTaskGroup(of: (PairedCamera, Error?).self) { group in
            for camera in cameras {
                group.addTask {
                    let driver = CameraDriverFactory.make(for: camera.type)
                    do {
                        try await driver.connect(peripheralID: camera.id)
                        try await action(driver)
                        driver.disconnect()
                        return (camera, nil)
                    } catch {
                        return (camera, error)
                    }
                }
            }
            for await (camera, error) in group {
                if let error {
                    failures.append("\(camera.name): \(error.localizedDescription)")
                } else {
                    onSuccess(camera.id)
                }
            }
        }

        errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        isSendingCommand = false
    }

    private func cameraType(for peripheral: CBPeripheral) -> CameraType? {
        // Type is inferred from which service we discover during pairing
        if peripheral.services?.contains(where: { $0.uuid == BLEConstants.Insta360.serviceUUID }) == true {
            return .insta360
        }
        if peripheral.services?.contains(where: { $0.uuid == BLEConstants.GoPro.serviceUUID }) == true {
            return .goPro
        }
        return nil
    }
}

extension PairingManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // UI reacts to isScanning; no action needed here
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            if !discoveredPeripherals.contains(peripheral) {
                discoveredPeripherals.append(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let services = [BLEConstants.Insta360.serviceUUID, BLEConstants.GoPro.serviceUUID]
        peripheral.discoverServices(services)
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            isPairing = false
            errorMessage = error?.localizedDescription ?? "Connection failed"
        }
    }
}

extension PairingManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            Task { @MainActor in isPairing = false; errorMessage = error.localizedDescription }
            return
        }
        // Discover characteristics for whichever known service was found
        if let svc = peripheral.services?.first(where: { $0.uuid == BLEConstants.Insta360.serviceUUID }) {
            peripheral.discoverCharacteristics([BLEConstants.Insta360.writeCharUUID, BLEConstants.Insta360.notifyCharUUID], for: svc)
        } else if let svc = peripheral.services?.first(where: { $0.uuid == BLEConstants.GoPro.serviceUUID }) {
            peripheral.discoverCharacteristics([BLEConstants.GoPro.writeCharUUID], for: svc)
        } else {
            Task { @MainActor in isPairing = false; errorMessage = "No supported camera service found" }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            Task { @MainActor in isPairing = false; errorMessage = error.localizedDescription }
            return
        }
        Task { @MainActor in
            guard let type = cameraType(for: peripheral) else {
                isPairing = false; errorMessage = "Unrecognised camera type"; return
            }
            let camera = PairedCamera(id: peripheral.identifier, type: type, name: peripheral.name ?? type.displayName)
            if !pairedCameras.contains(where: { $0.id == camera.id }) {
                pairedCameras.append(camera)
                SharedState.pairedCameras = pairedCameras
            }
            isPairing = false
            central.cancelPeripheralConnection(peripheral)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
