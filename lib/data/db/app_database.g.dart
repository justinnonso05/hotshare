// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DevicesTable extends Devices with TableInfo<$DevicesTable, Device> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<Uint8List> publicKey = GeneratedColumn<Uint8List>(
    'public_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pairedAt = GeneratedColumn<DateTime>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastKnownHostMeta = const VerificationMeta(
    'lastKnownHost',
  );
  @override
  late final GeneratedColumn<String> lastKnownHost = GeneratedColumn<String>(
    'last_known_host',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoAcceptMeta = const VerificationMeta(
    'autoAccept',
  );
  @override
  late final GeneratedColumn<bool> autoAccept = GeneratedColumn<bool>(
    'auto_accept',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_accept" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _revokedMeta = const VerificationMeta(
    'revoked',
  );
  @override
  late final GeneratedColumn<bool> revoked = GeneratedColumn<bool>(
    'revoked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("revoked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    platform,
    publicKey,
    pairedAt,
    lastSeenAt,
    lastKnownHost,
    autoAccept,
    revoked,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<Device> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_publicKeyMeta);
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pairedAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('last_known_host')) {
      context.handle(
        _lastKnownHostMeta,
        lastKnownHost.isAcceptableOrUnknown(
          data['last_known_host']!,
          _lastKnownHostMeta,
        ),
      );
    }
    if (data.containsKey('auto_accept')) {
      context.handle(
        _autoAcceptMeta,
        autoAccept.isAcceptableOrUnknown(data['auto_accept']!, _autoAcceptMeta),
      );
    }
    if (data.containsKey('revoked')) {
      context.handle(
        _revokedMeta,
        revoked.isAcceptableOrUnknown(data['revoked']!, _revokedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Device map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Device(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}public_key'],
      )!,
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paired_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      ),
      lastKnownHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_known_host'],
      ),
      autoAccept: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_accept'],
      )!,
      revoked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}revoked'],
      )!,
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }
}

