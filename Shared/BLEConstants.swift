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

        // GoPro general BLE packet format: [payload length, command ID, param length, param bytes...].
        // Verified against gopro/OpenGoPro's official source (CmdId enum + tutorial examples), not guessed:
        // https://github.com/gopro/OpenGoPro/blob/main/demos/python/sdk_wireless_camera_control/open_gopro/models/constants/constants.py
        // SET_SHUTTER = 0x01 is a dumb toggle — its effect (start video vs take photo) depends entirely
        // on which preset group (Photo/Video/Timelapse) is currently active, so it must be preceded by
        // LOAD_PRESET_GROUP (0x3E) to get reliable behavior regardless of the camera's current state.
        static let shutterOn: Data  = Data([0x03, 0x01, 0x01, 0x01])
        static let shutterOff: Data = Data([0x03, 0x01, 0x01, 0x00])
        // EnumPresetGroup: PRESET_GROUP_ID_VIDEO = 1000 (0x03E8), PRESET_GROUP_ID_PHOTO = 1001 (0x03E9)
        static let loadVideoPresetGroup: Data = Data([0x04, 0x3E, 0x02, 0x03, 0xE8])
        static let loadPhotoPresetGroup: Data = Data([0x04, 0x3E, 0x02, 0x03, 0xE9])
    }
}
