import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();

  static const String exercisesTable = 'exercises';
  static const String workoutsTable = 'workouts';
  static const String settingsTable = 'settings';

  static const String _dbName = 'pullcrane.db';
  static const int _dbVersion = 1;

  Database? _database;
  DatabaseFactory? _factory;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _factory ??= _createDatabaseFactory();
    final String path = await _resolveDatabasePath(_factory!);
    _database = await _factory!.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: (Database db, int version) async {
          await _createSchema(db);
        },
      ),
    );
    return _database!;
  }

  Future<void> init() async {
    await database;
  }

  DatabaseFactory _createDatabaseFactory() {
    if (kIsWeb) {
      throw UnsupportedError('SQLite storage is not supported on web.');
    }

    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  Future<String> _resolveDatabasePath(DatabaseFactory factory) async {
    if (_isTestEnvironment) {
      return inMemoryDatabasePath;
    }

    final String databasesPath = await factory.getDatabasesPath();
    return p.join(databasesPath, _dbName);
  }

  bool get _isTestEnvironment {
    return Platform.environment.containsKey('FLUTTER_TEST');
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $exercisesTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $workoutsTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        payload_json TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $settingsTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }
}

