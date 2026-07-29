import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pullcrane/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The settings table schema as shipped in v2 (with the dead
/// `user_max_lift_kg` column).
const String _v2SettingsDdl = '''
  CREATE TABLE app_settings (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    force_threshold_kg INTEGER NOT NULL,
    user_max_lift_kg INTEGER NOT NULL,
    target_hysteresis_kg INTEGER NOT NULL,
    enable_target_haptics INTEGER NOT NULL,
    require_zero_before_set_start INTEGER NOT NULL
  )
''';

const String _exerciseHistoryDdl = '''
  CREATE TABLE exercise_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    exercise_id TEXT NOT NULL,
    date TEXT NOT NULL,
    left_kg INTEGER NOT NULL,
    right_kg INTEGER NOT NULL,
    FOREIGN KEY(exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
  )
''';

const String _workoutsDdl = '''
  CREATE TABLE workouts (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL
  )
''';

const String _workoutEntriesDdl = '''
  CREATE TABLE workout_entries (
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
    FOREIGN KEY(workout_id) REFERENCES workouts(id) ON DELETE CASCADE,
    FOREIGN KEY(exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
  )
''';

String _exercisesDdl({required bool withIsDefault}) => '''
  CREATE TABLE exercises (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    is_side_switching INTEGER NOT NULL,
    max_lift_left_kg INTEGER NOT NULL,
    max_lift_right_kg INTEGER NOT NULL
    ${withIsDefault ? ', is_default INTEGER NOT NULL DEFAULT 0' : ''}
  )
''';

Future<void> _seedData(Database db) async {
  await db.insert('app_settings', {
    'id': 1,
    'force_threshold_kg': 12,
    'user_max_lift_kg': 75,
    'target_hysteresis_kg': 3,
    'enable_target_haptics': 1,
    'require_zero_before_set_start': 0,
  });
  await db.insert('exercises', {
    'id': 'ex1',
    'name': 'Hang',
    'description': 'Two-arm hang',
    'is_side_switching': 1,
    'max_lift_left_kg': 50,
    'max_lift_right_kg': 55,
  });
  await db.insert('exercise_history', {
    'exercise_id': 'ex1',
    'date': '2026-07-01T10:00:00.000',
    'left_kg': 48,
    'right_kg': 53,
  });
  await db.insert('workouts', {'id': 'w1', 'name': 'Strength'});
  await db.insert('workout_entries', {
    'workout_id': 'w1',
    'exercise_id': 'ex1',
    'sets': 3,
    'mode': 'duration',
    'reps': null,
    'duration_seconds': 7,
    'rest_seconds': 180,
    'target_force_mode': 'relativePercent',
    'target_force_value': 85.0,
    'starting_hand': 'left',
    'order_index': 0,
  });
}

Future<List<String>> _columnNames(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toList();
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pullcrane_migration_');
    dbPath = p.join(tempDir.path, 'pullcrane.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<Database> createOldDatabase({
    required int version,
    required bool exercisesWithIsDefault,
  }) {
    return databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) async {
          await db.execute(_v2SettingsDdl);
          await db.execute(
            _exercisesDdl(withIsDefault: exercisesWithIsDefault),
          );
          await db.execute(_exerciseHistoryDdl);
          await db.execute(_workoutsDdl);
          await db.execute(_workoutEntriesDdl);
          await _seedData(db);
        },
      ),
    );
  }

  Future<Database> openWithAppCallbacks() {
    return databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: AppDatabase.dbVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) => AppDatabase.onCreateDatabase(db),
        onUpgrade: AppDatabase.onUpgradeDatabase,
      ),
    );
  }

  Future<void> expectDataPreserved(Database db) async {
    final settings = await db.query('app_settings');
    expect(settings, hasLength(1));
    expect(settings.first['force_threshold_kg'], 12);
    expect(settings.first['target_hysteresis_kg'], 3);
    expect(settings.first['enable_target_haptics'], 1);
    expect(settings.first['require_zero_before_set_start'], 0);
    expect(settings.first['max_force_kg'], 200);

    final settingsColumns = await _columnNames(db, 'app_settings');
    expect(settingsColumns, isNot(contains('user_max_lift_kg')));
    expect(settingsColumns, contains('max_force_kg'));

    final exercises = await db.query('exercises');
    expect(exercises, hasLength(1));
    expect(exercises.first['name'], 'Hang');
    expect(exercises.first['max_lift_right_kg'], 55);

    final history = await db.query('exercise_history');
    expect(history, hasLength(1));
    expect(history.first['left_kg'], 48);

    final workouts = await db.query('workouts');
    expect(workouts, hasLength(1));
    expect(workouts.first['name'], 'Strength');

    final entries = await db.query('workout_entries');
    expect(entries, hasLength(1));
    expect(entries.first['sets'], 3);
    expect(entries.first['target_force_value'], 85.0);

    // v4 history tables exist and start empty after the upgrade.
    expect(await db.query('workout_sessions'), isEmpty);
    expect(await db.query('set_logs'), isEmpty);
  }

  test('v2 -> current preserves all user data and rebuilds settings', () async {
    var db = await createOldDatabase(version: 2, exercisesWithIsDefault: false);
    await db.close();

    db = await openWithAppCallbacks();
    await expectDataPreserved(db);
    await db.close();
  });

  test('v1 -> current preserves all user data', () async {
    var db = await createOldDatabase(version: 1, exercisesWithIsDefault: true);
    await db.close();

    db = await openWithAppCallbacks();
    await expectDataPreserved(db);
    await db.close();
  });

  test('fresh install creates the current schema', () async {
    final db = await openWithAppCallbacks();

    final settingsColumns = await _columnNames(db, 'app_settings');
    expect(settingsColumns, contains('max_force_kg'));
    expect(settingsColumns, isNot(contains('user_max_lift_kg')));

    final exerciseColumns = await _columnNames(db, 'exercises');
    expect(exerciseColumns, isNot(contains('is_default')));

    for (final table in [
      'app_settings',
      'exercises',
      'exercise_history',
      'workouts',
      'workout_entries',
      'workout_sessions',
      'set_logs',
    ]) {
      final rows = await db.query(table);
      expect(rows, isEmpty, reason: '$table should start empty');
    }
    await db.close();
  });
}
