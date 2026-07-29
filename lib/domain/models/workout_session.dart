import 'package:pullcrane/domain/models/set_log.dart';

/// A recorded run of a workout, with the sets that were completed in it.
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.workoutId,
    required this.workoutName,
    required this.startedAt,
    required this.finishedAt,
    required this.completed,
    this.setLogs = const [],
    this.setCount = 0,
  });

  final int id;
  final String workoutId;

  /// Denormalized so history stays readable after the workout is renamed
  /// or deleted.
  final String workoutName;

  final DateTime startedAt;
  final DateTime finishedAt;

  /// True when every entry was completed; false when aborted early.
  final bool completed;

  final List<SetLog> setLogs;

  /// Number of logged sets; populated by list queries that do not load the
  /// logs themselves.
  final int setCount;
}
