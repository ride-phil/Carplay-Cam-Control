import CoreBluetooth

enum BLEConstants {
    enum Insta360 {
        static let serviceUUID      = CBUUID(string: "0000be80-0000-1000-8000-00805f9b34fb")
        static let writeCharUUID    = CBUUID(string: "0000be81-0000-1000-8000-00805f9b34fb")
        static let notifyCharUUID   = CBUUID(string: "0000be82-0000-1000-8000-00805f9b34fb")

        enum Command: UInt8 {
            case startVideo = 0x04
            case stopVideo  = 0x05
            case takePhoto  = 0x03
        }
    }

    enum GoPro {
        // GoPro Open API BLE — service FEA6, command characteristic B5F90072
        static let serviceUUID      = CBUUID(string: "FEA6")
        static let writeCharUUID    = CBUUID(string: "B5F90072-AA8D-11E3-9046-0002A5D5C51B")
        static let notifyCharUUID   = CBUUID(string: "B5F90073-AA8D-11E3-9046-0002A5D5C51B")

        // Command packets (TLV: type 0x01, length 0x01, value)
        static let startVideo: Data = Data([0x03, 0x01, 0x01, 0x01])
        static let stopVideo: Data  = Data([0x03, 0x01, 0x01, 0x00])
        static let takePhoto: Data  = Data([0x03, 0x01, 0x01, 0x01]) // shutter in photo mode
    }
}
