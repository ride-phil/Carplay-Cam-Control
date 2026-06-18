# Carplay-Cam-Control (CamControl)

iOS app + Home Screen/CarPlay widget for controlling an action camera over Bluetooth LE — built for motorcycle use (CarPlay-connected dash, e.g. Chigee units). Pair a camera in the app, then start/stop recording and take photos from the app or the widget without unlocking your phone.

## Status

- **App**: builds, signs, installs via TestFlight. Pairing, Start/Stop recording, and photo capture confirmed working reliably on an Insta360 X3 and an Insta360 X4, in any camera mode — both expose the same BLE service/protocol, handled by one `Insta360Driver`.
- **Multi-camera**: the app can pair and control more than one camera at once (per-camera Record/Stop/Photo, plus a "Record All / Stop All / Photo — All Cameras" batch control that runs concurrently across all paired cameras).
- **Reconnect after power cycle**: the app has no live connectivity awareness — "Ready" only means "in the paired list," not "currently reachable." Power-cycling a camera (at least the Ace Pro, observed) can give it a new CoreBluetooth peripheral identity if the camera doesn't support BLE bonding, so the old stored identity stops resolving and commands fail. Each paired camera row has a "Reconnect" button (re-scans for a peripheral with the same advertised name and rebinds it) so this doesn't require a full unpair/re-pair. Background/always-on awareness (detecting power-off live, auto-reconnecting without user action) is a separate, much larger effort — see Known open items.
- **Widgets**: two widget kinds, both untested on a real device so far. `CamControlWidget` is per-camera and configurable — each placed instance is set (via "Edit Widget") to control one specific paired camera, via a `CameraEntity`/`SelectCameraIntent` (`AppIntentConfiguration`); add multiple instances to control multiple cameras. `RecordAllWidget` is a second, non-configurable widget that fans out Record/Stop/Photo to every paired camera concurrently.
- **CarPlay**: not yet verified. The widget already meets Apple's requirement for automatic CarPlay Dashboard inclusion (`.supportedFamilies([.systemSmall])`), so it *should* show up under CarPlay's widget gallery once added to the iPhone Home Screen — untested on an actual unit.
- **Photo capture**: reliable on the X3/X4 in any mode. On the **Insta360 Ace Pro specifically**, `0x03` does nothing while the camera is in Video mode — confirmed via real device testing — but works once manually switched to Photo mode first. The app shows an Ace Pro–specific in-app hint about this. Investigated via `Insta360Driver`'s notify-response logging (`os.log` category `Insta360BLE`): the BE82 notify packet is byte-for-byte identical across both camera models and both outcomes (success/fail) in every capture taken — it acks "command received," not the result — so there's no software-detectable signal to work around this from inside our own driver. Fixing `0x03` to work on the Ace Pro without a manual mode switch would require a genuine BLE packet capture of the official Insta360 app actually switching modes; not something fixable by guessing at undocumented opcodes.

## Architecture

```
CamControl/                Main app — SwiftUI, BLE pairing UI, camera controls
  Services/PairingManager.swift   Owns CBCentralManager, drives pairing + recording
  Views/PairingView.swift         Pair/scan UI + Record/Stop/Photo buttons

CamControlWidget/          WidgetKit extension (Home Screen / CarPlay widget)
  CamControlWidget.swift          Per-camera configurable widget UI + AppIntentTimelineProvider
  RecordAllWidget.swift           Non-configurable widget controlling every paired camera at once
  Intents/                        AppIntents for Record/Stop/Photo (per-camera and *All variants, run widget-side)

Shared/                    Code shared between app and widget targets
  PairedCamera.swift              One paired camera — stable app-level `id` (recording state, widget config) vs. volatile `peripheralID` (current CoreBluetooth identity, used to connect)
  CameraEntity.swift               AppEntity wrapper around PairedCamera, used by widget configuration UI
  SharedState.swift               App Group-backed UserDefaults — list of paired cameras + per-camera recording state
  CameraDriver*.swift             Per-protocol-family BLE command driver (Insta360 implemented and covers multiple Insta360 models; GoPro/DJI scaffolded, unverified)
```

### Data flow

