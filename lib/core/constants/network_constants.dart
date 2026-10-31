/// Network and transfer constants for HotShare protocol v1.
const int kPort = 8080;

/// Max bytes in flight before the sender pauses for acknowledgment.
const int kWindow = 4 * 1024 * 1024; // 4 MB

/// Receiver reports progress every [kAckEvery] bytes.
const int kAckEvery = 1024 * 1024; // 1 MB
