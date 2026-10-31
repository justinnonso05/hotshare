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

@DriftDatabase(tables: [Devices])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'hotshare_db');
  }

  // Queries
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
}