class Device extends DataClass implements Insertable<Device> {
  final String id;
  final String name;
  final String platform;
  final Uint8List publicKey;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;
  final String? lastKnownHost;
  final bool autoAccept;
  final bool revoked;
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.publicKey,
    required this.pairedAt,
    this.lastSeenAt,
    this.lastKnownHost,
    required this.autoAccept,
    required this.revoked,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['platform'] = Variable<String>(platform);
    map['public_key'] = Variable<Uint8List>(publicKey);
    map['paired_at'] = Variable<DateTime>(pairedAt);
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    }
    if (!nullToAbsent || lastKnownHost != null) {
      map['last_known_host'] = Variable<String>(lastKnownHost);
    }
    map['auto_accept'] = Variable<bool>(autoAccept);
    map['revoked'] = Variable<bool>(revoked);
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      id: Value(id),
      name: Value(name),
      platform: Value(platform),
      publicKey: Value(publicKey),
      pairedAt: Value(pairedAt),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      lastKnownHost: lastKnownHost == null && nullToAbsent
          ? const Value.absent()
          : Value(lastKnownHost),
      autoAccept: Value(autoAccept),
      revoked: Value(revoked),
    );
  }

  factory Device.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Device(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      platform: serializer.fromJson<String>(json['platform']),
      publicKey: serializer.fromJson<Uint8List>(json['publicKey']),
      pairedAt: serializer.fromJson<DateTime>(json['pairedAt']),
      lastSeenAt: serializer.fromJson<DateTime?>(json['lastSeenAt']),
      lastKnownHost: serializer.fromJson<String?>(json['lastKnownHost']),
      autoAccept: serializer.fromJson<bool>(json['autoAccept']),
      revoked: serializer.fromJson<bool>(json['revoked']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'platform': serializer.toJson<String>(platform),
      'publicKey': serializer.toJson<Uint8List>(publicKey),
      'pairedAt': serializer.toJson<DateTime>(pairedAt),
      'lastSeenAt': serializer.toJson<DateTime?>(lastSeenAt),
      'lastKnownHost': serializer.toJson<String?>(lastKnownHost),
      'autoAccept': serializer.toJson<bool>(autoAccept),
      'revoked': serializer.toJson<bool>(revoked),
    };
  }

  Device copyWith({
    String? id,
    String? name,
    String? platform,
    Uint8List? publicKey,
    DateTime? pairedAt,
    Value<DateTime?> lastSeenAt = const Value.absent(),
    Value<String?> lastKnownHost = const Value.absent(),
    bool? autoAccept,
    bool? revoked,
  }) => Device(
    id: id ?? this.id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    publicKey: publicKey ?? this.publicKey,
    pairedAt: pairedAt ?? this.pairedAt,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    lastKnownHost: lastKnownHost.present
        ? lastKnownHost.value
        : this.lastKnownHost,
    autoAccept: autoAccept ?? this.autoAccept,
    revoked: revoked ?? this.revoked,
  );
  Device copyWithCompanion(DevicesCompanion data) {
    return Device(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      platform: data.platform.present ? data.platform.value : this.platform,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      lastKnownHost: data.lastKnownHost.present
          ? data.lastKnownHost.value
          : this.lastKnownHost,
      autoAccept: data.autoAccept.present
          ? data.autoAccept.value
          : this.autoAccept,
      revoked: data.revoked.present ? data.revoked.value : this.revoked,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Device(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('publicKey: $publicKey, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastKnownHost: $lastKnownHost, ')
          ..write('autoAccept: $autoAccept, ')
          ..write('revoked: $revoked')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    platform,
    $driftBlobEquality.hash(publicKey),
    pairedAt,
    lastSeenAt,
    lastKnownHost,
    autoAccept,
    revoked,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Device &&
          other.id == this.id &&
          other.name == this.name &&
          other.platform == this.platform &&
          $driftBlobEquality.equals(other.publicKey, this.publicKey) &&
          other.pairedAt == this.pairedAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.lastKnownHost == this.lastKnownHost &&
          other.autoAccept == this.autoAccept &&
          other.revoked == this.revoked);
}

class DevicesCompanion extends UpdateCompanion<Device> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> platform;
  final Value<Uint8List> publicKey;
  final Value<DateTime> pairedAt;
  final Value<DateTime?> lastSeenAt;
  final Value<String?> lastKnownHost;
  final Value<bool> autoAccept;
  final Value<bool> revoked;
  final Value<int> rowid;
  const DevicesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.platform = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.lastKnownHost = const Value.absent(),
    this.autoAccept = const Value.absent(),
    this.revoked = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required String id,
    required String name,
    required String platform,
    required Uint8List publicKey,
    required DateTime pairedAt,
    this.lastSeenAt = const Value.absent(),
    this.lastKnownHost = const Value.absent(),
    this.autoAccept = const Value.absent(),
    this.revoked = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       platform = Value(platform),
       publicKey = Value(publicKey),
       pairedAt = Value(pairedAt);
  static Insertable<Device> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? platform,
    Expression<Uint8List>? publicKey,
    Expression<DateTime>? pairedAt,
    Expression<DateTime>? lastSeenAt,
    Expression<String>? lastKnownHost,
    Expression<bool>? autoAccept,
    Expression<bool>? revoked,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (platform != null) 'platform': platform,
      if (publicKey != null) 'public_key': publicKey,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (lastKnownHost != null) 'last_known_host': lastKnownHost,
      if (autoAccept != null) 'auto_accept': autoAccept,
      if (revoked != null) 'revoked': revoked,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? platform,
    Value<Uint8List>? publicKey,
    Value<DateTime>? pairedAt,
    Value<DateTime?>? lastSeenAt,
    Value<String?>? lastKnownHost,
    Value<bool>? autoAccept,
    Value<bool>? revoked,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      publicKey: publicKey ?? this.publicKey,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastKnownHost: lastKnownHost ?? this.lastKnownHost,
      autoAccept: autoAccept ?? this.autoAccept,
      revoked: revoked ?? this.revoked,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<Uint8List>(publicKey.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<DateTime>(pairedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (lastKnownHost.present) {
      map['last_known_host'] = Variable<String>(lastKnownHost.value);
    }
    if (autoAccept.present) {
      map['auto_accept'] = Variable<bool>(autoAccept.value);
    }
    if (revoked.present) {
      map['revoked'] = Variable<bool>(revoked.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('publicKey: $publicKey, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastKnownHost: $lastKnownHost, ')
          ..write('autoAccept: $autoAccept, ')
          ..write('revoked: $revoked, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DevicesTable devices = $DevicesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [devices];
}

typedef $$DevicesTableCreateCompanionBuilder =
    DevicesCompanion Function({
      required String id,
      required String name,
      required String platform,
      required Uint8List publicKey,
      required DateTime pairedAt,
      Value<DateTime?> lastSeenAt,
      Value<String?> lastKnownHost,
      Value<bool> autoAccept,
      Value<bool> revoked,
      Value<int> rowid,
    });
typedef $$DevicesTableUpdateCompanionBuilder =
    DevicesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> platform,
      Value<Uint8List> publicKey,
      Value<DateTime> pairedAt,
      Value<DateTime?> lastSeenAt,
      Value<String?> lastKnownHost,
      Value<bool> autoAccept,
      Value<bool> revoked,
      Value<int> rowid,
    });

class $$DevicesTableFilterComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastKnownHost => $composableBuilder(
    column: $table.lastKnownHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get revoked => $composableBuilder(
    column: $table.revoked,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastKnownHost => $composableBuilder(
    column: $table.lastKnownHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get revoked => $composableBuilder(
    column: $table.revoked,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<Uint8List> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<DateTime> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastKnownHost => $composableBuilder(
    column: $table.lastKnownHost,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoAccept => $composableBuilder(
    column: $table.autoAccept,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get revoked =>
      $composableBuilder(column: $table.revoked, builder: (column) => column);
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DevicesTable,
          Device,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (Device, BaseReferences<_$AppDatabase, $DevicesTable, Device>),
          Device,
          PrefetchHooks Function()
        > {
  $$DevicesTableTableManager(_$AppDatabase db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<Uint8List> publicKey = const Value.absent(),
                Value<DateTime> pairedAt = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<String?> lastKnownHost = const Value.absent(),
                Value<bool> autoAccept = const Value.absent(),
                Value<bool> revoked = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                id: id,
                name: name,
                platform: platform,
                publicKey: publicKey,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                lastKnownHost: lastKnownHost,
                autoAccept: autoAccept,
                revoked: revoked,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String platform,
                required Uint8List publicKey,
                required DateTime pairedAt,
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<String?> lastKnownHost = const Value.absent(),
                Value<bool> autoAccept = const Value.absent(),
                Value<bool> revoked = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                id: id,
                name: name,
                platform: platform,
                publicKey: publicKey,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                lastKnownHost: lastKnownHost,
                autoAccept: autoAccept,
                revoked: revoked,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DevicesTable,
      Device,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (Device, BaseReferences<_$AppDatabase, $DevicesTable, Device>),
      Device,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
}