- App and widget run in **separate processes**. They share pairing/recording state via an **App Group** (`group.io.camcontrol.app`), backed by `UserDefaults(suiteName:)`.
- Widget timelines use `policy: .never` — they do **not** auto-refresh. Both the app (`PairingManager`) and the widget's own `AppIntents` must explicitly call `WidgetCenter.shared.reloadAllTimelines()` after any state change, or the widget will show stale data indefinitely.

## ⚠️ Critical gotcha: XcodeGen `info:` / `entitlements:` keys

**Do not use `info: path:` or `entitlements: path:` in `project.yml`.** These are XcodeGen *generation* instructions — they tell XcodeGen to write a minimal file at that path, silently **overwriting** any real `Info.plist`/`.entitlements` file already there, on every single `xcodegen generate` run.

This caused two real, hard-to-diagnose bugs during initial setup:
1. Custom `Info.plist` keys (orientations, launch screen, Bluetooth usage strings, widget `NSExtension` block) were silently dropped on every build, despite the source files being correct.
2. The App Group entitlement (`com.apple.security.application-groups`) was silently dropped from every build, even after confirming the App Group was correctly registered and assigned to both App IDs in the Apple Developer portal, and even after regenerating provisioning profiles. The widget could never read the app's pairing/recording state as a result.

**The fix** (already applied, do not revert): reference existing files via plain build settings instead —
```yaml
settings:
  base:
    INFOPLIST_FILE: CamControl/Info.plist
    CODE_SIGN_ENTITLEMENTS: CamControl/CamControl.entitlements
```
and set `GENERATE_INFOPLIST_FILE: "NO"` once at the project level. Verify by checking a CI build's "Build and archive" log for the `ProcessProductPackaging` / `Entitlements:` dump — it should show your actual custom keys, not just the bare minimum Apple auto-injects.

## CI/CD (Codemagic)

`codemagic.yaml` defines two workflows:

- **`ios-simulator-build`** — no code signing required, builds for the simulator. Use this as a fast compile sanity check before chasing signing issues.
- **`ios-testflight`** — full signed archive, uploads to TestFlight automatically on every push to `main`.

Build numbers use Codemagic's own `$BUILD_NUMBER` (auto-incrementing per workflow) via `agvtool`, not Apple's `get-latest-testflight-build-number` API lookup — that lookup was unreliable and silently fell back to `0`, causing duplicate-build-number rejections.

### Signing setup (Apple Developer Portal)

- Team ID: `8DBK4N5HFL`
- Bundle IDs: `io.camcontrol.app` (app), `io.camcontrol.app.widget` (widget)
- App Group: `group.io.camcontrol.app`, enabled as a capability on **both** App IDs
- Distribution certificate + provisioning profiles generated through Codemagic's Code Signing Identities UI, linked to an App Store Connect API key (Developer Portal integration)
- If you ever change entitlement capabilities (add a new App Group, add a new capability, etc.), you must **regenerate the provisioning profiles** afterward and re-fetch them into Codemagic — profiles can go stale relative to the App ID's current capabilities.

### App Store Connect publishing

Requires an `app_store_connect` environment variable group (set in Codemagic app settings, not global — personal accounts don't support global env vars) with:
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_KEY_IDENTIFIER`
- `APP_STORE_CONNECT_PRIVATE_KEY` (the `.p8` contents)

## Known open items

- [ ] Find the correct Insta360 BLE photo-capture opcode/sequence so the Ace Pro doesn't require manually switching to Photo mode first — confirmed not solvable via the existing BLE notify channel (see Photo capture status above); needs a real packet capture of the official Insta360 app switching camera modes
- [ ] Verify both widgets actually appear in CarPlay's widget gallery on a real unit
- [ ] Verify the per-camera widget's configuration UI (camera picker via `CameraEntity`/`SelectCameraIntent`) actually works as expected on a real device — untested since being built
- [ ] GoPro and DJI camera drivers are scaffolded but unverified against real hardware
- [ ] Placeholder app icon (`CamControl/Assets.xcassets/AppIcon.appiconset/icon-1024.png`) needs real branding before any public release
- [ ] Background/always-on connectivity awareness (detect camera power-off/on live, not just via manual "Reconnect") — main-app-only (widget extensions can't run persistently), requires `bluetooth-central` background mode + switching from connect-per-command to persistent connections, only works while the app process is resident, and may still need a manual re-scan if the camera doesn't preserve BLE identity across power cycles
