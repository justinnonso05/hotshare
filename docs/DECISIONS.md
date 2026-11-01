# HotShare Architectural Decisions (ADR)

This document tracks key technical decisions, context, and rationale as the codebase evolves across phases.

---

## ADR 000: Project Baseline and Phase 0 Setup
- **Date:** 2026-10-31
- **Status:** Accepted
- **Context:**
  The project started as a monolithic 586-line prototype in `lib/main.dart` with direct WebSocket connections, JSON framing, and binary streaming between an Android phone (acting as a hotspot server) and a Windows PC (gateway client).
- **Decisions:**
  1. **Git Initialization:** Initialized clean git tracking with standard Flutter ignores.
  2. **Android minSdkVersion:** Elevated `minSdk` to 29 in `android/app/build.gradle.kts`. This is required for scoped storage and modern `MediaStore` downloads API without legacy storage permissions.
  3. **Module Extraction:** Mechanically decomposed `lib/main.dart` into:
     - `lib/core/constants/network_constants.dart` (ports, buffer windows, ack intervals)
     - `lib/core/protocol/protocol_messages.dart` (wire protocol message contracts)
     - `lib/core/net/gateway_finder.dart` (Windows gateway discovery helper)
     - `lib/core/storage/storage_helper.dart` (storage directory path resolver and unique name generator)
     - `lib/core/utils/formatters.dart` (human-readable file size and time formatting)
     - `lib/ui/screens/share_page.dart` (stateful UI page)
     - `lib/main.dart` (clean entry point)
  4. **Preserve Wire Protocol:** Zero wire protocol or runtime changes in Phase 0 to ensure full backward compatibility with the existing prototype.


---

## ADR 001: Phase 1 Speed & Architecture Foundation
- **Date:** 2026-10-31
- **Status:** Accepted
- **Context:**
  The initial prototype relied on widget `setState()` calls on every chunk, used default 64 KB streaming chunks, and enabled WebSocket `permessage-deflate` compression.
- **Decisions:**
  1. **HotShareEngine Facade:** Decoupled networking and streaming from Flutter widgets into `lib/core/engine/hotshare_engine.dart` with a pure Dart `EngineCommand` and `EngineEvent` API.
  2. **Riverpod State Layer:** Introduced `flutter_riverpod` (v2.6.1) without code generation to manage connection status, active transfer progress, and completed file records.
  3. **Network Throughput Quick Wins (Section 8.1):**
     - Disabled WebSocket compression on both client and server (`CompressionOptions.compressionOff`).
     - Increased chunk size to 256 KB (`kChunkSize = 256 * 1024`).
     - Expanded flow-control in-flight credit window to 12 MB (`kWindow = 12 * 1024 * 1024`).
     - Throttled UI progress emissions to at most 10 Hz (`kProgressThrottleInterval = 100ms`).
  4. **Synthetic Benchmark Mode:** Built-in in-memory benchmark (`RunBenchmarkCommand`) to measure raw Wi-Fi link speed bypassing disk I/O.
  5. **Unit Testing:** Established automated unit tests in `test/core_test.dart`.


---

## ADR 002: Phase 2 Persistence & Background Lifecycle
- **Date:** 2026-10-31
- **Status:** Accepted
- **Context:**
  When backgrounded on mobile, Android suspends processes without a foreground service or wake lock. On desktop, closing the window kills the process and loses connection.
