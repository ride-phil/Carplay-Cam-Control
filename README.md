# Carplay-Cam-Control (CamControl)

iOS app + Home Screen/CarPlay widget for controlling an action camera over Bluetooth LE — built for motorcycle use (CarPlay-connected dash, e.g. Chigee units). Pair a camera in the app, then start/stop recording and take photos from the app or the widget without unlocking your phone.

## Status

- **App**: builds, signs, installs via TestFlight. Pairing, Start/Stop recording, and photo capture confirmed working reliably on an Insta360 X3 and an Insta360 X4, in any camera mode — both expose the same BLE service/protocol, handled by one `Insta360Driver`.
- **Multi-camera**: the app can pair and control more than one camera at once (per-camera Record/Stop/Photo, plus a "Record All / Stop All / Photo — All Cameras" batch control that runs concurrently across all paired cameras).
- **Reconnect after power cycle**: power-cycling a camera (at least the Ace Pro, observed) can give it a new CoreBluetooth peripheral identity if the camera doesn't support BLE bonding, so the old stored identity stops resolving and commands fail. Each paired camera row has a "Reconnect" button (re-scans for a peripheral with the same advertised name and rebinds it) so this doesn't require a full unpair/re-pair. There's still no *live* connectivity awareness — a camera only gets flagged "Unreachable" (app and both widgets) after a command or reconnect attempt actually fails with `peripheralNotFound`; it doesn't detect power-off proactively. Background/always-on awareness (detecting power-off live, auto-reconnecting without user action) is a separate, much larger effort — see Known open items.
- **Scan timeouts**: general "Scan" (pairing new cameras) auto-stops after 30s if left running; "Reconnect" auto-stops after 10s if the target camera isn't found. Neither scan runs indefinitely draining battery if you walk away.
- **App ↔ widget state sync**: the widget extension is a separate process — when a widget intent changes `SharedState` (e.g. starting a recording from a widget), `WidgetCenter.shared.reloadAllTimelines()` refreshes *other widgets* but does nothing for an already-running app, since `UserDefaults`' own change notification doesn't reliably cross the App Group process boundary. Fixed via `CrossProcessNotifier` (Darwin notification center, the standard mechanism for this) — `SharedState`'s setters post a notification on every write, and `PairingManager` observes it and reloads its in-memory state. Confirmed bug before this fix: starting a recording from the CarPlay widget showed no change at all in the open app. Not yet re-tested after the fix.
- **Cross-widget refresh reliability**: confirmed bug — stopping a camera via one widget left `RecordAllWidget`'s count stuck (e.g. "1/3 recording") until directly interacting with `RecordAllWidget` itself forced a recompute; starting had worked fine moments earlier. Two contributing causes found, not one: (1) a widget's *own* button press gets an immediate, non-throttled refresh, but `reloadAllTimelines()` telling *other* widgets to refresh goes through iOS's normal rate-limited background refresh budget — addressed with `UserDefaults.synchronize()` on every `SharedState` write plus a 20s periodic self-refresh fallback on both widgets' timeline policies (`.never` → `.after(20s)`), so they self-correct on their own cadence even if a pushed reload is throttled. (2) The real dominant cause, found via a retest showing GoPro updating fast/reliably while Insta360 cameras updated slowly/unreliably specifically when more than one was paired: `Insta360Driver` (and `GoProDriver`) used a `static` BLE dispatch queue shared across *every instance of that camera type*. Running "Record All" concurrently across two Insta360 cameras serialized their CoreBluetooth callbacks through one shared queue, delaying each camera's actual command completion (and therefore its `SharedState` write) relative to a camera type with no same-type contention. Fixed by making `bleQueue` a per-instance property in both drivers instead of `static`. Not yet re-tested on hardware.
- **UI**: forced always-dark (`UIUserInterfaceStyle: Dark` in Info.plist — covers system-presented UI too, not just SwiftUI views), matching the widgets' existing black backgrounds. Custom `AccentColor` asset (cyan-blue) and `LaunchBackground` asset (avoids a white flash on launch). Three-tab `TabView` (`RootView`): Cameras (paired list + controls), Connect (scan/pair new cameras), About (version, supported cameras, known limitations) — `PairingManager` is owned once by `RootView` and shared across tabs via `@ObservedObject`.
- **Widgets**: confirmed working on a real CarPlay Dashboard with 3 paired cameras — 3 `CamControlWidget` instances (one per camera) plus 1 `RecordAllWidget` simultaneously. `CamControlWidget` is per-camera and configurable — each placed instance is set (via "Edit Widget") to control one specific paired camera, via a `CameraEntity`/`SelectCameraIntent` (`AppIntentConfiguration`); add multiple instances to control multiple cameras. `RecordAllWidget` is a second, non-configurable widget that fans out Record/Stop/Photo to every paired camera concurrently. Both widgets' Record/Stop/Photo buttons use a shared `WidgetActionButton` (hand-drawn colored background + full-width frame) instead of system button styles, which render inconsistently inside WidgetKit — gives a real visible button look and a maximized tap target. Not yet visually verified on a real device.
- **CarPlay**: confirmed — both widget kinds appear in CarPlay Dashboard's widget gallery and work simultaneously. Two gallery quirks worth knowing: (1) the number of `CamControlWidget` instances you can add appears tied to your paired camera count (e.g. 3 cameras → 3 addable instances) — this is expected `AppIntentConfiguration`/`EntityQuery` behavior, not a bug; pairing more cameras opens more slots. (2) The gallery's default/recommended browse view doesn't reliably list every available widget — if one seems "unavailable," **use the gallery's Search** instead of just scrolling the default view; this resolved a "missing widget" false alarm during testing.
- **Photo capture (Insta360)**: reliable on the X3/X4 in any mode. On the **Insta360 Ace Pro specifically**, `0x03` does nothing while the camera is in Video mode — confirmed via real device testing — but works once manually switched to Photo mode first. The app shows an Ace Pro–specific in-app hint about this. Investigated via `Insta360Driver`'s notify-response logging (`os.log` category `Insta360BLE`): the BE82 notify packet is byte-for-byte identical across both camera models and both outcomes (success/fail) in every capture taken — it acks "command received," not the result — so there's no software-detectable signal to work around this from inside our own driver. Fixing `0x03` to work on the Ace Pro without a manual mode switch would require a genuine BLE packet capture of the official Insta360 app actually switching modes; not something fixable by guessing at undocumented opcodes.
- **GoPro**: tested on a Hero 7 Silver — Record/Stop confirmed. Photo capture had the *same class of bug* as the Ace Pro (Shutter is a dumb on/off toggle whose effect depends on the camera's current preset group), except this one was a real, fixable bug in our own driver, not a hardware limitation — `takePhoto()` was sending the exact same bytes as `startRecording()`. Unlike Insta360, GoPro publishes an official, public BLE protocol (`gopro/OpenGoPro` on GitHub), so the fix is verified against their actual source rather than guessed: `GoProDriver` now sends `LOAD_PRESET_GROUP` (cmd `0x3E`, Photo group ID `1001`/Video group ID `1000`) before the shutter toggle, for both `takePhoto()` and `startRecording()`. **Not yet re-tested on hardware after this fix.** Pairing a GoPro for the first time requires enabling Connections → Connect Device → GoPro App on the camera itself first — this is GoPro's standard pairing flow (same as their own Quik app), not a bug; the Connect tab has a hint about it.

## Architecture

```
CamControl/                Main app — SwiftUI, BLE pairing UI, camera controls
  Services/PairingManager.swift   Owns CBCentralManager, drives pairing + recording
  Views/RootView.swift            TabView root (Cameras / Connect / About), owns the single shared PairingManager
  Views/CamerasView.swift         Paired camera list + Record/Stop/Photo (per-camera and All Cameras)
  Views/ConnectView.swift         Scan/pair UI for adding new cameras
  Views/AboutView.swift           Static app info — version, supported cameras, known limitations

CamControlWidget/          WidgetKit extension (Home Screen / CarPlay widget)
  CamControlWidget.swift          Per-camera configurable widget UI + AppIntentTimelineProvider
  RecordAllWidget.swift           Non-configurable widget controlling every paired camera at once
  Intents/                        AppIntents for Record/Stop/Photo (per-camera and *All variants, run widget-side)

Shared/                    Code shared between app and widget targets
  PairedCamera.swift              One paired camera — stable app-level `id` (recording state, widget config) vs. volatile `peripheralID` (current CoreBluetooth identity, used to connect)
  CameraEntity.swift               AppEntity wrapper around PairedCamera, used by widget configuration UI
  SharedState.swift               App Group-backed UserDefaults — list of paired cameras + per-camera recording/unreachable state
  CameraDriver*.swift             Per-protocol-family BLE command driver (Insta360 covers multiple Insta360 models; GoPro confirmed on Hero 7 Silver, Record/Stop working, Photo fix pending re-test; DJI scaffolded, unverified — protocol undocumented)
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
- [ ] Verify the GoPro Photo-capture fix (`LOAD_PRESET_GROUP` before shutter) on real hardware — implemented and verified against GoPro's official BLE source, but not yet re-tested on the Hero 7 Silver that originally surfaced the bug
- [ ] DJI camera driver is scaffolded but unverified against real hardware (BLE protocol undocumented — see `Shared/Drivers/DJIDriver.swift`)
- [ ] Placeholder app icon (`CamControl/Assets.xcassets/AppIcon.appiconset/icon-1024.png`) needs real branding before any public release
- [ ] Background/always-on connectivity awareness (detect camera power-off/on live, not just via manual "Reconnect") — main-app-only (widget extensions can't run persistently), requires `bluetooth-central` background mode + switching from connect-per-command to persistent connections, only works while the app process is resident, and may still need a manual re-scan if the camera doesn't preserve BLE identity across power cycles
- [ ] Re-test cross-widget refresh (start/stop via one widget, check the other; Record All with 2+ Insta360 cameras paired) on hardware after the per-instance `bleQueue` fix + `UserDefaults.synchronize()` + 20s periodic-refresh fix — confirm Insta360 update speed/reliability now matches GoPro, and tune the 20s interval against real-world WidgetKit refresh budget behavior (faster correction vs. budget exhaustion on long rides)
