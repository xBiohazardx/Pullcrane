class WorkoutExerciseEntry {
  WorkoutExerciseEntry({
    required this.exerciseId,
    required this.sets,
    this.restOverrideSeconds,
  });

  final String exerciseId;
  final int sets;
  final int? restOverrideSeconds;

  Map<String, dynamic> toJson() {
    return {
      'exerciseId': exerciseId,
      'sets': sets,
      'restOverrideSeconds': restOverrideSeconds,
    };
  }

  factory WorkoutExerciseEntry.fromJson(Map<String, dynamic> json) {
    return WorkoutExerciseEntry(
      exerciseId: json['exerciseId'] as String,
      sets: json['sets'] as int,
      restOverrideSeconds: json['restOverrideSeconds'] as int?,
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

