import 'package:pullcrane/domain/models/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalSettingsRepository {
  static const String _forceThresholdKey = 'settings.forceThresholdKg';
  static const String _userMaxLiftKey = 'settings.userMaxLiftKg';
  static const String _targetHysteresisKey = 'settings.targetHysteresisKg';
  static const String _targetHapticsKey = 'settings.enableTargetHaptics';
  static const String _requireZeroKey = 'settings.requireZeroBeforeSetStart';

  Future<AppSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return AppSettings(
      forceThresholdKg:
          prefs.getInt(_forceThresholdKey) ?? AppSettings.defaults.forceThresholdKg,
      userMaxLiftKg:
          prefs.getInt(_userMaxLiftKey) ?? AppSettings.defaults.userMaxLiftKg,
      targetHysteresisKg:
          prefs.getInt(_targetHysteresisKey) ?? AppSettings.defaults.targetHysteresisKg,
      enableTargetHaptics:
          prefs.getBool(_targetHapticsKey) ?? AppSettings.defaults.enableTargetHaptics,
      requireZeroBeforeSetStart:
          prefs.getBool(_requireZeroKey) ??
              AppSettings.defaults.requireZeroBeforeSetStart,
    );
  }

  Future<void> save(AppSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_forceThresholdKey, settings.forceThresholdKg);
    await prefs.setInt(_userMaxLiftKey, settings.userMaxLiftKg);
    await prefs.setInt(_targetHysteresisKey, settings.targetHysteresisKg);
    await prefs.setBool(_targetHapticsKey, settings.enableTargetHaptics);
    await prefs.setBool(
      _requireZeroKey,
      settings.requireZeroBeforeSetStart,
    );
  }
}


