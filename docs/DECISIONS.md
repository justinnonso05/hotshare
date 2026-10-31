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
