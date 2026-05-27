import 'package:pullcrane/domain/models/exercise.dart';

class WorkoutExerciseEntry {
  WorkoutExerciseEntry({
    required this.exerciseId,
    required this.sets,
    required this.mode,
    this.reps,
    this.durationSeconds,
    required this.restSeconds,
    this.targetForceMode = TargetForceMode.absoluteKg,
    this.targetForceValue = 10,
    this.startingHand = ExerciseHand.left,
  });

  final String exerciseId;
  final int sets;
  final ExerciseMode mode;
  final int? reps;
  final int? durationSeconds;
  final int restSeconds;
  final TargetForceMode targetForceMode;
  final double targetForceValue;
  final ExerciseHand startingHand;

  Map<String, dynamic> toJson() {
    return {
      'exerciseId': exerciseId,
      'sets': sets,
      'mode': mode.name,
      'reps': reps,
      'durationSeconds': durationSeconds,
      'restSeconds': restSeconds,
      'targetForceMode': targetForceMode.name,
      'targetForceValue': targetForceValue,
      'startingHand': startingHand.name,
    };
  }

  factory WorkoutExerciseEntry.fromJson(Map<String, dynamic> json) {
    return WorkoutExerciseEntry(
      exerciseId: json['exerciseId'] as String,
      sets: json['sets'] as int,
      mode: ExerciseMode.values.byName(json['mode'] as String),
      reps: json['reps'] as int?,
      durationSeconds: json['durationSeconds'] as int?,
      restSeconds: json['restSeconds'] as int? ?? 60,
      targetForceMode: json['targetForceMode'] != null
          ? TargetForceMode.values.byName(json['targetForceMode'] as String)
          : TargetForceMode.absoluteKg,
      targetForceValue: (json['targetForceValue'] as num?)?.toDouble() ?? 10,
      startingHand: json['startingHand'] != null
          ? ExerciseHand.values.byName(json['startingHand'] as String)
          : ExerciseHand.left,
    );
  }
}

class Workout {
  Workout({
    required this.id,
    required this.name,
    required this.entries,
  });

  final String id;
  final String name;
  final List<WorkoutExerciseEntry> entries;

  Workout copyWith({
    String? id,
    String? name,
    List<WorkoutExerciseEntry>? entries,
  }) {
    return Workout(
      id: id ?? this.id,
      name: name ?? this.name,
      entries: entries ?? this.entries,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'entries': entries.map((entry) => entry.toJson()).toList(),
    };
  }

  factory Workout.fromJson(Map<String, dynamic> json) {
    return Workout(
      id: json['id'] as String,
      name: json['name'] as String,
      entries: (json['entries'] as List<dynamic>? ?? <dynamic>[])
          .map((entry) =>
              WorkoutExerciseEntry.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }
}

