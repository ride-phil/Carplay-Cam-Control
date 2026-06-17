import Foundation
import CoreBluetooth

final class Insta360AceProDriver: NSObject, CameraDriver {
    private static let bleQueue = DispatchQueue(label: "com.ridephilippines.aceprorecorder.ble.insta360")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?

    private var powerOnContinuation: CheckedContinuation<Void, Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var commandContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: Self.bleQueue)
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

extension Insta360AceProDriver: CBCentralManagerDelegate {
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

extension Insta360AceProDriver: CBPeripheralDelegate {
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
            commandContinuation?.resume(throwing: error)
        } else {
            commandContinuation?.resume()
        }
        commandContinuation = nil
    }
}
