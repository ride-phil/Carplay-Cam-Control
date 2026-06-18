import Foundation
import CoreBluetooth

// Open GoPro BLE API — https://github.com/gopro/OpenGoPro. Officially documented for
// Hero9 Black and later, but the underlying BLE command set is the same one used since
// Hero5 Black; confirmed working here on a Hero7 Silver. Uses service FEA6.
final class GoProDriver: NSObject, CameraDriver {
    // Per-instance, not static — see Insta360Driver for why (avoids
    // serializing multiple concurrently-commanded cameras of the same type).
    private let bleQueue = DispatchQueue(label: "io.camcontrol.app.ble.gopro")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var queryWriteChar: CBCharacteristic?

    private var powerOnContinuation: CheckedContinuation<Void, Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var commandContinuation: CheckedContinuation<Void, Error>?
    private var queryContinuation: CheckedContinuation<[UInt8: [UInt8]], Error>?
    private let queryAccumulator = GoProResponseAccumulator()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
    }

    func connect(peripheralID: UUID) async throws {
        if central.state != .poweredOn {
            try await withCheckedThrowingContinuation { cont in powerOnContinuation = cont }
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
        // Shutter ON is a dumb toggle — force Video preset first so it doesn't take a photo
        // if the camera happens to be in Photo mode.
        try await send(BLEConstants.GoPro.loadVideoPresetGroup)
        try await send(BLEConstants.GoPro.shutterOn)
    }

    func stopRecording() async throws {
        try await send(BLEConstants.GoPro.shutterOff)
    }

    func takePhoto() async throws {
        // Same shutter toggle as startRecording — force Photo preset first so it takes a
        // photo instead of starting a video recording.
        try await send(BLEConstants.GoPro.loadPhotoPresetGroup)
        try await send(BLEConstants.GoPro.shutterOn)
    }

    func batteryPercentage() async throws -> Int {
        guard let p = peripheral, let char = queryWriteChar else { throw CameraError.notConnected }
        let params: [UInt8: [UInt8]] = try await withCheckedThrowingContinuation { cont in
            queryContinuation = cont
            p.writeValue(BLEConstants.GoPro.getBatteryStatus, for: char, type: .withResponse)
        }
        guard let bytes = params[BLEConstants.GoPro.batteryStatusId], let value = bytes.first else {
            throw CameraError.unsupported
        }
        return Int(value)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    private func send(_ data: Data) async throws {
        guard let p = peripheral, let char = commandChar else { throw CameraError.notConnected }
        try await withCheckedThrowingContinuation { cont in
            commandContinuation = cont
            p.writeValue(data, for: char, type: .withResponse)
        }
    }
}

extension GoProDriver: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: powerOnContinuation?.resume()
        default:         powerOnContinuation?.resume(throwing: CameraError.bluetoothUnavailable)
        }
        powerOnContinuation = nil
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BLEConstants.GoPro.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectContinuation?.resume(throwing: error ?? CameraError.connectionFailed)
        connectContinuation = nil
    }
}

