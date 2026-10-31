/// Network and transfer constants for HotShare protocol v1+.
const int kPort = 8080;

/// Chunk size for file streaming (256 KB).
const int kChunkSize = 256 * 1024;

/// In-flight credit window before sender pauses (12 MB).
const int kWindow = 12 * 1024 * 1024;

/// Receiver reports progress every [kAckEvery] bytes (1 MB).
const int kAckEvery = 1024 * 1024;

/// Maximum frequency for emitting UI progress events per second.
const int kProgressMaxFps = 10;
const Duration kProgressThrottleInterval = Duration(milliseconds: 100);
