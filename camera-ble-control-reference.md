# Camera BLE Control Reference: Insta360, GoPro, DJI

Purpose: source material for porting the Insta360 Ace Pro CarPlay widget's BLE control layer from Android (working) to iOS/Swift (CoreBluetooth). The unbuilt piece is the pairing/connection flow. Includes parallel research on GoPro and DJI in case the widget expands to support those cameras.

---

## 1. Insta360

### 1.1 Official iOS SDK (primary resource)

- Repo: https://github.com/Insta360Develop/iOS-SDK (current branch `V1.9.2`, Nov 2025)
- Apply for SDK access (appId/secretKey, needed for camera activation): https://www.insta360.com/sdk/apply
- Developer portal: https://www.insta360.com/developer/home
- Online manual / integration guide: https://onlinemanual.insta360.com/developer/en-us/resource/sdk
- Android SDK (for cross-referencing the existing working implementation): https://github.com/Insta360Develop/Android-SDK

**Connection states** (`INSCameraManager.socket().cameraState`):
```
INSCameraStateFound            // found, not connected
INSCameraStateSynchronized     // synced, not connected
INSCameraStateConnected        // connected, can send requests
INSCameraStateConnectFailed
INSCameraStateNoConnection
```

**BLE connection flow:**
```swift
// 1. Scan
INSBluetoothManager().scanCameras

// 2. Connect
- (id)connectDevice:(INSBluetoothDevice *)device
         completion:(void (^)(NSError * _Nullable))completion;

// 3. Disconnect
- (void)disconnectDevice:(INSBluetoothDevice *)device;
```

**Critical: heartbeat requirement.** The camera disconnects if it doesn't receive a heartbeat within 30 seconds. Any session that stays open (preview, recording) needs a repeating heartbeat, e.g. every 0.5s:
```swift
func startSendingHeartbeats() {
    let commandManager = INSCameraManager.shared().commandManager
    GCDTimer.shared.scheduledDispatchTimer(
        WithTimerName: "HeartbeatsTimer",
        timeInterval: 0.5,
        queue: DispatchQueue.main,
        repeats: true
    ) {
        commandManager.sendHeartbeats(with: nil)
    }
}
```

**BLE limitations:** no large data transfer. Unsupported over BLE: preview, retrieve supported list, download files, firmware upgrade, playback, image export. After connecting BLE, you can call `getOptionsWithTypes` to retrieve Wi-Fi SSID/password if you need to upgrade to a Wi-Fi connection for higher-bandwidth operations.

**Error codes of note:** `INSCameraErrorCodeShakeHandeError = 445`, `INSCameraErrorCodePairError = 446`, `INSCameraErrorCodeCentralManagerNotInited = 601` — all directly relevant to debugging the pairing flow.

Required frameworks (drag into target): `INSCoreMedia.xcframework`, `INSCameraServiceSDK.xcframework`, `INSCameraSDK.xcframework`, `SSZipArchive.xcframework`. Build setting: `TO_B_SDK=1`.

### 1.2 Protocol-level / reverse-engineered reference

- Medium: "BLE Control of Insta360 Cameras" by Patrick Chwalek — https://medium.com/@patrickchwalek/ble-control-of-insta360-cameras-7bf6894648a4

Useful if you need to debug below the SDK's abstraction layer. Key finding: the camera's BLE remote-discovery feature expects the connecting device to advertise the name **"Insta360 GPS Remote"** — an ESP32 spoofing this name was recognized and accepted as a remote, after which standard remote commands (shutter, mode-cycle, short-press power = screen toggle, long-press power = shutdown) worked. Also notes a "Bluetooth Wakeup" feature where the camera retains a small (~0.1Wh) standby power draw even when nominally off, implying the BLE radio is listening for a wake command even in "off" state.

---

## 2. GoPro

GoPro is the most developer-friendly of the three: there's an official, free, MIT-licensed protocol spec with the actual BLE characteristic UUIDs published — no reverse engineering required.

### 2.1 Official program

