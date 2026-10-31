# HotShare: Implementation Guide

**Audience:** an AI coding agent evolving the existing HotShare Flutter project into the product described in `HOTSHARE_DESIGN_GUIDE.md`.
**Rule of precedence:** this file decides technical choices (architecture, state, data, protocol, packages, phases). The design guide decides look, feel and interaction. If they conflict on UI behaviour, follow the design guide and note the conflict.

---

## 0. Working agreement

1. Work **one phase at a time** (section 12). Finish a phase's acceptance criteria before starting the next.
2. After **every task**: `flutter analyze` must be clean, the app must still build on both targets, then **commit** with a clear message. Never leave the tree broken between commits.
3. **Test on real devices**: a Windows PC joined to the Android phone's hotspot. Emulators cannot reproduce the network.
4. Never change the wire protocol without bumping `protocolVersion` and keeping a compatibility note.
5. Keep **networking and transfer logic free of Flutter imports** (pure Dart) so it can run in a background isolate and be unit tested.
6. Run `flutter pub add <pkg>` to get current versions; do not hand-edit version numbers from memory. If a version conflict appears, read the solver message and fix it, do not downgrade blindly.
7. Prefer small, reviewable files. No file over ~400 lines without a reason.
8. Add a short note to `docs/DECISIONS.md` for every non-obvious choice.

### 0.1 Facts about this project (verified)

- Path: `C:\Projects\hotshare`, Android application id `com.example.hotshare`. Flutter 3.47.x stable, Dart 3.13.
- Dev machine: Windows 11, Git Bash terminal, VS Code-based IDE. Test phone: Android 16 (API 36), a Xiaomi-family device (MIUI/HyperOS-style log tags), connected over USB for debugging.
- Topology today: **phone = WebSocket server on port 8080**, **PC = client** that connects to the hotspot gateway. The PC finds the gateway with `route print -4` and a regex on the default route.
- Everything currently lives in one file, `lib/main.dart` (~580 lines): connection, protocol, transfer, and UI. Protocol v1: JSON text frames (`text, offer, accept, reject, progress, done, result, cancel`) and raw binary frames for data, with a 4 MB in-flight window and 1 MB progress acks. It works and transfers ~150 MB in 10 to 15 s.

### 0.2 Known gotchas (do not rediscover these)

| Problem seen | Cause | Decision |
| --- | --- | --- |
| `pub get` conflict | `file_picker >= 12` needs `cross_file ^0.3.5+4`, `desktop_drop >= 0.9` needs `cross_file ^0.4.0` | Keep `desktop_drop: ">=0.5.0 <0.9.0"`. Revisit when either package updates. |
| `FilePicker.platform.pickFiles` not found | file_picker v12+ API: static `FilePicker.pickFiles()` returns `List<PlatformFile>` (empty if cancelled); `pickFile()` for one file; `FilePickerResult` removed | Use the v12+ API. |
| Windows build: "requires symlink support" | Developer Mode off | Developer Mode must be on (already on). |
| Android build: NDK not found | Auto-install via new Android CLI failed | NDK `28.2.13676358` installed manually in SDK Manager. |
| `flutter pub add "pkg:<1.0"` fails in Git Bash / cmd | `<` treated as a redirect | Edit `pubspec.yaml` directly for range constraints. |
| Connection drops when the user leaves the app | Android suspends/freezes background apps; no foreground service | Phase 2 |
| Logs flooded with Android system lines | `flutter run` mirrors logcat | Run from the IDE debugger (Debug Console) or filter with `grep -v`. |
| Received files not visible in Android Files app | Saved to app-specific external dir | Phase 4 (MediaStore) |

---

## 1. Goals for this evolution

1. **Faster transfers** (find and remove bottlenecks; measure against the Wi-Fi ceiling).
2. **Persistent connection**: survives leaving the app and screen lock on Android; auto-reconnects on Windows.
3. **One-time pairing** with cryptographic device identity; no PIN per session.
4. **Share history** (database), **configurable storage**, settings.
5. **Share integration**: Android share sheet, Windows Explorer integration, floating bubble / Drop Dock.
6. **Ember Glass UI** with AirDrop-style interaction (design guide).
7. Clean state management so all of the above stays maintainable.

---

## 2. Target architecture

Layered, dependencies point **downward** only.

```
lib/
  main.dart                      // bootstrap only: init services, runApp(ProviderScope)
  app/
    app.dart                     // MaterialApp, theme, routing
    shell_mobile.dart            // pill nav
    shell_desktop.dart           // rail + custom title bar
  core/                          // pure Dart, no Flutter imports
    protocol/
      messages.dart              // sealed message classes + (de)serialisation
      frame.dart                 // binary frame header encode/decode
      protocol_version.dart
    net/
      peer_connection.dart       // one authenticated socket to one peer
      connection_manager.dart    // lifecycle: discover, connect, reconnect, state machine
      gateway_finder.dart        // Windows: route print parsing
      discovery.dart             // interface + hotspot-gateway impl (+ mDNS later)
    transfer/
      transfer_engine.dart       // queue, send/receive pipelines, flow control
      sender.dart
      receiver.dart
      checksum.dart
    security/
      identity.dart              // device keypair
      pairing.dart               // pairing state machine
      session_crypto.dart        // key agreement + AEAD framing (phase 7)
    engine/
      hotshare_engine.dart       // facade: commands in, events out
      engine_api.dart            // Command / Event types (serialisable for isolates)
  data/
    db/                          // Drift database, tables, DAOs
    settings_repository.dart     // shared_preferences wrapper
    secure_store.dart            // keys (flutter_secure_storage)
    storage_resolver.dart        // where to save a file (platform specific)
    platform/                    // method-channel wrappers (MediaStore, share intents, overlay)
  state/                         // Riverpod providers (the only place UI meets core)
  ui/
    design_system/               // glass components (design guide section 8)
    features/
      nearby/ history/ devices/ settings/ onboarding/ share_target/
  platform_integration/          // tray, window effects, SendTo, dock, overlay, notifications
android/app/src/main/kotlin/...  // share intents, MediaStore writer, foreground service glue
```

