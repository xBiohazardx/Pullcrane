import 'package:pullcrane/data/local/local_database.dart';
import 'package:pullcrane/domain/models/app_settings.dart';
import 'package:sqflite_common/sqlite_api.dart';

class LocalSettingsRepository {
  static const String _forceThresholdKey = 'settings.forceThresholdKg';
  static const String _userMaxLiftKey = 'settings.userMaxLiftKg';
  static const String _targetHysteresisKey = 'settings.targetHysteresisKg';
  static const String _targetHapticsKey = 'settings.enableTargetHaptics';
  static const String _requireZeroKey = 'settings.requireZeroBeforeSetStart';

  Future<AppSettings> load() async {
    final Database db = await LocalDatabase.instance.database;
    final Map<String, String> settings = await _loadAllSettings(db);

    return AppSettings(
      forceThresholdKg:
          int.tryParse(settings[_forceThresholdKey] ?? '') ?? AppSettings.defaults.forceThresholdKg,
      userMaxLiftKg:
          int.tryParse(settings[_userMaxLiftKey] ?? '') ?? AppSettings.defaults.userMaxLiftKg,
      targetHysteresisKg: int.tryParse(settings[_targetHysteresisKey] ?? '') ??
          AppSettings.defaults.targetHysteresisKg,
      enableTargetHaptics: _parseBool(settings[_targetHapticsKey]) ??
          AppSettings.defaults.enableTargetHaptics,
      requireZeroBeforeSetStart: _parseBool(settings[_requireZeroKey]) ??
          AppSettings.defaults.requireZeroBeforeSetStart,
    );
  }

  Future<void> save(AppSettings settings) async {
    final Database db = await LocalDatabase.instance.database;
    await db.transaction((Transaction txn) async {
      await _upsert(txn, _forceThresholdKey, settings.forceThresholdKg.toString());
      await _upsert(txn, _userMaxLiftKey, settings.userMaxLiftKg.toString());
      await _upsert(txn, _targetHysteresisKey, settings.targetHysteresisKg.toString());
      await _upsert(txn, _targetHapticsKey, settings.enableTargetHaptics.toString());
      await _upsert(
        txn,
        _requireZeroKey,
        settings.requireZeroBeforeSetStart.toString(),
      );
    });
  }

  Future<Map<String, String>> _loadAllSettings(Database db) async {
    final List<Map<String, Object?>> rows = await db.query(LocalDatabase.settingsTable);
    return <String, String>{
      for (final Map<String, Object?> row in rows)
        row['key']! as String: row['value']! as String,
    };
  }

  bool? _parseBool(String? raw) {
    if (raw == null) {
      return null;
    }
    if (raw == 'true') {
      return true;
    }
    if (raw == 'false') {
      return false;
    }
    return null;
  }

  Future<void> _upsert(Transaction txn, String key, String value) async {
    await txn.insert(
      LocalDatabase.settingsTable,
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
