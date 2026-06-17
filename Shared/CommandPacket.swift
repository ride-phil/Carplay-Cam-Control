import Foundation

enum CommandPacket {
    static func insta360(_ command: BLEConstants.Insta360.Command) -> Data {
        let bytes: [UInt8] = [
            0x10, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, command.rawValue,
            0x00, 0x02, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00
        ]
        return Data(bytes)
    }
}