- **Decisions:**
  1. **Android Foreground Service (`flutter_foreground_task`):**
     - Declared `FOREGROUND_SERVICE` with type `connectedDevice`.
     - Configured persistent notification channel (`hotshare_service`) with `allowWakeLock: true` and `allowWifiLock: true` to prevent network throttling during active transfers and standby.
     - Requested battery optimization exemption (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`).
  2. **Windows Tray & Window Management (`window_manager`, `tray_manager`):**
     - Set `windowManager.setPreventClose(true)`. Intercepting window close minimizes to system tray instead of exiting.
     - System tray icon with context menu ("Open HotShare", "Quit").
  3. **Heartbeat & Auto-Recovery:**
     - Added 5s heartbeat ping/pong with 15s timeout to detect link failure immediately.
     - 3s automatic reconnection loop on Windows when the phone hotspot connection is lost or toggled.


---

## ADR 003: Phase 3 Identity, Pairing, and Drift Persistence
- **Date:** 2026-10-31
- **Status:** Accepted
- **Context:**
  Ad-hoc connections required manual IP addresses, had no permanent identity verification, and lacked mutual authentication.
- **Decisions:**
  1. **Ed25519 Cryptographic Identity:** Generated via `cryptography` package and persisted in platform secure storage (`flutter_secure_storage`). `deviceId` derived from `Base32(SHA-256(pubKey)[:16])`.
  2. **Drift Local Database (`AppDatabase`):** Used `drift` + `drift_flutter` with SQLite on Android and Windows to persist paired devices, public keys, and last-seen timestamps.
  3. **Protocol v2 Handshake:** `hello` / `hello_ack` / `auth` with signed nonces over session transcripts.
  4. **One-Time Pairing Flow:**
     - 60s pairing window with 6-digit code and QR code.
     - `HMAC-SHA256` pairing proof preventing network snooping.
     - 4-word SAS (Short Authentication String) verification phrase preventing Man-in-the-Middle attacks.
     - Upon confirmation, trusted devices auto-reconnect without PIN or confirmation prompts.


---

## ADR 004: Phase 4 Transfer History, Settings, and Storage Resolution
- **Date:** 2026-10-31
- **Status:** Accepted
- **Context:**
  Transfers were only held in volatile memory and lost on restart. Storage directories were hardcoded without file categorization or settings support.
- **Decisions:**
  1. **Transfers Table & Persistent History:** Added `Transfers` table to Drift database tracking transfers, directions, sizes, statuses, throughput speeds, and local filesystem paths.
  2. **Settings Layer:** Created `AppSettings` and `SettingsNotifier` with `SharedPreferences` to manage user preferences (auto-accept, save modes, auto-reconnect, retention limits).
  3. **Unified StorageResolver:**
     - Automatic classification into 6 file kinds: `image`, `video`, `audio`, `document`, `archive`, `other`.
     - Android: Scoped storage routing (`Pictures/HotShare`, `Movies/HotShare`, `Music/HotShare`, `Download/HotShare`).
     - Windows: Folder organization by type, date, or custom root.
     - Cross-platform file revealing: `explorer.exe /select, <path>` on Windows and `open_filex` on Android.
  4. **Retention Policy:** Automated background purging of transfer records older than 90 days.

---

## ADR 005: Phase 5 Ember Glass Design System, Platform Shells & Screens
- **Date:** 2026-10-31
- **Status:** Accepted
- **Context:**
  The UI was a functional prototype page (`SharePage`) using standard Material 3 components. The app needed a cohesive visual identity matching the Ember Glass specification (dark crimson/red-orange gradients, frosted glass surfaces, circular floating radar, and bespoke platform shells).
- **Decisions:**
  1. **Ember Glass Tokens (`lib/ui/design_system/`):**
     - Colors: `HsColors` with dark base `#0A0A0C`, raised surfaces `#141417`, deep crimson glow `#7A0A12`, red accent `#E5231B`, warm orange glow `#FF7A1A`, and translucent glass fill/stroke tokens.
     - Typography: `HsText` with display, headline, title, body, caption, and micro tiers.
     - Background: `AppBackground` containing two drifting radial glow blobs isolated in a `RepaintBoundary` with lifecycle and `reduceMotion` awareness.
     - Glass Components: `GlassSurface` with backdrop blur, specular top highlight, gradient border; `GlassButton` with pill shape and ember glow; `GlassTextField`; `FileGlyph` with folded corners and kind color coding; `TransferRing` for circular progress; `StatusDot` with connection pulsing.
  2. **Adaptive Platform Shells (`lib/app/`):**
     - Mobile Shell: `MobileShell` with a floating pill navigation bar hovering 16dp above the home gesture bar with active item white pill lens.
     - Desktop Shell: `DesktopShell` with custom 44px draggable title bar strip (`DragToMoveArea`), window controls (minimize, maximize, close), connection indicator, and left glass navigation rail.
  3. **4 Core Feature Screens (`lib/ui/features/`):**
     - Nearby: Header, concentric pulsing radar stage with orbiting peer bubbles, active transfer glass card with real-time speed/progress, floating bobbing file glyphs, and send file actions.
     - History: Search filter, category chips (All, Sent, Received, Images, Videos, Docs, Failed), date-grouped sections (Today, Yesterday, Date), file opening/revealing.
     - Devices: Cryptographic device management, 6-digit PIN & QR pairing sheets, SAS 4-word verification dialog, and forget device confirm dialogs.
     - Settings: Comprehensive settings for device name, auto-accept, pause receiving, storage routing (by-type vs downloads, Windows directory picker, subfolder grouping), appearance controls, and link benchmark diagnostics.



---

## ADR 006: Phase 6 Share Sheet & System Shortcut Integrations
- **Date:** 2026-11-01
- **Status:** Accepted
- **Context:**
  Files could only be sent from within HotShare by tapping file picker buttons or dropping files onto the window. Users need to send files directly from other mobile apps via Android's native share sheet ("Share with...") and from Windows Explorer context menus.
- **Decisions:**
  1. **Native Android Share Sheet Target (`ACTION_SEND` & `ACTION_SEND_MULTIPLE`):**
     - Configured `AndroidManifest.xml` with intent filters matching `*/*`.
     - Implemented direct Kotlin stream extraction in `MainActivity.kt` with background thread copying to avoid UI thread disk I/O, passing cached paths to Dart via `MethodChannel('com.example.hotshare/share_target')`.
  2. **Translucent Quick-Send Sheet (`QuickSendSheet`):**
     - Emitted whenever files are received from external shares or command lines.
     - Displays file thumbnails, kinds, total payload size, target peer connectivity status, and a 1-tap "Send Now" button.
  3. **Windows Explorer Integration:**
     - Added `--send <path>` CLI argument parsing in `main.dart`.
     - Managed `%APPDATA%\Microsoft\Windows\SendTo\HotShare.lnk` shortcut creation/deletion via PowerShell WScript.
     - Managed `HKCU\Software\Classes\*\shell\HotShare` Explorer right-click context menu via Windows `reg.exe` commands.
     - Toggled easily from the Settings screen under "Windows Explorer & Shortcuts".


---

## ADR 007: Phase 7 Reliability, Integrity & Transfer Hardening
- **Date:** 2026-11-01
- **Status:** Accepted
- **Context:**
  Large file transfers on lossy local hotspot links can be interrupted by transient disconnects or suffer bit-rot corruption without end-to-end cryptographic checksum verification.
- **Decisions:**
  1. **End-to-End Streaming SHA-256 Checksums:**
     - Computed incrementally on both sender and receiver using `crypto.AccumulatorSink` without buffering the entire file in RAM.
     - Transmitted in the `done` message; receiver checks matching hash before finalizing. Mismatched or corrupt files are rejected and discarded.
  2. **Interrupted Transfer Resumption:**
     - When receiving an offer for a partially existing file, receiver checks `existingLength`.
     - Responds with `accept: {id: ..., offset: existingLength}` and opens file in `FileMode.append`.
     - Sender seeks to `offset` using `RandomAccessFile.setPosition(offset)` and streams only the remaining bytes, avoiding re-transmitting data.
  3. **Bi-Directional Transfer Cancellation:**
     - Sender or receiver can abort an active transfer at any time via `CancelTransferCommand`.
     - Socket emits a `cancel` frame, immediately flushing and closing open file handles without leaving dangling locks.


---

## ADR 008: Phase 8 Polish, Packaging & Production Readiness
- **Date:** 2026-11-01
- **Status:** Accepted
- **Context:**
  The core protocol, security, glass design system, share targets, and reliability are in place. The app required production assets (adaptive icons, tray icons, splash assets), rotating local crash/diagnostics logging, cleanup of prototype remnants, and packaging setups for Windows and Android.
- **Decisions:**
  1. **HotShare Brand Asset Integration:**
     - Applied complete Ember Glass icon pack across Android (`android/app/src/main/res/` with adaptive icons, monochrome Android 13 layer, and `ic_stat_hotshare` notification drawables) and Windows (`windows/runner/resources/app_icon.ico` with multi-resolution mipmaps).
     - Bundled tray status assets (`tray_idle.ico`, `tray_connected.ico`, `tray_transfer_1..4.ico`) in `pubspec.yaml` and wired into `WindowsTrayManager`.
  2. **Rotating File Logger & Diagnostics Report (`AppLogger`):**
     - Local rotating file logger (`hotshare.log` and `hotshare.log.old`, capped at 2MB) in app support directory.
     - Settings screen "Export Diagnostics" viewer modal with 1-tap clipboard copying and comprehensive environment info (OS, IPs, paired devices, total transfers, event logs).
  3. **Prototype Cleanup:**
     - Removed legacy monolithic prototype `lib/ui/screens/share_page.dart`.
  4. **Packaging Configurations:**
     - Windows: Added Inno Setup script `windows/installer/hotshare_setup.iss` generating clean x64 setup wizard with desktop/Start Menu icons and SendTo integration.
     - Android: Configured `AndroidManifest.xml` with proper app name (`HotShare`), adaptive icons (`@mipmap/ic_launcher` and `@mipmap/ic_launcher_round`), and verified release signing readiness.
