import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get platform => text()();
  BlobColumn get publicKey => blob()();
  DateTimeColumn get pairedAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  TextColumn get lastKnownHost => text().nullable()();
  BoolColumn get autoAccept => boolean().withDefault(const Constant(true))();
  BoolColumn get revoked => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get peerId => text()();
  TextColumn get direction => text()(); // 'in' or 'out'
  TextColumn get name => text()();
  IntColumn get size => integer()();
  TextColumn get mime => text().nullable()();
  TextColumn get kind => text()(); // 'image', 'video', 'audio', 'document', 'archive', 'other'
  TextColumn get status => text()(); // 'queued', 'transferring', 'done', 'failed', 'cancelled', 'declined'
  IntColumn get bytesDone => integer()();
  TextColumn get localPath => text().nullable()();
  TextColumn get thumbPath => text().nullable()();
  TextColumn get sha256 => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  IntColumn get avgBytesPerSec => integer().nullable()();
  TextColumn get error => text().nullable()();
  TextColumn get batchId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Devices, Transfers])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(transfers);
          }
        },
      );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'hotshare_db');
  }

  // Device Queries
  Stream<List<Device>> watchActiveDevices() {
    return (select(devices)..where((tbl) => tbl.revoked.equals(false))).watch();
  }

  Future<Device?> findDeviceById(String id) {
    return (select(devices)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();
  }

  Future<void> upsertDevice(DevicesCompanion device) {
    return into(devices).insertOnConflictUpdate(device);
  }

  Future<void> updateLastSeen(String id, String host) {
    return (update(devices)..where((tbl) => tbl.id.equals(id))).write(
      DevicesCompanion(
        lastSeenAt: Value(DateTime.now()),
        lastKnownHost: Value(host),
      ),
    );
  }

  Future<void> revokeDevice(String id) {
    return (update(devices)..where((tbl) => tbl.id.equals(id))).write(
      const DevicesCompanion(
        revoked: Value(true),
      ),
    );
  }

  // Transfer Queries
  Stream<List<Transfer>> watchTransferHistory() {
    return (select(transfers)
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
        .watch();
  }

  Future<void> insertTransfer(TransfersCompanion transfer) {
    return into(transfers).insertOnConflictUpdate(transfer);
  }

  Future<void> updateTransferProgress(String id, int bytesDone, int avgSpeed) {
    return (update(transfers)..where((tbl) => tbl.id.equals(id))).write(
      TransfersCompanion(
        bytesDone: Value(bytesDone),
        avgBytesPerSec: Value(avgSpeed),
      ),
    );
  }

  Future<void> completeTransfer(
    String id, {
    required String status,
    String? localPath,
    String? error,
    int? avgSpeed,
  }) {
    return (update(transfers)..where((tbl) => tbl.id.equals(id))).write(
      TransfersCompanion(
        status: Value(status),
        localPath: Value(localPath),
        error: Value(error),
        finishedAt: Value(DateTime.now()),
        avgBytesPerSec: Value(avgSpeed),
      ),
    );
  }

  Future<int> purgeOldTransfers(DateTime cutoff) {
    return (delete(transfers)..where((tbl) => tbl.startedAt.isSmallerThanValue(cutoff))).go();
  }
}
