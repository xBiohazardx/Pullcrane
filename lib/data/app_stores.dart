import 'package:pullcrane/data/app_database.dart';
import 'package:pullcrane/data/stores/exercise_store.dart';
import 'package:pullcrane/data/stores/session_store.dart';
import 'package:pullcrane/data/stores/settings_store.dart';
import 'package:pullcrane/data/stores/workout_store.dart';

class AppStores {
  AppStores._();

  static final ExerciseStore exercises = ExerciseStore();
  static final WorkoutStore workouts = WorkoutStore();
  static final SettingsStore settings = SettingsStore();
  static final SessionStore sessions = SessionStore();

  static Future<void> init() async {
    await AppDatabase.instance.init();
    await exercises.init();
    await workouts.init();
    // Warm settings on startup so first read has persisted values available.
    await settings.load();
  }

  static Future<void> reload() async {
    await AppDatabase.instance.reloadDatabase();
    await exercises.init();
    await workouts.init();
    await settings.load();
  }
}
