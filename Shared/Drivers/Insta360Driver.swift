import Foundation
import CoreBluetooth
import os

final class Insta360Driver: NSObject, CameraDriver {
    // Per-instance, not static — a shared queue would serialize multiple
    // concurrently-commanded Insta360 cameras (e.g. via Record All) behind
    // each other, delaying their actual BLE completion relative to other
    // camera types that aren't sharing a queue.
    private let bleQueue = DispatchQueue(label: "io.camcontrol.app.ble.insta360")
    private static let log = Logger(subsystem: "io.camcontrol.app", category: "Insta360BLE")

    /// Raw bytes from the camera's last notify response, captured for protocol
    /// debugging (e.g. the Ace Pro photo-mode investigation) — not yet parsed
    /// or used for control logic, since the response format is undocumented.
    static private(set) var lastNotifyHex: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?

    private var powerOnContinuation: CheckedContinuation<Void, Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var commandContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
    }

    func connect(peripheralID: UUID) async throws {
        if central.state != .poweredOn {
            try await withCheckedThrowingContinuation { cont in
                powerOnContinuation = cont
            }
        }

        let found = central.retrievePeripherals(withIdentifiers: [peripheralID])
        guard let p = found.first else { throw CameraError.peripheralNotFound }

        peripheral = p
        p.delegate = self

        try await withCheckedThrowingContinuation { cont in
            connectContinuation = cont
            central.connect(p)
        }
    }

    func startRecording() async throws {
        try await send(CommandPacket.insta360(.startVideo))
    }

    func stopRecording() async throws {
        try await send(CommandPacket.insta360(.stopVideo))
    }

    func takePhoto() async throws {
        Self.lastNotifyHex = nil
        try await send(CommandPacket.insta360(.takePhoto))
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    private func send(_ data: Data) async throws {
        guard let p = peripheral, let char = writeChar else { throw CameraError.notConnected }
        try await withCheckedThrowingContinuation { cont in
            commandContinuation = cont
            p.writeValue(data, for: char, type: .withResponse)
        }
    }
}

extension Insta360Driver: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            powerOnContinuation?.resume()
        default:
            powerOnContinuation?.resume(throwing: CameraError.bluetoothUnavailable)
        }
        powerOnContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BLEConstants.Insta360.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectContinuation?.resume(throwing: error ?? CameraError.connectionFailed)
        connectContinuation = nil
    }
}

extension Insta360Driver: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { connectContinuation?.resume(throwing: error); connectContinuation = nil; return }
        guard let svc = peripheral.services?.first(where: { $0.uuid == BLEConstants.Insta360.serviceUUID }) else {
            connectContinuation?.resume(throwing: CameraError.serviceNotFound); connectContinuation = nil; return
        }
        peripheral.discoverCharacteristics([BLEConstants.Insta360.writeCharUUID, BLEConstants.Insta360.notifyCharUUID], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { connectContinuation?.resume(throwing: error); connectContinuation = nil; return }
        guard let chars = service.characteristics,
              let wChar = chars.first(where: { $0.uuid == BLEConstants.Insta360.writeCharUUID }) else {
            connectContinuation?.resume(throwing: CameraError.characteristicNotFound); connectContinuation = nil; return
        }
        writeChar = wChar
        if let nChar = chars.first(where: { $0.uuid == BLEConstants.Insta360.notifyCharUUID }) {
            peripheral.setNotifyValue(true, for: nChar)
        }
        connectContinuation?.resume()
        connectContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Self.log.error("write ack failed: \(error.localizedDescription, privacy: .public)")
            commandContinuation?.resume(throwing: error)
        } else {
            Self.log.debug("write ack: ok")
            commandContinuation?.resume()
        }
        commandContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Self.log.error("notify error: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let data = characteristic.value else { return }
        let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        Self.lastNotifyHex = hex
        Self.log.debug("notify <- \(hex, privacy: .public)")
    }
}
