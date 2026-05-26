import 'package:pullcrane/data/local/local_database.dart';
import 'package:pullcrane/data/local/local_exercise_repository.dart';
import 'package:pullcrane/data/local/local_settings_repository.dart';
import 'package:pullcrane/data/local/local_workout_repository.dart';

class AppRepositories {
  AppRepositories._();

  static final LocalExerciseRepository exercises = LocalExerciseRepository();
  static final LocalWorkoutRepository workouts = LocalWorkoutRepository();
  static final LocalSettingsRepository settings = LocalSettingsRepository();

  static Future<void> init() async {
    await LocalDatabase.instance.init();
    await exercises.init();
    await workouts.init();
    // Warm settings on startup so first read has persisted values available.
    await settings.load();
  }
}