- Hub: https://gopro.github.io/OpenGoPro/
- BLE spec: https://gopro.github.io/OpenGoPro/ble/
- Main repo (specs + demos + tutorials): https://github.com/gopro/OpenGoPro
- Demos folder index: https://github.com/gopro/OpenGoPro/tree/main/demos
- **Official Swift/iOS demo (CoreBluetooth)**: `demos/swift/EnableWiFiDemo` — https://github.com/gopro/OpenGoPro/tree/main/demos/swift/EnableWiFiDemo — this is your most direct reference for porting the pairing flow, since it's GoPro's own CoreBluetooth implementation.
- Python SDK (full reference implementation, useful for cross-checking command sequences even though you're targeting Swift): https://gopro.github.io/OpenGoPro/python_sdk/
- BLE walkthrough tutorial (sending TLV commands): https://gopro.github.io/OpenGoPro/tutorials/send-ble-commands

Supported cameras (public BLE API, minimum firmware): HERO9 Black (v01.70.00), HERO10 Black (v01.10.00), HERO11 Black (v01.10.00), HERO11 Black Mini (v01.10.00), HERO12 Black (v01.10.00).

### 2.2 BLE architecture

- BLE handles command-and-control (settings, start/stop capture, battery/SD status query) and is required to bootstrap Wi-Fi — the camera's Wi-Fi must be turned on via a BLE command before any Wi-Fi-dependent feature (streaming, media transfer) is available.
- Messages are written to a write-enabled UUID, then the client waits for a notification on the corresponding response UUID. Subscriptions are not cached by the device and must be re-subscribed on every connection.
- GoPro does not support caching of notification subscriptions — re-subscribe characteristics on every reconnect, not just first pairing.

### 2.3 GATT-level reference (confirmed UUIDs)

Primary advertised service UUID: `FEA6` (16-bit, expands to `0000fea6-0000-1000-8000-00805f9b34fb`). Scanning for this UUID will surface nearby GoPro cameras.

Per a Swift/iOS developer writeup (Doubletapp), the camera exposes three services: **GoPro WiFi Access Point**, **GoPro Camera Management**, and **Control & Query**. Key characteristics under Control & Query (`FEA6`):

```
Command Request:   B5F90072-AA8D-11E3-9046-0002A5D5C51B   (write)
Command Response:  B5F90073-AA8D-11E3-9046-0002A5D5C51B   (notify)
```

Example command/response exchange (shutter on):
```
write  -> B5F90072...: 03:01:01:01
notify <- B5F90073...: 02:01:00   (success — third byte 0x00)
```
Load Preset Group (switch to Video):
```
write -> B5F90072...: 04:3E:02:03:E8
```

Reference sources for the above: Doubletapp Swift article — https://doubletapp.medium.com/parsing-responses-to-ble-commands-in-swift-using-the-example-of-gopro-b7ca27190cd5 ; official tutorial — https://gopro.github.io/OpenGoPro/tutorials/send-ble-commands ; community handle/UUID table (older HERO models) — https://github.com/KonradIT/goprowifihack/blob/master/Bluetooth/bluetooth-api.md

### 2.4 Known gotcha (Swift/CoreBluetooth specific)

GitHub issue #157 on gopro/OpenGoPro documents a malformed multi-packet response bug reproduced by a developer "leveraging CoreBluetooth" while extending the official Swift demo — relevant if you see corrupted responses on payloads larger than a single BLE packet (~20 bytes), since those get fragmented and must be reassembled. https://github.com/gopro/OpenGoPro/issues/157

### 2.5 App Store note

A developer's experience (issue #404) building a Swift GoPro-control app from the official sample ran into Apple requiring proof of GoPro compatibility/trademark permission before App Store approval — worth budgeting time for if you ever ship a public GoPro-control feature. https://github.com/gopro/OpenGoPro/issues/404

---

## 3. DJI (Osmo Action / Osmo Pocket / Osmo Mobile)

DJI is the most fragmented: an official but narrowly-scoped protocol, plus community reverse engineering that covers more ground.

### 3.1 Official: DJI R SDK

- Repo (protocol + ESP32 demo): https://github.com/dji-sdk/Osmo-GPS-Controller-Demo
- Protocol doc: https://github.com/dji-sdk/Osmo-GPS-Controller-Demo/blob/main/docs/protocol.md

This is DJI's own published protocol for third-party control of Osmo 360 and Osmo Action 6 / 5 Pro / 4. Frame structure: SOF → header fields → SEQ → DATA, with CRC-16 over SOF-through-SEQ and CRC-32 over SOF-through-DATA (reference implementations: `custom_crc32.c`, `custom_crc16.c` in the demo). The CmdType field's bit 5 distinguishes Command Frame vs Response Frame; bits [4:0] indicate whether a response is required (0 = none, 1 = optional, 2–31 = mandatory).

The demo runs on ESP32-C6 (ESP-IDF) and implements: long-press to discover/connect nearest compatible Osmo Action/Osmo 360, single-click record start/stop, mode switching, and 10Hz GPS data push. Protocol layer is explicitly designed to be platform-independent and portable — useful since you'd be reimplementing the BLE transport in CoreBluetooth, not the protocol logic.

Note: **DJI Mobile SDK** (developer.dji.com) is a separate, much larger SDK aimed at drones and the Osmo Mobile gimbal line (Bluetooth product connector class included) — it is not the right path for Action-series cameras. Don't confuse the two when searching DJI's developer docs.

### 3.2 Reverse-engineered: DUML protocol (cross-product)

DJI's actual wire protocol across most of its product line — Osmo Action, Osmo Pocket, Osmo Mobile gimbals, even Mavic drones — is internally called **DUML**. Three community projects map it out at the GATT/byte level:

- **yigitkonur/lib-osmo-ble** (Node.js, Osmo Pocket 3, most detailed) — https://github.com/yigitkonur/lib-osmo-ble
  - Characteristic UUIDs: `FFF3` (write w/ response — accepts writes silently ignored by firmware, a trap) and `FFF5` (read/writeWithoutResponse/notify/indicate — the channel that actually processes DUML commands). **Only write to FFF5; FFF3 is a silent dead end.**
  - Partial command table (CmdSet/CmdID): `0x04/0x01` raw PWM gimbal, `0x04/0x05` position telemetry (~20Hz push), `0x04/0x0A` absolute angle, `0x04/0x0C` velocity control, `0x04/0x4C` set mode, `0x07/0x45` set pairing PIN, `0x07/0x46` pairing approved, `0x07/0x47` Wi-Fi connect.
  - Includes a CLI, BLE scanner, characteristic inspector, and DUML message decoder/CRC verifier tool — useful for debugging your own pairing implementation against real traffic.
  - Ships a patch fixing 7 bugs in the older `node-osmo` library, including a NodeJS-specific `ByteBuf`/buffer-pool offset bug that silently corrupted all decoded message types — worth reading if you port any byte-parsing logic from JS reference implementations.

- **datagutt/node-osmo** (TypeScript, Osmo Action 3/4/5 + Pocket 3) — https://github.com/datagutt/node-osmo

- **alkersan/om-research** (Python, documents Osmo Mobile gimbal's BLE protocol) — https://github.com/alkersan/om-research
  - Confirms the gimbal "follows the same protocol used in other products, like Mavic" — corroborating that DUML findings transfer across the DJI product line, not just within the Osmo Action family.
  - Includes `duml.py` (packet parser), `gimbal.py` (connection/MTU-discovery/notification driver), and a Web Bluetooth API proof-of-concept.

### 3.3 Practical takeaway for the pairing flow

DJI pairing over BLE on Osmo Pocket 3 involves an explicit PIN exchange (`0x07/0x45` set PIN, `0x07/0x46` approved) — a different model than GoPro's open/no-PIN BLE pairing or Insta360's name-based remote discovery. If you ever extend the CarPlay widget to DJI, budget for that extra handshake step specifically.

---

## 4. Cross-manufacturer comparison (for the pairing flow port)

| | Insta360 | GoPro | DJI |
|---|---|---|---|
| Official BLE spec published? | No (SDK abstracts it; binary frameworks only) | Yes, full open spec + UUIDs | Partial (R SDK covers Action/360 line only) |
| Pairing mechanism | Advertises/discovers as itself; SDK handles handshake | Standard BLE pairing, no PIN | PIN-based pairing handshake (cmd 0x07) |
| Official Swift/CoreBluetooth demo? | No (Obj-C/Swift SDK, no raw CoreBluetooth sample) | **Yes** — `demos/swift/EnableWiFiDemo` | No (ESP-IDF/C demo only) |
| Keep-alive required? | Yes — heartbeat every 0.5s, 30s timeout | Not documented as required | Not confirmed in community docs |
| BLE bandwidth ceiling | Control only; no preview/streaming/large files | Control + triggers Wi-Fi handoff for streaming | Control + telemetry push (~20Hz) |
