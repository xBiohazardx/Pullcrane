import 'package:pullcrane/data/local/local_database.dart';
import 'package:pullcrane/domain/models/app_settings.dart';
import 'package:sqflite_common/sqlite_api.dart';

class LocalSettingsRepository {
  Future<AppSettings> load() async {
    final Database db = await LocalDatabase.instance.database;
    final List<Map<String, Object?>> rows = await db.query(
      LocalDatabase.settingsTable,
      where: 'id = ?',
      whereArgs: [1],
    );

    if (rows.isEmpty) {
      return AppSettings.defaults;
    }

    final row = rows.first;
    return AppSettings(
      forceThresholdKg: row['force_threshold_kg'] as int,
      targetHysteresisKg: row['target_hysteresis_kg'] as int,
      enableTargetHaptics: (row['enable_target_haptics'] as int) == 1,
      requireZeroBeforeSetStart: (row['require_zero_before_set_start'] as int) == 1,
    );
  }

  Future<void> save(AppSettings settings) async {
    final Database db = await LocalDatabase.instance.database;
    await db.insert(
      LocalDatabase.settingsTable,
      {
        'id': 1,
        'force_threshold_kg': settings.forceThresholdKg,
        'user_max_lift_kg': 60, // Dummy value to prevent NOT NULL constraint error on older databases
        'target_hysteresis_kg': settings.targetHysteresisKg,
        'enable_target_haptics': settings.enableTargetHaptics ? 1 : 0,
        'require_zero_before_set_start': settings.requireZeroBeforeSetStart ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
