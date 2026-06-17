# Carplay-Cam-Control (AceProRecorder)

iOS app + Home Screen/CarPlay widget for controlling an action camera over Bluetooth LE — built for motorcycle use (CarPlay-connected dash, e.g. Chigee units). Pair a camera in the app, then start/stop recording and take photos from the app or the widget without unlocking your phone.

## Status

- **App**: builds, signs, installs via TestFlight. Pairing, Start/Stop recording confirmed working on an Insta360 Ace Pro.
- **Widget**: confirmed working — shows live paired/recording state, Record/Stop/Photo buttons trigger real camera commands via `AppIntents`.
- **CarPlay**: not yet verified. The widget already meets Apple's requirement for automatic CarPlay Dashboard inclusion (`.supportedFamilies([.systemSmall])`), so it *should* show up under CarPlay's widget gallery once added to the iPhone Home Screen — untested on an actual unit.
- **Photo capture**: works in the camera's photo mode. Does **not** work while the camera is recording video — the BLE opcode used (`0x03`) is likely a generic "shutter" trigger that's mode-dependent, not a dedicated "snapshot" command. Needs a real packet capture from the official Insta360 app to find the correct command; not something fixable by guessing.

## Architecture

```
AceProRecorder/            Main app — SwiftUI, BLE pairing UI, camera controls
  Services/PairingManager.swift   Owns CBCentralManager, drives pairing + recording
  Views/PairingView.swift         Pair/scan UI + Record/Stop/Photo buttons

AceProRecorderWidget/      WidgetKit extension (Home Screen / CarPlay widget)
  AceProRecorderWidget.swift      Widget UI + TimelineProvider
  Intents/                        AppIntents for Record/Stop/Photo (run widget-side)

Shared/                    Code shared between app and widget targets
  SharedState.swift               App Group-backed UserDefaults (pairing/recording state)
  CameraDriver*.swift             Per-camera-brand BLE command protocol (Insta360 implemented; GoPro/DJI scaffolded, unverified)
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
    INFOPLIST_FILE: AceProRecorder/Info.plist
    CODE_SIGN_ENTITLEMENTS: AceProRecorder/AceProRecorder.entitlements
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

- [ ] Find correct BLE opcode for "take photo while recording video" (Insta360 Ace Pro)
- [ ] Verify widget actually appears in CarPlay's widget gallery on a real unit
- [ ] GoPro and DJI camera drivers are scaffolded but unverified against real hardware
- [ ] Placeholder app icon (`AceProRecorder/Assets.xcassets/AppIcon.appiconset/icon-1024.png`) needs real branding before any public release
