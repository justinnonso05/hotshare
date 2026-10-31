/// Pure Dart API definitions for commands sent to the HotShare engine
/// and events emitted by the HotShare engine.
library;

// -----------------------------------------------------------------------------
// Commands (UI/Client -> Engine)
// -----------------------------------------------------------------------------

abstract class EngineCommand {
  const EngineCommand();
}

class StartServerCommand extends EngineCommand {
  final int port;
  const StartServerCommand({this.port = 8080});
}

class ConnectCommand extends EngineCommand {
  final String host;
  final int port;
  const ConnectCommand({required this.host, this.port = 8080});
}

class DisconnectCommand extends EngineCommand {
  const DisconnectCommand();
}

class SendFilesCommand extends EngineCommand {
  final List<String> paths;
  const SendFilesCommand(this.paths);
}

class SendTextCommand extends EngineCommand {
  final String text;
  const SendTextCommand(this.text);
}

class RunBenchmarkCommand extends EngineCommand {
  final int sizeMb;
  const RunBenchmarkCommand({this.sizeMb = 100});
}

class CancelTransferCommand extends EngineCommand {
  final String transferId;
  const CancelTransferCommand(this.transferId);
}

class SetAutoReconnectCommand extends EngineCommand {
  final bool enabled;
  const SetAutoReconnectCommand(this.enabled);
}

class OpenPairingWindowCommand extends EngineCommand {
  const OpenPairingWindowCommand();
}

class SubmitPairingCodeCommand extends EngineCommand {
  final String code;
  const SubmitPairingCodeCommand(this.code);
}

class ConfirmPairingCommand extends EngineCommand {
  final bool isConfirmed;
  const ConfirmPairingCommand(this.isConfirmed);
}

class RevokeDeviceCommand extends EngineCommand {
  final String deviceId;
  const RevokeDeviceCommand(this.deviceId);
}

// -----------------------------------------------------------------------------
// Events (Engine -> UI/Notifiers)
// -----------------------------------------------------------------------------

abstract class EngineEvent {
  const EngineEvent();
}

class LogEvent extends EngineEvent {
  final String message;
  final DateTime timestamp;
  LogEvent(this.message) : timestamp = DateTime.now();
}

class PeerStateEvent extends EngineEvent {
  final bool isConnected;
  final String peerName;
  final String? host;
  final bool isPaired;
  final bool isAuthenticated;

  const PeerStateEvent({
    required this.isConnected,
    this.peerName = '',
    this.host,
    this.isPaired = false,
    this.isAuthenticated = false,
  });
}

class TransferProgressEvent extends EngineEvent {
  final String id;
  final String name;
  final int bytesDone;
  final int totalBytes;
  final double progress; // 0.0 to 1.0
  final double speedBytesPerSec;
  final bool isSending;

  const TransferProgressEvent({
    required this.id,
    required this.name,
    required this.bytesDone,
    required this.totalBytes,
    required this.progress,
    required this.speedBytesPerSec,
    required this.isSending,
  });
}

class TransferCompletedEvent extends EngineEvent {
  final String id;
  final String name;
  final String? filePath;
  final int size;
  final bool isSending;
  final bool success;
  final String? error;

  const TransferCompletedEvent({
    required this.id,
    required this.name,
    this.filePath,
    required this.size,
    required this.isSending,
    required this.success,
    this.error,
  });
}

class BenchmarkResultEvent extends EngineEvent {
  final double mbPerSec;
  final int totalBytes;
  final Duration duration;
  final bool isSender;

  const BenchmarkResultEvent({
    required this.mbPerSec,
    required this.totalBytes,
    required this.duration,
    required this.isSender,
  });
}

class PairingWindowOpenedEvent extends EngineEvent {
  final String code;
  final String qrPayload;
  final DateTime expiresAt;

  const PairingWindowOpenedEvent({
    required this.code,
    required this.qrPayload,
    required this.expiresAt,
  });
}

class PairingVerificationRequiredEvent extends EngineEvent {
  final List<String> sasWords;
  final String peerName;
  final String peerId;

  const PairingVerificationRequiredEvent({
    required this.sasWords,
    required this.peerName,
    required this.peerId,
  });
}

class PairingCompletedEvent extends EngineEvent {
  final bool success;
  final String peerName;
  final String? error;

  const PairingCompletedEvent({
    required this.success,
    required this.peerName,
    this.error,
  });
}