**Key architectural decision: the engine is a self-contained object with a command/event API.**

- `HotShareEngine` exposes `Stream<EngineEvent> events` and `void send(EngineCommand cmd)`. Commands and events are plain serialisable data (maps), no sockets or Flutter types.
- **Windows:** the engine runs **in the UI isolate** (the app lives in the tray, so it persists).
- **Android:** the engine must run **inside the foreground-service isolate** so it survives the activity being destroyed. The UI talks to it through ports.
- Therefore the UI depends on an `EngineClient` interface with two implementations: `InProcessEngineClient` (Windows) and `ServiceIsolateEngineClient` (Android). Everything above the interface is identical on both platforms.
- Do this in two steps (Phase 2a, 2b) so a working app exists at every point.

---

## 3. State management: Riverpod

**Package:** `flutter_riverpod`. Use the plain `Notifier` / `AsyncNotifier` / `StreamProvider` APIs. **Do not use code generation** (`riverpod_generator`, `freezed`) in the first iteration; write immutable classes with `copyWith` by hand (or `equatable`). Keeps the toolchain simple.

### 3.1 Rules

1. **UI never touches sockets, files or the database.** Widgets watch providers and call methods on notifiers.
2. Core services have **no** Riverpod or Flutter imports. Providers wrap them.
3. State classes are **immutable**.
4. High-frequency data (transfer progress) is held **in memory** and pushed to the UI at <= 10 Hz; it is **not** written to the database on every tick (write on state changes: queued, started, finished, failed).
5. Side effects (toasts, haptics, navigation) go through `ref.listen` in a top-level widget or a dedicated `EffectsListener`, never inside `build`.
6. Use `select` to rebuild only what changed (e.g. a single bubble's progress).
7. Provider overrides in tests replace the engine with a fake.

### 3.2 Provider map

| Provider | Type | Source of truth | Consumers |
| --- | --- | --- | --- |
| `engineClientProvider` | `Provider<EngineClient>` | Platform-specific client | Everything below |
| `engineEventsProvider` | `StreamProvider<EngineEvent>` | Engine event stream | Notifiers below |
| `settingsProvider` | `NotifierProvider<SettingsNotifier, AppSettings>` | `shared_preferences` | Settings screen, engine config |
| `identityProvider` | `FutureProvider<DeviceIdentity>` | Secure store | Pairing, handshake |
| `pairedDevicesProvider` | `StreamProvider<List<PairedDevice>>` | Drift `devices` table | Devices screen, nearby |
| `peerStatesProvider` | `NotifierProvider<..., Map<DeviceId, PeerState>>` | Engine `PeerStateChanged` events | Nearby, tray |
| `nearbyBubblesProvider` | `Provider<List<BubbleVm>>` | Combines paired devices + peer states + active transfers | Radar |
| `activeTransfersProvider` | `NotifierProvider<..., Map<TransferId, TransferProgress>>` | Engine progress events (throttled) | Bubbles, toast, notification |
| `historyProvider` | `StreamProvider<List<TransferRecord>>` (with filter family) | Drift `transfers` table | History screen |
| `pairingControllerProvider` | `NotifierProvider<..., PairingUiState>` | Engine pairing events | Pairing sheets |
| `storageResolverProvider` | `Provider<StorageResolver>` | Settings + platform | Engine (via config), settings UI |
| `incomingShareProvider` | `StreamProvider<SharePayload>` | Android intent / Windows args | Share-target UI |
| `themeControllerProvider` | `Notifier` | Settings | `MaterialApp` |
| `connectivityHintsProvider` | `Provider` | Hotspot/gateway info | Pairing, diagnostics |

### 3.3 Example (shape, not final code)

```dart
class ActiveTransfersNotifier extends Notifier<Map<String, TransferProgress>> {
  @override
  Map<String, TransferProgress> build() {
    final sub = ref.watch(engineClientProvider).events
        .where((e) => e is TransferProgressEvent)
        .cast<TransferProgressEvent>()
        .listen(_onProgress);
    ref.onDispose(sub.cancel);
    return const {};
  }
  void _onProgress(TransferProgressEvent e) =>
      state = {...state, e.id: TransferProgress.from(e)};
}
```

The engine itself already throttles progress events to ~10 Hz so the notifier stays simple.

---

## 4. Data layer

### 4.1 Storage technologies

| Data | Technology | Why |
| --- | --- | --- |
| Transfer history, paired devices, offline queue | **Drift** (`drift` + `drift_flutter` or `sqlite3_flutter_libs`) | Typed SQL, reactive streams, works on Android and Windows |
| Settings | `shared_preferences` | Small key/values |
| Private keys | `flutter_secure_storage` | OS-backed secure storage (verify Windows backend behaviour; fall back to an encrypted file with a DPAPI-protected key if needed) |
| Thumbnails | App cache directory, `thumbs/<transferId>.jpg` | Disposable |

### 4.2 Schema (Drift)

**`devices`**

| Column | Type | Notes |
| --- | --- | --- |
| `id` | text PK | Device id = base32 of first 16 bytes of SHA-256(public signing key) |
| `name` | text | User-editable |
| `platform` | text | `android`, `windows`, `macos`, ... |
| `publicKey` | blob | Ed25519 public key |
| `pairedAt` | datetime | |
| `lastSeenAt` | datetime nullable | |
| `lastKnownHost` | text nullable | Last IP, hint only |
| `autoAccept` | bool default true | Per-device |
| `canInitiate` | bool default true | May this device start transfers to us |
| `saveFolderOverride` | text nullable | |
| `revoked` | bool default false | Soft delete on forget |

**`transfers`**

| Column | Type | Notes |
| --- | --- | --- |
| `id` | text PK | UUID |
| `peerId` | text FK -> devices.id | |
| `direction` | text | `in` / `out` |
| `name` | text | Display name |
| `size` | int | Bytes |
| `mime` | text nullable | |
| `kind` | text | `image, video, audio, document, archive, other` |
| `status` | text | `queued, offered, transferring, verifying, done, failed, cancelled, declined` |
| `bytesDone` | int | Updated on state change and every ~1 s at most |
| `localPath` | text nullable | Windows path or Android `content://` URI |
| `thumbPath` | text nullable | |
| `sha256` | text nullable | |
| `startedAt` | datetime | |
| `finishedAt` | datetime nullable | |
| `avgBytesPerSec` | int nullable | |
| `error` | text nullable | Short code + message |
| `batchId` | text nullable | Groups a multi-file share |

Indexes: `transfers(startedAt DESC)`, `transfers(peerId, startedAt DESC)`. Retention job at startup deletes rows older than the setting (and optionally files).

**Offline queue:** represented as `transfers` rows with status `queued` and `localPath` set to the source file; the engine drains them when the peer comes online.

### 4.3 Settings keys (`AppSettings`)

`deviceName`, `autoAcceptTrusted`, `pauseReceiving`, `saveRootWindows`, `androidSaveMode` (`byType`|`downloads`|`customTree`), `androidTreeUri`, `organiseBy` (`none|type|date|device`), `keepPartials`, `historyRetentionDays`, `deleteFilesWithHistory`, `runInBackground`, `startWithWindows`, `minimiseToTray`, `autoReconnect`, `theme`, `reduceTransparency`, `reduceMotion`, `glassStyle`, `haptics`, `sounds`, `floatingBubble`, `dropDock`, `explorerIntegration`, `verifyIntegrity`, `chunkSizeKb` (0 = auto), `onboardingDone`.

---

## 5. Protocol v2

Keep v1 working until v2 is complete (the engine can speak `protocolVersion` 1 or 2 based on the hello).

### 5.1 Transport

- Control and data over **one WebSocket** per peer (v2). A raw TCP data channel is an optimisation (section 8.4), only if measurements demand it.
- **Disable per-message compression** on both ends (see 8.1).
- Application-level heartbeat in addition to WebSocket ping (section 9.3).

### 5.2 Framing

- **Text frames:** JSON control messages `{ "t": "<type>", ... }`.
- **Binary frames:** `[type:1 byte][transferId:4 bytes big-endian][payload...]`. `type 0x01` = file data. The 4-byte numeric transfer id is assigned by the sender in `offer`. This allows multiple concurrent transfers later without changing the format.
- Maximum payload per binary frame = chunk size (default 256 KB, see 8.2).

### 5.3 Messages

| `t` | Direction | Fields | Notes |
| --- | --- | --- | --- |
| `hello` | client -> server | `v`, `deviceId`, `name`, `platform`, `pubKey`, `nonce`, `caps[]` | First message after connect |
| `hello_ack` | server -> client | `v`, `deviceId`, `name`, `pubKey`, `nonce`, `sig`, `known` (bool) | `sig` = server signature over transcript; `known` says whether the server recognises the client |
| `auth` | client -> server | `sig` | Client signature over transcript; connection is now **authenticated** |
| `pair_request` | client -> server | `proof` | Only if not yet paired and server has an open pairing window (section 6) |
| `pair_confirm` | both | `ok` | After the user confirms the verification phrase |
| `offer` | sender -> receiver | `id` (u32), `uuid`, `name`, `size`, `mime`, `batch:{id,index,count}`, `sha256?` | |
| `accept` | receiver -> sender | `id`, `resumeFrom` (default 0) | |
| `reject` | receiver -> sender | `id`, `reason` (`busy, declined, no_space, paused`) | |
| `progress` | receiver -> sender | `id`, `bytes` | Every ~1 MB or 100 ms, whichever is later; doubles as flow-control credit |
| `done` | sender -> receiver | `id`, `sha256?` | After the last chunk |
| `result` | receiver -> sender | `id`, `ok`, `reason?` | After flush, size check and optional hash check |
| `cancel` | either | `id` | |
| `text` | either | `body` | Optional clipboard/text sharing |
| `ping` / `pong` | either | `ts` | Application heartbeat |
| `bye` | either | `reason` | Graceful close |

**Capabilities (`caps`):** `enc1` (encrypted frames), `resume1`, `multi1` (concurrent transfers), `sha256`. Features are used only if both sides advertise them.

### 5.4 Authentication handshake (paired devices)

1. Client sends `hello` with a fresh random `nonceC`.
2. Server replies `hello_ack` with `nonceS` and `sig = Ed25519.sign(skS, "hotshare/v2" | idC | idS | nonceC | nonceS)`. If the client is not a paired device, `known=false`.
3. Client verifies `sig` against the **stored** server public key (not the one in the message, if paired). It sends `auth` with its own signature over the same transcript.
4. Server verifies against the stored client key. On success both mark the connection **authenticated** and may exchange transfer messages. Any transfer message before this is a protocol error and closes the socket.
5. (Phase 7) The same messages carry ephemeral X25519 public keys, included in the signed transcript, to derive session keys.

Unknown devices can only send `pair_request`, and only while the server has an open pairing window.

---

## 6. Pairing and trust

### 6.1 Identity

- On first run generate an **Ed25519** signing key pair (package `cryptography`; add `cryptography_flutter` for native acceleration). Store the private key in secure storage. `deviceId` as defined in 4.2.
- A device's **name** is advertised in `hello` but is *not* trusted for identity; only the public key is.

### 6.2 One-time pairing flow (matches design guide 5.4)

Because the phone is the listening side:

1. **Phone**: user taps *Pair new device*. Engine opens a **pairing window** for 60 s: generates a random 6-digit `code` and a 16-byte `pairSecret`, displays code and QR (`hotshare://pair?v=2&id=...&pk=...&host=...&port=8080&s=<secret>`).
2. **PC**: user enters the code (host auto-detected from the gateway) or scans the QR (needs a camera; mainly for phone-to-phone). The PC connects, sends `hello`, receives `hello_ack` with `known=false`, then sends `pair_request { proof = HMAC-SHA256(key = code, data = nonceC | nonceS | pubKeyC) }`.
3. The phone verifies the proof in constant time. **Max 3 attempts per window; window closes on success or on the third failure.** Single use.
4. Both sides compute a **verification phrase** (`SAS`): `HMAC-SHA256(data = sort(pubKeyC, pubKeyS) | nonceC | nonceS)` mapped to 4 words from a 256-word list (or 4 emoji). Both UIs show it; the user confirms it matches. This defeats a man-in-the-middle on the local network. If the user rejects, nothing is stored.
5. On `pair_confirm` from both, each side stores the other's public key and name in `devices`. Pairing is done; from now on the normal authenticated handshake (5.4) is used and **no code is ever needed again**.

Design note: the code gates who may *start* pairing (stops random hotspot guests); the verification phrase proves identity. Do not skip the verification step.

### 6.3 Trust policy

- Only **paired, non-revoked** devices are ever allowed past authentication.
- `autoAccept` per device decides whether incoming `offer`s need user approval.
- *Forget device* sets `revoked`, closes the connection immediately, and removes the key. Re-pairing is required.
- Log every pairing and revocation in a local audit list (shown in Devices > device > Activity).

---

## 7. Connection manager and state machine

One `PeerConnection` per paired peer. State machine per peer:

```
idle -> searching -> connecting -> authenticating -> connected
  ^         |            |              |               |
  |         v            v              v               v
  +---- backoff <--- failed <------ failed <---- degraded/lost
```

- **Windows (client side):** for each paired device, loop: find candidate host(s) (gateway, then `lastKnownHost`, later mDNS) -> connect -> authenticate. On failure, back off 1 s, 2 s, 3 s, then **stay at 3 s** (hotspots come and go; recovery should feel instant). Also re-run discovery immediately when the OS reports a network change (poll `NetworkInterface.list` every 2 s, or use `connectivity_plus`).
- **Android (server side):** keep the server socket open while the service runs; accept connections only from authenticated peers; when a peer reconnects, close the old socket.
- **Heartbeat:** application `ping` every 5 s; if no `pong` or any traffic within 15 s, mark `lost` and tear down. (WebSocket `pingInterval` alone is not enough; keep it as well.)
- Expose peer state as engine events: `PeerStateChanged(deviceId, state, host?)`.
- **Android <-> Android later:** both advertise via mDNS (`_hotshare._tcp`, TXT = deviceId); the device with the lexicographically smaller `deviceId` initiates; the other listens. Same code paths.

---

## 8. Transfer engine

### 8.1 Quick wins to apply first (Phase 1)

The user measured ~10 to 15 MB/s. Try these in order, **measuring after each**:

1. **Turn off WebSocket compression.** `dart:io` enables `permessage-deflate` by default (verify in current SDK docs); compressing already-compressed media (mkv, jpg, zip) burns CPU for nothing.
   ```dart
   // server
   final ws = await WebSocketTransformer.upgrade(
     request, compression: CompressionOptions.compressionOff);
   // client
   final ws = await WebSocket.connect(url,
     compression: CompressionOptions.compressionOff);
   ```
2. **Bigger chunks** (256 KB to 1 MB). `file.openRead()` yields 64 KB by default; re-chunk with a small buffering transform, or read with `RandomAccessFile.read(chunkSize)` in a loop.
3. **Bigger window**: 8 to 16 MB in flight (flow control already exists; the 4 MB window may stall the pipe on a high-latency radio).
4. **Stop per-chunk UI work**: no `setState` per chunk; progress events at <= 10 Hz and only by time, not by bytes.
5. **Receiver disk writes**: keep `IOSink` writes non-blocking; do not `await flush()` per chunk.
6. **Hotspot band**: confirm the phone hotspot is on **5 GHz** (phone hotspot settings, AP band). 2.4 GHz alone caps near 10 to 15 MB/s in practice, which may already be the limit the user sees. Measure the raw link (an iperf3 app/phone build + `iperf3.exe`) so the target is "within ~80% of the raw link", not an arbitrary number.
7. If still far below the raw link: **WebSocket frame masking** (client-to-server frames are masked, a per-byte XOR in Dart) and framing overhead may be the cost for PC -> phone. Then consider a **dedicated raw TCP data socket** (section 8.4).

### 8.2 Sender pipeline

1. `offer` (with `batch` info) -> wait for `accept` (timeout 15 s, longer if the receiver needs to prompt: use `offer` `awaitingUser` hint and 60 s).
2. Stream chunks: `[0x01][id][bytes]` with the **credit window**: `inFlight = sent - acked <= window`. `progress` messages advance `acked`.
3. Optionally compute SHA-256 incrementally while reading (package `crypto`, chunked conversion). Send in `done`.
4. Wait for `result` (timeout 30 s + proportional to size for hash verification).
5. Update state; emit events.

### 8.3 Receiver pipeline

1. On `offer`: policy check (paused? busy? free space? trusted + autoAccept?) -> `accept` / `reject` / prompt.
2. Write to a **temporary partial file**:
   - Windows: `<destination>\<name>.hspart` in the final folder (so the final rename is atomic and on the same volume).
   - Android: app cache `incoming/<uuid>.part`.
3. On `done`: flush, close, verify size (+ SHA-256 if present), reply `result`.
4. **Finalise**: Windows: rename to a unique final name (`name (1).ext` on collision). Android: copy into MediaStore (section 10.2), then delete the partial.
5. Insert/update the `transfers` row; emit `TransferCompleted`.
6. On disconnect or cancel: delete the partial unless `keepPartials` (or resume is enabled, 8.5).

**Security details (must implement):** sanitise names (strip any path, replace `<>:"|?*` and control chars, trim trailing dots/spaces, reserved Windows names like `CON`, `NUL`), cap name length (~180), reject `size` larger than free space, never trust sender-supplied paths.

### 8.4 Optional raw TCP data channel

Only if 8.1 measurements justify it. Control stays on the WebSocket. On `accept`, the receiver includes `dataPort` and a one-time `token`; the sender opens a plain `Socket`, sends the token and `transferId`, then streams length-prefixed chunks with the same credit window. Enables `tcpNoDelay`, avoids WebSocket masking. Encrypt with the session AEAD (Phase 7).

### 8.5 Resume (Phase 7)

Receiver keeps `.part` with a sidecar (`.part.json`: transferId uuid, size, bytes, optional rolling hash of the first N MB). On reconnect the sender re-sends `offer` with the same `uuid`; the receiver replies `accept { resumeFrom: bytes }`; sender seeks (`RandomAccessFile.setPosition`). Validate by comparing size and the stored hash of the last verified block before resuming.

### 8.6 Queue and concurrency

- Default: one active transfer per direction; additional items queue (`queued`). With `multi1` allow 2 concurrent.
- **Offline queue:** share/drop while the peer is offline creates `queued` records; the engine auto-sends when the peer reaches `connected`.
- Cancel works in any state from either side.

### 8.7 Integrity

Size check always. SHA-256 when `verifyIntegrity` is on (default). The UI says **Delivered / Verified** only after `result.ok`.

### 8.8 Benchmark mode (Phase 1)

A hidden *Benchmark* screen/command: sender streams N MB of random bytes for 10 s; receiver discards them (no disk). Reports MB/s in each direction. Separates **network** speed from **disk** speed. Keep it in the app permanently under Settings > Advanced.

---

## 9. Persistence and background behaviour

### 9.1 Android: foreground service

Goal: connection and server survive leaving the app, screen off, and (Phase 2b) the app being swiped away.

- Package: `flutter_foreground_task` (verify current API). Runs a `TaskHandler` in a separate isolate.
- Manifest: `FOREGROUND_SERVICE`, `POST_NOTIFICATIONS` (Android 13+ runtime), `WAKE_LOCK`, `CHANGE_WIFI_STATE`, `ACCESS_WIFI_STATE`, `INTERNET`, `ACCESS_NETWORK_STATE`, and the permission for the chosen **foreground service type**.
- **Foreground service type:** Android 14+ requires a declared type. `dataSync` has a runtime cap on Android 15 (a few hours per day), which breaks an always-on server. Prefer **`connectedDevice`** (requires one of the Wi-Fi/network permissions above) and fall back to `specialUse` with a justification. **Verify against current Android docs** before choosing.
- Hold a **partial wake lock** and a **Wi-Fi lock** (`WIFI_MODE_FULL_HIGH_PERF` / low-latency where available) while connected or transferring (`flutter_foreground_task` can acquire both). Release when idle and nothing is connected.
- Persistent notification: "HotShare is ready" with actions **Pause receiving** and **Stop**. During transfers, show progress in the same notification.
- **Battery optimisation:** request `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` via a user-visible explanation (permission_handler or an intent).
- **Xiaomi / MIUI / HyperOS:** the OS kills background apps aggressively. Onboarding must show a guided card: *Settings > Apps > HotShare > Autostart: on; Battery saver: No restrictions; lock the app in the recents screen*. Provide a button that opens the app-info screen. Also remind the user that the **hotspot's own auto-off timer** ("turn off hotspot when no devices connected") can drop the link.
- **Phase 2a:** service keeps the process alive; engine still in the UI isolate. **Phase 2b:** move the engine to the service isolate; UI connects through `ServiceIsolateEngineClient` using the plugin's data ports. The engine's command/event API is the seam that makes this a contained change.
- Persist enough state (paired devices in DB, settings) so the service isolate can start without the UI: open Drift and settings directly inside the isolate.

### 9.2 Windows: tray and autostart

- `window_manager`: `setPreventClose(true)`, hide on close when `minimiseToTray`.
- `tray_manager`: icon and menu (Open, Send file..., status, Pause receiving, Quit). Icon states: no peer online / connected / transferring.
- `launch_at_startup`: toggle in settings; start minimised to tray when launched at login.
- **Single instance** (section 11.2) so a second launch forwards arguments to the running app.
- The engine runs in the UI isolate here; keep the app alive when the window is hidden.

### 9.3 Reconnect behaviour

See section 7. Acceptance: toggling the hotspot or locking the phone for 5 minutes must result in an automatic return to `connected` within ~5 s of the link being available, without user action.

---

## 10. Storage

### 10.1 Windows

- Default root: `<Downloads>\HotShare` (`path_provider.getDownloadsDirectory`).
- Setting `saveRootWindows`: choose with `FilePicker.getDirectoryPath()`. Validate it exists and is writable; on failure fall back to the default and show a toast.
- `organiseBy`: sub-folder by type (`Images`, `Videos`, `Audio`, `Documents`, `Archives`, `Other`), by date (`YYYY-MM`), or by device name.
- Open/Show in folder: `Process.run('explorer.exe', ['/select,', path])`; open file via `open_filex` or `url_launcher` with a file URI.

### 10.2 Android

- Set **`minSdkVersion 29`** so `MediaStore.Downloads` and scoped storage are always available (the user's device is far newer).
- **Default mode `byType`**: images -> `Pictures/HotShare`, video -> `Movies/HotShare`, audio -> `Music/HotShare`, everything else -> `Download/HotShare`. Mode `downloads` puts everything in `Download/HotShare`.
- Write path: receive into app cache `.part`, then a **native Kotlin method** `saveToMediaStore(partPath, displayName, mime, relativePath)` that inserts a `MediaStore` row with `IS_PENDING=1`, copies the bytes using the `ContentResolver` output stream (native copy, fast), clears `IS_PENDING`, returns the `content://` URI. Store that URI in `transfers.localPath`. (Alternative package: `media_store_plus`; evaluate, but a ~60-line Kotlin channel is more controllable.)
- Optimisation (later): stream directly into the MediaStore output stream via a native sink to avoid the second copy and double disk usage on very large files.
- **Custom folder** (`customTree`): Storage Access Framework. Launch `ACTION_OPEN_DOCUMENT_TREE`, call `takePersistableUriPermission`, store the tree URI, write with `DocumentFile`. Treat as an advanced option; MediaStore remains the default.
- Opening a received file: `open_filex` with the content URI/path, or a native `ACTION_VIEW` intent with `FLAG_GRANT_READ_URI_PERMISSION`.
- Free-space check before `accept`: `StatFs` through a small channel call.

### 10.3 StorageResolver

Single interface used by the engine so platform code stays out of it:

```dart
abstract class StorageResolver {
  Future<IncomingTarget> prepare({required String name, required int size, required String kind, required PeerInfo peer});
  Future<SavedFile> finalize(IncomingTarget t);   // rename or MediaStore copy; returns display path/URI
  Future<void> discard(IncomingTarget t);
  Future<int?> freeBytes();
}
```

---

## 11. Share and shortcut integrations

### 11.1 Android share sheet ("Share with")

- `AndroidManifest.xml`: on the main activity (or a dedicated lightweight activity) add intent filters for `ACTION_SEND` and `ACTION_SEND_MULTIPLE`, `mimeType="*/*"`, category `DEFAULT`. Set `launchMode="singleTop"` and handle `onNewIntent`.
- **Handle intents in Kotlin** (more reliable than depending on an aging plugin; if you prefer a plugin, evaluate `share_handler` for maintenance first). For each `EXTRA_STREAM` URI: query `OpenableColumns` for name and size, **copy to `cache/share/<uuid>/<name>`** on a background thread, and send `{name, size, mime, path}` to Dart on an `EventChannel`. Also support `EXTRA_TEXT` (send as text/link).
- Dart: `incomingShareProvider` emits payloads. The `share_target` feature shows the translucent quick-send sheet from the design guide 7.1 and either sends immediately (one device online), asks which device, or queues.
- Clean up cache copies after the transfer completes or fails. Warn if free cache space is lower than the file size.
- Cold start must be fast: show the sheet before the engine is fully connected; the connection continues in the service.
- Later: **Direct Share** shortcuts (`ShortcutManagerCompat` + `share-targets` XML) per paired device; and streaming straight from the `content://` URI via a native channel to avoid the cache copy.

### 11.2 Windows

- **Single instance + arguments:** use a single-instance mechanism (evaluate `windows_single_instance`, or implement a mutex + `WM_COPYDATA`/named pipe in the runner). Command line: `hotshare.exe --send "<path>" ...`. A second process forwards its args to the first and exits. Batch args that arrive within ~500 ms into one share (Explorer launches one process per selected file).
- **Send to menu:** settings toggle creates/removes `%APPDATA%\Microsoft\Windows\SendTo\HotShare.lnk` (create via PowerShell `WScript.Shell` from Dart, pointing at the exe with `--send`).
- **Context menu:** write `HKCU\Software\Classes\*\shell\HotShare` with `MUIVerb` and `Icon`, and `...\command` default value `"<exe>" --send "%1"` (use `reg add` or `win32_registry`). On Windows 11 it appears under "Show more options"; note this in the UI. Remove cleanly when the toggle is turned off.
- **Drop Dock:** a second small window (`window_manager` secondary window approach, or a separate Flutter view/engine; evaluate `desktop_multi_window`) set always-on-top, frameless, transparent, edge-docked; expands on hover/drag. Share the same engine through a lightweight local channel, or host the dock in the **same window** as an overlay mode if multi-window proves unstable. Decide in a spike (Phase 6) and record in `DECISIONS.md`.
- `desktop_drop` handles dropping onto the main window and the dock.

### 11.3 Android floating bubble

- `flutter_overlay_window` (needs `SYSTEM_ALERT_WINDOW`). The overlay is a separate Flutter entry point; it talks to the service/engine through the plugin's messaging. Keep the overlay UI tiny (bubble + mini panel) to limit memory.
- The user enables it in Settings; check the permission and explain it before opening system settings.

### 11.4 Notifications

- Android: `flutter_local_notifications` for completion and the service notification text; progress in the foreground notification.
- Windows: `local_notifier` (or `windows_notification`) for receive toasts with action buttons; taskbar progress via a taskbar-progress package (evaluate `windows_taskbar`).

---

## 12. Phases

Each phase has **goal, tasks, packages, acceptance criteria, how to test**. Do not start a phase until the previous one's acceptance criteria pass.

### Phase 0: Baseline and housekeeping

**Goal:** a safe starting point.
- Initialise git, add a sensible `.gitignore` (Flutter default), commit the working state.
- Add `docs/DECISIONS.md`, set `analysis_options.yaml` (flutter_lints on), fix all analyzer warnings.
- Set Android `minSdkVersion 29`. Confirm `flutter run` works on both targets.
- Split `main.dart` mechanically into files per section 2 **without behaviour changes** (protocol, transfer, UI) as a first step toward the layers.

**Acceptance:** app behaves exactly as before; analyzer clean; commit exists.

### Phase 1: Speed and architecture foundation

**Goal:** faster transfers and a testable core.
- Introduce `HotShareEngine` with command/event API; move socket and transfer code from the widget into `core/` (pure Dart). Add Riverpod; UI becomes a thin consumer. Keep v1 protocol.
- Apply the quick wins in 8.1 one at a time with benchmark numbers recorded in `docs/PERF.md` (before/after).
- Add the Benchmark mode (8.8).
- Unit tests: protocol (de)serialisation, flow-control window, filename sanitiser, unique-file naming.

**Packages:** `flutter_riverpod`, `crypto`.
**Acceptance:** same functionality; benchmark screen reports network MB/s; `docs/PERF.md` shows measured improvement or a documented explanation that the Wi-Fi link is the limit; no `setState` per chunk.
**Test:** 500 MB incompressible file both directions; compare with the iperf3 raw-link number.

### Phase 2: Persistence

**Goal:** the connection survives real life.
- **2a Android:** foreground service (9.1), notification with Pause/Stop, wake + Wi-Fi locks, battery-optimisation request, Xiaomi guidance screen, runtime notification permission.
- **2b Android:** move the engine into the service isolate; add `ServiceIsolateEngineClient`; survive swipe-away.
- **Windows:** tray, hide-on-close, start-on-login, reconnect state machine with 3 s backoff (7), app-level heartbeat.

**Packages:** `flutter_foreground_task`, `permission_handler`, `window_manager`, `tray_manager`, `launch_at_startup`, `connectivity_plus` (optional).
**Acceptance:** with the app backgrounded and the screen locked for 10 minutes, a file sent from the PC arrives; toggling the hotspot recovers automatically; swiping the app away (2b) keeps the service running; closing the Windows window keeps it in the tray and connected.
**Test:** the matrix in section 13.

### Phase 3: Identity, pairing, trust

**Goal:** no PIN per session; only paired devices connect.
- Device identity (6.1), secure store, device id.
- Protocol v2 handshake (5.4), `hello/hello_ack/auth`.
- Pairing window, code + QR, proof, verification phrase, `devices` table (Drift introduced here), Devices screen (functional, plain UI is fine).
- Auto-accept policy, forget device.
- Unpaired devices rejected with a clear event.

**Packages:** `cryptography` (+ `cryptography_flutter`), `flutter_secure_storage`, `drift`, `sqlite3_flutter_libs` (or `drift_flutter`), `qr_flutter`, `mobile_scanner` (for phone-to-phone scan).
**Acceptance:** after one pairing, PC and phone reconnect and transfer with **no code, no IP typing**; a third device with the wrong code or no pairing cannot send; forgetting a device blocks it immediately; unit tests cover the handshake transcript and proof verification.

### Phase 4: History, settings, storage

**Goal:** data and configuration.
- `transfers` table + history repository; engine writes state changes; retention job.
- `SettingsNotifier` and persisted settings (4.3); simple settings screen.
- `StorageResolver` for Windows (folder picker, organise-by) and Android (MediaStore, `byType`/`downloads`); free-space check; open file / show in folder.
- Offline queue (`queued` status) and auto-drain on reconnect.
- Thumbnail generation for images (decode at <= 256 px), video thumbnails where a package supports the platform (evaluate), glyph fallback.

**Packages:** `shared_preferences`, `path_provider`, `open_filex`, `file_picker` (v12+ API), optional `video_thumbnail`/native thumbnail package (evaluate per platform).
**Acceptance:** history survives restarts and shows direction, size, device, status; changing the save path on Windows takes effect for the next file; on Android, received images appear in the Gallery and files in the Files app under `Download/HotShare`; queued items send automatically when the device returns.

### Phase 5: Design system and screens

**Goal:** Ember Glass UI per `HOTSHARE_DESIGN_GUIDE.md`.
- Tokens, `AppBackground`, `GlassSurface`, buttons, fields, nav (pill and rail), sheets, `DeviceBubble`, `TransferRing`, `RadarStage`, `FileGlyph`, `HistoryTile`, toasts.
- Screens: Nearby, History (filters, search, detail sheet), Devices (pairing sheets, verification), Settings (full list), Onboarding.
- Windows: Mica/Acrylic via `flutter_acrylic`, custom title bar. Android: edge-to-edge, frosted fallback.
- Motion spec (design guide 6), haptics, Reduce motion / Reduce transparency.
- Performance guard: frame-time monitor and automatic style downgrade.

**Packages:** `flutter_acrylic`, `window_manager`, `flutter_animate` (optional), an icon set package, optional `liquid_glass_renderer` (evaluate).
**Acceptance:** the design checklist (design guide 14) passes for items that do not depend on Phase 6; performance budget met on the user's phone and PC.

### Phase 6: Share and shortcut integrations

**Goal:** sending from anywhere.
- Android share sheet intent filters + Kotlin handler + quick-send sheet (11.1).
- Windows single instance, `--send` handling, Send-to shortcut, context-menu entries, toast notifications (11.2, 11.4).
- Floating bubble (Android) and Drop Dock (Windows) after a short spike on multi-window stability.
- Optional: Direct Share shortcuts, Quick Settings tile.

**Packages:** `windows_single_instance` (or custom), `flutter_overlay_window`, `local_notifier`, `flutter_local_notifications`, optional `desktop_multi_window`.
**Acceptance:** share a photo from the phone's Gallery to HotShare and it arrives on the PC with one tap (or none if a single device is online); right-click a file in Explorer and it sends; multi-select sends as one batch; the bubble/dock work when enabled.

### Phase 7: Reliability, integrity, security hardening

**Goal:** dependable on bad networks and large files.
- SHA-256 verification end to end (8.7).
- Resume (8.5), cancel from both sides, multi-file batches, optional concurrency (`multi1`).
- Session encryption: ephemeral X25519 key agreement bound into the signed handshake, HKDF-SHA256 for keys, **ChaCha20-Poly1305** per frame with counter nonces; measure throughput impact; if it costs more than ~20%, enable `cryptography_flutter` native acceleration or move crypto into a worker isolate. Make encryption default-on once the benchmark is acceptable.
- Optional raw TCP data channel (8.4) if benchmarks say so.
- Robust edge cases: zero-byte files, huge files (> 4 GB), name collisions, Unicode/emoji names, receiver disk full, sender file modified during send (fail with a clear error), permission revoked mid-transfer.

**Acceptance:** killing the link at 50% and restoring resumes from the offset (not from zero); a flipped bit in transit (test hook) is detected by the checksum; encrypted transfers within an agreed overhead; the test matrix in section 13 passes.

### Phase 8: Polish and packaging

**Goal:** shippable for personal use (and beyond).
- App icons, tray icons, splash; sounds (optional); empty states; copy review.
- Windows installer: MSIX or Inno Setup (decide; MSIX has stricter capabilities, Inno is simpler); code signing optional.
- Android: release signing, `flutter build apk --release` / App Bundle; verify permissions in release mode (INTERNET etc.) and that the foreground service works in release.
- Crash/diagnostics: local rotating log file, "Export diagnostics" in Settings.
- Optional: macOS target (needs a Mac, network entitlements for client/server and file access, signing for distribution).

**Acceptance:** clean install on a fresh Windows user and fresh Android install can pair and transfer; release builds behave like debug builds.

---

## 13. Test plan

**Functional matrix (run before closing Phases 2, 3, 6, 7):**

| Scenario | Expected |
| --- | --- |
| 0 B, 1 KB, 10 MB, 500 MB, 2 GB files, both directions | All delivered, verified |
| Names with spaces, Unicode, emoji, very long, duplicates | Saved safely, unique names |
| Multi-file batch (20 files) | One batch in history, all arrive |
| Hotspot off/on during transfer | Fails or resumes (Phase 7), no corrupt final file, partial cleaned |
| Phone screen locked for 10 min, app in background | Still connected; transfer works |
| App swiped away (after 2b) | Service survives; receiving works |
| PC sleep/resume | Reconnects automatically |
| Unpaired device attempts to connect | Rejected, no files written |
| Wrong pairing code x3 | Window closes |
| Receiver declines | Sender shows Declined |
| Receiver out of space | `reject: no_space`, clear message |
| Cancel from sender / from receiver | Both sides clean up |
| Android share of image, PDF, text, multiple items | Arrives correctly |
| Explorer right-click with 5 files selected | One batch |
| Low-end Android / Reduce transparency on | Smooth, readable |

**Automated:** unit tests for protocol, sanitiser, flow control, handshake transcript, pairing proof, storage resolver logic; a fake `EngineClient` for widget tests; golden tests for key glass components (opaque fallback variant, since blur is not golden-friendly).

**Benchmarks:** record in `docs/PERF.md`: raw link (iperf3), Benchmark mode MB/s each direction, real file MB/s, CPU usage on each side, with and without encryption.

---

## 14. Package shortlist (verify current versions and platform support with `flutter pub add`)

| Purpose | Package |
| --- | --- |
| State | `flutter_riverpod` |
| DB | `drift`, `sqlite3_flutter_libs` (or `drift_flutter`) |
| Settings / secrets | `shared_preferences`, `flutter_secure_storage` |
| Crypto | `cryptography`, `cryptography_flutter`, `crypto` |
| Files | `file_picker` (v12+ API), `desktop_drop` (`<0.9.0`), `path_provider`, `open_filex` |
| Android background | `flutter_foreground_task`, `permission_handler`, `flutter_overlay_window`, `flutter_local_notifications` |
| Android native glue | Kotlin MethodChannel/EventChannel (share intents, MediaStore, free space) |
| Windows shell | `window_manager`, `tray_manager`, `launch_at_startup`, `flutter_acrylic`, `local_notifier`, single-instance package |
| Pairing UI | `qr_flutter`, `mobile_scanner` |
| Device info | `device_info_plus` |
| Network hints | `connectivity_plus`, `nsd` (mDNS, later) |
| UI polish | `flutter_animate` (optional), icon set package, `liquid_glass_renderer` (optional, evaluate) |

Anything marked "evaluate" needs a quick spike and a line in `DECISIONS.md` before adopting.

---

## 15. Open decisions to confirm with the user

1. **Brand and name** (currently "HotShare"; package id `com.example.hotshare` must change before any release).
2. **Encryption default** (recommend on) and whether to accept a small speed cost.
3. **Raw TCP data channel**: only if Phase 1 benchmarks show WebSocket is the bottleneck.
4. **Drop Dock implementation**: separate window vs overlay mode inside the main window (decide after the Phase 6 spike).
5. **Windows packaging**: MSIX vs Inno Setup.
6. **Android custom folder (SAF)** in v1 or later (recommend later).
7. **macOS and Android-to-Android timing** (recommend after Phase 8; architecture already supports it via mDNS and the initiator rule).
8. **Light theme** timing (recommend after Phase 8).

---

## 16. Definition of done (whole project)

- Pair once, then every later connection is automatic on hotspot.
- The connection survives backgrounding, screen lock and hotspot toggles on Android, and sleep/network changes on Windows.
- Transfers run near the Wi-Fi link's capability, are integrity-verified, can resume, and never leave corrupt files.
- Share history, configurable storage, and settings work and persist.
- Share from other Android apps and from Windows Explorer works in one step.
- The UI matches the Ember Glass design with AirDrop-style interactions and meets the performance budget on the user's devices.
- `flutter analyze` is clean, tests pass, release builds work on both platforms.
