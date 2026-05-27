import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();

  static const String exercisesTable = 'exercises';
  static const String exerciseHistoryTable = 'exercise_history';
  static const String workoutsTable = 'workouts';
  static const String workoutEntriesTable = 'workout_entries';
  static const String settingsTable = 'app_settings';

  static const String _dbName = 'pullcrane.db';
  static const int _dbVersion = 1;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    if (_usesSqflitePlugin) {
      final String path = await _resolveMobileDatabasePath();
      _database = await sqflite.openDatabase(
        path,
        version: _dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (sqflite.Database db, int version) async {
          await _createSchema(db);
        },
      );
      return _database!;
    }

    final DatabaseFactory factory = _createFfiDatabaseFactory();
    final String path = await _resolveFfiDatabasePath(factory);
    _database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
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

  bool get _usesSqflitePlugin {
    if (kIsWeb) {
      return false;
    }
    return Platform.isAndroid || Platform.isIOS;
  }

  DatabaseFactory _createFfiDatabaseFactory() {
    if (kIsWeb) {
      throw UnsupportedError('SQLite storage is not supported on web.');
    }

    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  Future<String> _resolveMobileDatabasePath() async {
    final String databasesPath = await sqflite.getDatabasesPath();
    return p.join(databasesPath, _dbName);
  }

  Future<String> _resolveFfiDatabasePath(DatabaseFactory factory) async {
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
      CREATE TABLE IF NOT EXISTS $settingsTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        force_threshold_kg INTEGER NOT NULL,
        user_max_lift_kg INTEGER NOT NULL,
        target_hysteresis_kg INTEGER NOT NULL,
        enable_target_haptics INTEGER NOT NULL,
        require_zero_before_set_start INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $exercisesTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        mode TEXT NOT NULL,
        reps INTEGER,
        duration_seconds INTEGER,
        default_rest_seconds INTEGER NOT NULL,
        target_force_mode TEXT NOT NULL,
        target_force_value REAL NOT NULL,
        is_side_switching INTEGER NOT NULL,
        starting_hand TEXT NOT NULL,
        max_lift_left_kg INTEGER NOT NULL,
        max_lift_right_kg INTEGER NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $exerciseHistoryTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        exercise_id TEXT NOT NULL,
        date TEXT NOT NULL,
        left_kg INTEGER NOT NULL,
        right_kg INTEGER NOT NULL,
        FOREIGN KEY(exercise_id) REFERENCES $exercisesTable(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $workoutsTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $workoutEntriesTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_id TEXT NOT NULL,
        exercise_id TEXT NOT NULL,
        sets INTEGER NOT NULL,
        rest_override_seconds INTEGER,
        order_index INTEGER NOT NULL,
        FOREIGN KEY(workout_id) REFERENCES $workoutsTable(id) ON DELETE CASCADE,
        FOREIGN KEY(exercise_id) REFERENCES $exercisesTable(id) ON DELETE CASCADE
      )
    ''');
  }
}
