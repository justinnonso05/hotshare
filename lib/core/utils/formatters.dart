/// Formats a byte count into a human-readable string (B, KB, MB, GB).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Formats a [DateTime] into a friendly time-ago string (e.g. "just now", "3m ago", "1h ago", "2d ago", "1w ago").
String formatTimeAgo(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.isNegative || diff.inSeconds < 45) {
    return 'just now';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  }
  if (diff.inDays < 30) {
    final weeks = (diff.inDays / 7).floor();
    return '${weeks}w ago';
  }
  if (diff.inDays < 365) {
    final months = (diff.inDays / 30).floor();
    return '${months}mo ago';
  }
  final years = (diff.inDays / 365).floor();
  return '${years}y ago';
}
