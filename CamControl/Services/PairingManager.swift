import Foundation
import CoreBluetooth
import WidgetKit

struct PairedCamera {
    let uuid: UUID
    let type: CameraType
}

@MainActor
final class PairingManager: NSObject, ObservableObject {
    @Published var discoveredPeripherals: [CBPeripheral] = []
    @Published var pairedCamera: PairedCamera?
    @Published var isScanning = false
    @Published var isPairing = false
    @Published var isRecording = SharedState.isRecording
    @Published var isSendingCommand = false
    @Published var errorMessage: String?

    private var central: CBCentralManager!
    private var pairingTarget: CBPeripheral?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        if let uuid = SharedState.pairedPeripheralUUID, let type = SharedState.pairedCameraType {
            pairedCamera = PairedCamera(uuid: uuid, type: type)
        }
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

    func unpair() {
        SharedState.pairedPeripheralUUID = nil
        SharedState.pairedCameraType = nil
        pairedCamera = nil
        if let p = pairingTarget { central.cancelPeripheralConnection(p) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func startRecording() async {
        await runCommand { driver in try await driver.startRecording() }
        if errorMessage == nil {
            isRecording = true
            SharedState.isRecording = true
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func stopRecording() async {
        await runCommand { driver in try await driver.stopRecording() }
        if errorMessage == nil {
            isRecording = false
            SharedState.isRecording = false
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func takePhoto() async {
        await runCommand { driver in try await driver.takePhoto() }
    }

    private func runCommand(_ action: @escaping (CameraDriver) async throws -> Void) async {
        guard let camera = pairedCamera else { return }
        isSendingCommand = true
        errorMessage = nil
        let driver = CameraDriverFactory.make(for: camera.type)
        do {
            try await driver.connect(peripheralID: camera.uuid)
            try await action(driver)
            driver.disconnect()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSendingCommand = false
    }

    private func cameraType(for peripheral: CBPeripheral) -> CameraType? {
        // Type is inferred from which service we discover during pairing
        if peripheral.services?.contains(where: { $0.uuid == BLEConstants.Insta360.serviceUUID }) == true {
            return .insta360AcePro
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
            SharedState.pairedPeripheralUUID = peripheral.identifier
            SharedState.pairedCameraType = type
            pairedCamera = PairedCamera(uuid: peripheral.identifier, type: type)
            isPairing = false
            central.cancelPeripheralConnection(peripheral)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