extension GoProDriver: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { connectContinuation?.resume(throwing: error); connectContinuation = nil; return }
        guard let svc = peripheral.services?.first(where: { $0.uuid == BLEConstants.GoPro.serviceUUID }) else {
            connectContinuation?.resume(throwing: CameraError.serviceNotFound); connectContinuation = nil; return
        }
        peripheral.discoverCharacteristics([
            BLEConstants.GoPro.writeCharUUID,
            BLEConstants.GoPro.notifyCharUUID,
            BLEConstants.GoPro.queryWriteCharUUID,
            BLEConstants.GoPro.queryNotifyCharUUID,
        ], for: svc)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { connectContinuation?.resume(throwing: error); connectContinuation = nil; return }
        guard let chars = service.characteristics,
              let wChar = chars.first(where: { $0.uuid == BLEConstants.GoPro.writeCharUUID }) else {
            connectContinuation?.resume(throwing: CameraError.characteristicNotFound); connectContinuation = nil; return
        }
        commandChar = wChar
        queryWriteChar = chars.first(where: { $0.uuid == BLEConstants.GoPro.queryWriteCharUUID })
        if let notifyChar = chars.first(where: { $0.uuid == BLEConstants.GoPro.notifyCharUUID }) {
            peripheral.setNotifyValue(true, for: notifyChar)
        }
        if let queryNotifyChar = chars.first(where: { $0.uuid == BLEConstants.GoPro.queryNotifyCharUUID }) {
            peripheral.setNotifyValue(true, for: queryNotifyChar)
        }
        connectContinuation?.resume()
        connectContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == BLEConstants.GoPro.queryWriteCharUUID {
            // The meaningful response is the notify payload, not this transport ack —
            // only treat a write failure here as fatal (no notify will follow).
            if let error { queryContinuation?.resume(throwing: error); queryContinuation = nil }
            return
        }
        if let error { commandContinuation?.resume(throwing: error) } else { commandContinuation?.resume() }
        commandContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEConstants.GoPro.queryNotifyCharUUID else { return }
        if let error { queryContinuation?.resume(throwing: error); queryContinuation = nil; return }
        guard let data = characteristic.value, queryAccumulator.accumulate(data) else { return }
        guard queryAccumulator.status == 0x00 else {
            queryContinuation?.resume(throwing: CameraError.unsupported)
            queryContinuation = nil
            return
        }
        queryContinuation?.resume(returning: queryAccumulator.parseParams())
        queryContinuation = nil
    }
}

/// Reassembles GoPro's general BLE packet framing (responses can be fragmented
/// across multiple ~20-byte BLE packets) and parses query-style TLV payloads.
/// Verified against gopro/OpenGoPro's official tutorial source, not guessed:
/// https://github.com/gopro/OpenGoPro/blob/main/demos/python/tutorial/tutorial_modules/tutorial_3_parse_ble_tlv_responses/ble_command_get_hardware_info.py
private final class GoProResponseAccumulator {
    private var rawBytes: [UInt8] = []
    private var bytesRemaining = 0

    /// Feeds one notify packet in. Returns true once a full response has
    /// been accumulated (call status/parseParams only after that).
    func accumulate(_ data: Data) -> Bool {
        var buf = [UInt8](data)
        guard let first = buf.first else { return false }

        if first & 0b1000_0000 != 0 {
            buf.removeFirst()
        } else {
            rawBytes = []
            switch (first & 0b0110_0000) >> 5 {
            case 0: // General: 5-bit length in this byte
                bytesRemaining = Int(first & 0b0001_1111)
                buf.removeFirst()
            case 1: // Ext13: 13-bit length across this byte + next
                guard buf.count >= 2 else { return false }
                bytesRemaining = (Int(first & 0b0001_1111) << 8) + Int(buf[1])
                buf.removeFirst(2)
            case 2: // Ext16: 16-bit length in next two bytes
                guard buf.count >= 3 else { return false }
                bytesRemaining = (Int(buf[1]) << 8) + Int(buf[2])
                buf.removeFirst(3)
            default:
                return false
            }
        }

        rawBytes.append(contentsOf: buf)
        bytesRemaining -= buf.count
        return !rawBytes.isEmpty && bytesRemaining <= 0
    }

    /// Outer TLV: [response id, status, payload...]
    var status: UInt8 { rawBytes.count >= 2 ? rawBytes[1] : 0xFF }

    /// Query payload is itself repeated [param id, param length, value...].
    func parseParams() -> [UInt8: [UInt8]] {
        guard rawBytes.count > 2 else { return [:] }
        var buf = Array(rawBytes.dropFirst(2))
        var result: [UInt8: [UInt8]] = [:]
        while buf.count >= 2 {
            let paramId = buf[0]
            let paramLen = Int(buf[1])
            buf.removeFirst(2)
            guard buf.count >= paramLen else { break }
            result[paramId] = Array(buf.prefix(paramLen))
            buf.removeFirst(paramLen)
        }
        return result
    }
}
