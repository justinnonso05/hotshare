# HotShare Performance & Throughput Log

This document records transfer speeds, optimizations, and benchmark results across phases.

---

## Phase 1 Optimizations Applied

1. **WebSocket Compression Disabled**:
   - Both server and client now set `compression: CompressionOptions.compressionOff`.
   - Eliminates useless per-message CPU compression overhead for already compressed media (mkv, jpg, mp4, zip).
2. **Optimized Frame Chunking**:
   - Increased chunk streaming size to **256 KB** (`kChunkSize = 256 * 1024`).
3. **Expanded Flow-Control Window**:
   - Expanded in-flight credit window to **12 MB** (`kWindow = 12 * 1024 * 1024`) to eliminate stalling over Wi-Fi jitter.
4. **UI Update Throttling (10 Hz)**:
   - Emitting UI progress events at at most 10 times per second (`kProgressThrottleInterval = 100ms`).
5. **Non-blocking Receiver Disk Writes**:
   - Direct streaming to `IOSink` without per-chunk flushing.

---

## Synthetic Benchmark Mode

- Built-in test: streams in-memory synthetic bytes (default 100 MB) across the socket.
- Bypasses disk I/O on both sides to measure the true network ceiling of the link.
- Available via the "Test Speed (100 MB)" button in the UI.

### Test Log

| Date | Direction | Mode | Size | Speed (MB/s) | Notes |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Baseline | PC -> Phone | Real File | ~150 MB | 10–15 MB/s | Initial prototype with 64KB chunks and 4MB window |
| Phase 1 | Synthetic | In-memory | 100 MB | *Pending user run* | Compression off, 256KB chunks, 12MB window |
