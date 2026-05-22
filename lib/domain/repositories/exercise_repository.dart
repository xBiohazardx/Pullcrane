import 'package:pullcrane/domain/models/exercise.dart';

abstract class ExerciseRepository {
  Future<void> init();
  Future<List<Exercise>> listExercises();
  Future<void> saveExercise(Exercise exercise);
  Future<void> deleteExercise(String id);
}

