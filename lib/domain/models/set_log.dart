import 'package:pullcrane/domain/models/exercise.dart';

/// Record of a single completed set inside a workout session.
///
/// Produced by the workout session engine and persisted by the history
/// store. Pure data, no Flutter dependencies.
class SetLog {
  const SetLog({
    required this.entryIndex,
    required this.setNumber,
    required this.exerciseId,
    required this.exerciseName,
    required this.hand,
    required this.targetForceKg,
    required this.plannedDurationSeconds,
    required this.plannedReps,
    required this.actualDurationSeconds,
    required this.peakForceKg,
    this.sessionStartedAt,
  });

  /// Index of the workout entry within the workout.
  final int entryIndex;

  /// 1-based set number within the entry.
  final int setNumber;

  final String exerciseId;

  /// Denormalized so history stays readable after the exercise is renamed
  /// or deleted.
  final String exerciseName;

  /// The hand that performed the set; null when the exercise is not
  /// side-switching.
  final ExerciseHand? hand;

  /// Resolved target force for this set in kg.
  final int targetForceKg;

  /// Planned hold time for duration sets; 0 for rep sets.
  final int plannedDurationSeconds;

  /// Planned reps for rep sets; 0 for duration sets.
  final int plannedReps;

  /// Wall-clock seconds between set start and completion.
  final int actualDurationSeconds;

  /// Highest force observed while the set was active.
  final int peakForceKg;

  /// Start time of the session this set belongs to. Only populated when the
  /// log was loaded from persistence; the engine leaves it null.
  final DateTime? sessionStartedAt;
}
