import 'package:pullcrane/domain/models/workout.dart';

abstract class WorkoutRepository {
  Future<void> init();
  Future<List<Workout>> listWorkouts();
  Future<void> saveWorkout(Workout workout);
  Future<void> deleteWorkout(String id);
}

