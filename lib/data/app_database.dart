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
  static const String workoutSessionsTable = 'workout_sessions';
  static const String setLogsTable = 'set_logs';

  static const String _dbName = 'pullcrane.db';

  /// Current schema version. Public so tests can open databases at this
  /// version using [onCreateDatabase] / [onUpgradeDatabase].
  static const int dbVersion = 4;

  Database? _database;

  /// Whether the configured external directory was unavailable when the
  /// database was last opened, causing a fallback to internal storage.
  /// The UI can read this to warn the user instead of failing silently.
  bool externalDirectoryMissing = false;

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
        externalDirectoryMissing = false;
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
      // Configured external directory is gone (e.g. SD card removed):
      // fall back to internal but let the UI warn about it.
      externalDirectoryMissing = true;
    } else {
      externalDirectoryMissing = false;
    }

    // Fallback to internal
    return defaultInternalPath;
  }

  /// Copies the externally stored database back over the internal one so no
  /// data is orphaned when external storage is disabled. Does nothing when
  /// no external database exists.
  Future<void> copyExternalToInternal() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? externalDir = prefs.getString('external_db_dir');
    if (externalDir == null || externalDir.isEmpty) {
      return;
    }

    final File externalFile = File(p.join(externalDir, _dbName));
    if (!await externalFile.exists()) {
      return;
    }

    // Close the live database before overwriting the internal file.
    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    final String internalPath = _usesSqflitePlugin
        ? await _resolveMobileDatabasePath()
        : await _resolveFfiDatabasePath(_createFfiDatabaseFactory());
    await externalFile.copy(internalPath);
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
        version: dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => onCreateDatabase(db),
        onUpgrade: onUpgradeDatabase,
      );
      return _database!;
    }

    final DatabaseFactory factory = _createFfiDatabaseFactory();
    final String internalPath = await _resolveFfiDatabasePath(factory);
    final String finalPath = await _getDatabasePath(internalPath);

    _database = await factory.openDatabase(
      finalPath,
      options: OpenDatabaseOptions(
        version: dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => onCreateDatabase(db),
        onUpgrade: onUpgradeDatabase,
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

  /// Creates the current (v4) schema on a fresh database.
  ///
  /// Never DROPs anything here: this runs only on newly created databases.
  static Future<void> onCreateDatabase(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $settingsTable (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        force_threshold_kg INTEGER NOT NULL,
        target_hysteresis_kg INTEGER NOT NULL,
        enable_target_haptics INTEGER NOT NULL,
        require_zero_before_set_start INTEGER NOT NULL,
        max_force_kg INTEGER NOT NULL DEFAULT 200
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $exercisesTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        is_side_switching INTEGER NOT NULL,
        max_lift_left_kg INTEGER NOT NULL,
        max_lift_right_kg INTEGER NOT NULL
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

    await _createHistorySchema(db);
  }

  /// History tables (v4). Session rows deliberately have no foreign key to
  /// workouts/exercises (only denormalized names) so history survives
  /// deletion of the workout or exercise it refers to.
  static Future<void> _createHistorySchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $workoutSessionsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        workout_id TEXT NOT NULL,
        workout_name TEXT NOT NULL,
        started_at TEXT NOT NULL,
        finished_at TEXT NOT NULL,
        completed INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $setLogsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        entry_index INTEGER NOT NULL,
        set_number INTEGER NOT NULL,
        exercise_id TEXT NOT NULL,
        exercise_name TEXT NOT NULL,
        hand TEXT,
        target_force_kg INTEGER NOT NULL,
        planned_duration_seconds INTEGER NOT NULL,
        planned_reps INTEGER NOT NULL,
        actual_duration_seconds INTEGER NOT NULL,
        peak_force_kg INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES $workoutSessionsTable(id) ON DELETE CASCADE
      )
    ''');
  }

  /// Runs incremental migrations. Each step must preserve existing user data.
  ///
  /// Historical note: v1 -> v2 was destructive (drop + recreate), so any
  /// database that has ever been opened by a v2 app is already v2-shaped.
  /// The v1 exercises table only differs by an extra `is_default` column,
  /// which is harmless to keep, so v1 -> v2 needs no migration step.
  static Future<void> onUpgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 3) {
      await _migrateToV3(db);
    }
    if (oldVersion < 4) {
      await _createHistorySchema(db);
    }
  }

  /// v2 -> v3: rebuild the settings table without the dead
  /// `user_max_lift_kg` column and add `max_force_kg`.
  ///
  /// The settings table is not referenced by any foreign key, so dropping
  /// it is safe even with `PRAGMA foreign_keys = ON`.
  static Future<void> _migrateToV3(Database db) async {
    await db.execute('''
      CREATE TABLE app_settings_v3 (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        force_threshold_kg INTEGER NOT NULL,
        target_hysteresis_kg INTEGER NOT NULL,
        enable_target_haptics INTEGER NOT NULL,
        require_zero_before_set_start INTEGER NOT NULL,
        max_force_kg INTEGER NOT NULL DEFAULT 200
      )
    ''');
    await db.execute('''
      INSERT INTO app_settings_v3 (
        id,
        force_threshold_kg,
        target_hysteresis_kg,
        enable_target_haptics,
        require_zero_before_set_start
      )
      SELECT
        id,
        force_threshold_kg,
        target_hysteresis_kg,
        enable_target_haptics,
        require_zero_before_set_start
      FROM $settingsTable
    ''');
    await db.execute('DROP TABLE $settingsTable');
    await db.execute('ALTER TABLE app_settings_v3 RENAME TO $settingsTable');
  }
}
