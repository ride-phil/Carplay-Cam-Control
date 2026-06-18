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
    /// Stable id of the paired camera currently being re-scanned for, if any.
    @Published var reconnectingCameraID: UUID?
    /// Cameras confirmed unreachable (peripheral not found) by a failed
    /// command or reconnect attempt. In-memory only — reflects current
    /// connectivity, not a stored property of the pairing itself.
    @Published var unreachableCameraIDs: Set<UUID> = []
    /// Battery percentage per camera, where known — only populated for camera
    /// types whose driver supports querying it (currently GoPro only).
    @Published var batteryLevels: [UUID: Int] = [:]
    /// Raw bytes from the camera's last BLE response after a photo command —
    /// diagnostic only, for investigating mode-dependent behavior (e.g. Ace Pro).
    @Published var lastDebugResponse: String?

    private var central: CBCentralManager!
    private var pairingTarget: CBPeripheral?
    private var scanTimeoutTask: Task<Void, Never>?

    private static let scanTimeoutNanos: UInt64 = 30_000_000_000
    private static let reconnectTimeoutNanos: UInt64 = 10_000_000_000

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        reloadFromSharedState()
        // The widget extension runs as a separate process — when a widget
        // intent changes SharedState, this is how the already-running app
        // finds out and refreshes its in-memory copy.
        CrossProcessNotifier.observeStateChanged { [weak self] in
            Task { @MainActor in
                self?.reloadFromSharedState()
            }
        }
    }

    private func reloadFromSharedState() {
        pairedCameras = SharedState.pairedCameras
        recordingUUIDs = SharedState.recordingCameraUUIDs
        unreachableCameraIDs = SharedState.unreachableCameraUUIDs
        batteryLevels = SharedState.batteryLevels
    }

    func startScanning() {
        guard central.state == .poweredOn else { errorMessage = "Bluetooth is not available"; return }
        discoveredPeripherals = []
        errorMessage = nil
        isScanning = true
        // Scan for all supported camera service UUIDs
        let services = [BLEConstants.Insta360.serviceUUID, BLEConstants.GoPro.serviceUUID]
        central.scanForPeripherals(withServices: services)

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.scanTimeoutNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isScanning, self.reconnectingCameraID == nil else { return }
                self.stopScanning()
                if self.discoveredPeripherals.isEmpty {
                    self.errorMessage = "No cameras found nearby."
                }
            }
        }
    }

    func stopScanning() {
        central.stopScan()
        isScanning = false
        scanTimeoutTask?.cancel()
        reconnectingCameraID = nil
    }

    func pair(_ peripheral: CBPeripheral) {
        stopScanning()
        isPairing = true
        errorMessage = nil
        pairingTarget = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    /// Re-scans for a previously paired camera by name and rebinds its
    /// BLE peripheral identity in place, without losing its stable id,
    /// recording state, or widget configuration. Needed because some
    /// cameras (e.g. without BLE bonding) get a new peripheral identity
    /// from iOS after a power cycle, so the old one stops resolving.
    func reconnect(_ camera: PairedCamera) {
        guard central.state == .poweredOn else { errorMessage = "Bluetooth is not available"; return }
        stopScanning()
        discoveredPeripherals = []
        errorMessage = nil
        reconnectingCameraID = camera.id
        isScanning = true
        let services = [BLEConstants.Insta360.serviceUUID, BLEConstants.GoPro.serviceUUID]
        central.scanForPeripherals(withServices: services)

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.reconnectTimeoutNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.reconnectingCameraID == camera.id else { return }
                self.stopScanning()
                self.errorMessage = "\(camera.name): not found — make sure it's powered on and nearby"
                self.setUnreachable(camera.id, true)
            }
        }
    }

    func unpair(_ camera: PairedCamera) {
        pairedCameras.removeAll { $0.id == camera.id }
        SharedState.pairedCameras = pairedCameras
        recordingUUIDs.remove(camera.id)
        SharedState.setRecording(camera.id, false)
        unreachableCameraIDs.remove(camera.id)
        SharedState.setUnreachable(camera.id, false)
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

    private func setUnreachable(_ id: UUID, _ unreachable: Bool) {
        SharedState.setUnreachable(id, unreachable)
        if unreachable { unreachableCameraIDs.insert(id) } else { unreachableCameraIDs.remove(id) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func setBattery(_ id: UUID, _ percent: Int) {
        SharedState.setBatteryLevel(id, percent)
        batteryLevels[id] = percent
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func runCommand(_ camera: PairedCamera, _ action: @escaping (CameraDriver) async throws -> Void) async {
        isSendingCommand = true
        errorMessage = nil
        let driver = CameraDriverFactory.make(for: camera.type)
        do {
            try await driver.connect(peripheralID: camera.peripheralID)
            try await action(driver)
            // Opportunistic — piggyback a battery check on the connection we
            // already have open rather than requiring a dedicated action.
            // Unsupported camera types just throw and are silently skipped.
            if let battery = try? await driver.batteryPercentage() {
                setBattery(camera.id, battery)
            }
            driver.disconnect()
            setUnreachable(camera.id, false)
        } catch {
            errorMessage = "\(camera.name): \(error.localizedDescription)"
            if case CameraError.peripheralNotFound = error {
                setUnreachable(camera.id, true)
            }
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
        await withTaskGroup(of: (PairedCamera, Error?, Int?).self) { group in
            for camera in cameras {
                group.addTask {
                    let driver = CameraDriverFactory.make(for: camera.type)
                    do {
                        try await driver.connect(peripheralID: camera.peripheralID)
                        try await action(driver)
                        let battery = try? await driver.batteryPercentage()
                        driver.disconnect()
                        return (camera, nil, battery)
                    } catch {
                        return (camera, error, nil)
                    }
                }
            }
            for await (camera, error, battery) in group {
                if let battery {
                    setBattery(camera.id, battery)
                }
                if let error {
                    failures.append("\(camera.name): \(error.localizedDescription)")
                    if case CameraError.peripheralNotFound = error {
                        setUnreachable(camera.id, true)
                    }
                } else {
                    onSuccess(camera.id)
                    setUnreachable(camera.id, false)
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

    private func rebind(_ camera: PairedCamera, to peripheral: CBPeripheral) {
        guard let index = pairedCameras.firstIndex(where: { $0.id == camera.id }) else { return }
        pairedCameras[index].peripheralID = peripheral.identifier
        SharedState.pairedCameras = pairedCameras
        setUnreachable(camera.id, false)
    }
}

extension PairingManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // UI reacts to isScanning; no action needed here
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            if let targetID = reconnectingCameraID,
               let target = pairedCameras.first(where: { $0.id == targetID }),
               peripheral.name == target.name {
                scanTimeoutTask?.cancel()
                stopScanning()
                reconnectingCameraID = nil
                rebind(target, to: peripheral)
                return
            }
            if reconnectingCameraID == nil, !discoveredPeripherals.contains(peripheral) {
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
            let name = peripheral.name ?? type.displayName
            if let index = pairedCameras.firstIndex(where: { $0.peripheralID == peripheral.identifier || $0.name == name }) {
                // Already paired (or reappearing under a new peripheral identity) — rebind rather than duplicate.
                let stableID = pairedCameras[index].id
                pairedCameras[index].peripheralID = peripheral.identifier
                SharedState.pairedCameras = pairedCameras
                setUnreachable(stableID, false)
            } else {
                let camera = PairedCamera(id: UUID(), peripheralID: peripheral.identifier, type: type, name: name)
                pairedCameras.append(camera)
                SharedState.pairedCameras = pairedCameras
            }
            isPairing = false
            central.cancelPeripheralConnection(peripheral)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
