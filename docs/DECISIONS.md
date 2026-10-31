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
