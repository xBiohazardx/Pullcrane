import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String exercisesTable = 'exercises';
  static const String exerciseHistoryTable = 'exercise_history';
  static const String workoutsTable = 'workouts';
  static const String workoutEntriesTable = 'workout_entries';
  static const String settingsTable = 'app_settings';

  static const String _dbName = 'pullcrane.db';
  static const int _dbVersion = 2;

  Database? _database;

  Future<void> reloadDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    await database; // This will trigger a fresh initialization
  }

  Future<String> _getDatabasePath(String defaultInternalPath) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? externalDir = prefs.getString('external_db_dir');

    if (externalDir != null && externalDir.isNotEmpty) {
      final Directory extDir = Directory(externalDir);
      if (await extDir.exists()) {
        final String externalDbPath = p.join(externalDir, _dbName);
        final File externalDbFile = File(externalDbPath);
        
        if (!await externalDbFile.exists()) {
          // Database doesn't exist externally yet, so let's copy the internal one if it exists
          final File internalDbFile = File(defaultInternalPath);
          if (await internalDbFile.exists()) {
            await internalDbFile.copy(externalDbPath);
          }
        }
        return externalDbPath;
      }
    }
    
    // Fallback to internal
    return defaultInternalPath;
  }

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    if (_usesSqflitePlugin) {
      final String internalPath = await _resolveMobileDatabasePath();
      final String finalPath = await _getDatabasePath(internalPath);
      
      _database = await sqflite.openDatabase(
        finalPath,
        version: _dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (sqflite.Database db, int version) async {
          await _createSchema(db);
        },
        onUpgrade: (sqflite.Database db, int oldVersion, int newVersion) async {
          await _createSchema(db);
        },
      );
      return _database!;
    }

    final DatabaseFactory factory = _createFfiDatabaseFactory();
    final String internalPath = await _resolveFfiDatabasePath(factory);
    final String finalPath = await _getDatabasePath(internalPath);

    _database = await factory.openDatabase(
      finalPath,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await _createSchema(db);
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
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
    await db.execute('DROP TABLE IF EXISTS $workoutEntriesTable');
    await db.execute('DROP TABLE IF EXISTS $workoutsTable');
    await db.execute('DROP TABLE IF EXISTS $exerciseHistoryTable');
    await db.execute('DROP TABLE IF EXISTS $exercisesTable');
    await db.execute('DROP TABLE IF EXISTS $settingsTable');

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
        is_side_switching INTEGER NOT NULL,
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
        mode TEXT NOT NULL,
        reps INTEGER,
        duration_seconds INTEGER,
        rest_seconds INTEGER NOT NULL,
        target_force_mode TEXT NOT NULL,
        target_force_value REAL NOT NULL,
        starting_hand TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        FOREIGN KEY(workout_id) REFERENCES $workoutsTable(id) ON DELETE CASCADE,
        FOREIGN KEY(exercise_id) REFERENCES $exercisesTable(id) ON DELETE CASCADE
      )
    ''');
  }
}
