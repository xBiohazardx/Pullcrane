enum ExerciseMode { reps, duration }

enum TargetForceMode { absoluteKg, relativePercent }

enum ExerciseHand { left, right }

class Exercise {
  Exercise({
    required this.id,
    required this.name,
    required this.description,
    required this.mode,
    this.reps,
    this.durationSeconds,
    required this.defaultRestSeconds,
    this.targetForceMode = TargetForceMode.absoluteKg,
    this.targetForceValue = 10,
    this.isSideSwitching = false,
    this.startingHand = ExerciseHand.left,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String description;
  final ExerciseMode mode;
  final int? reps;
  final int? durationSeconds;
  final int defaultRestSeconds;
  final TargetForceMode targetForceMode;
  final double targetForceValue;
  final bool isSideSwitching;
  final ExerciseHand startingHand;
  final bool isDefault;

  Exercise copyWith({
    String? id,
    String? name,
    String? description,
    ExerciseMode? mode,
    int? reps,
    int? durationSeconds,
    int? defaultRestSeconds,
    TargetForceMode? targetForceMode,
    double? targetForceValue,
    bool? isSideSwitching,
    ExerciseHand? startingHand,
    bool? isDefault,
  }) {
    return Exercise(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      mode: mode ?? this.mode,
      reps: reps ?? this.reps,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      defaultRestSeconds: defaultRestSeconds ?? this.defaultRestSeconds,
      targetForceMode: targetForceMode ?? this.targetForceMode,
      targetForceValue: targetForceValue ?? this.targetForceValue,
      isSideSwitching: isSideSwitching ?? this.isSideSwitching,
      startingHand: startingHand ?? this.startingHand,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'mode': mode.name,
      'reps': reps,
      'durationSeconds': durationSeconds,
      'defaultRestSeconds': defaultRestSeconds,
      'targetForceMode': targetForceMode.name,
      'targetForceValue': targetForceValue,
      'isSideSwitching': isSideSwitching,
      'startingHand': startingHand.name,
      'isDefault': isDefault,
    };
  }

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      mode: ExerciseMode.values.byName(json['mode'] as String),
      reps: json['reps'] as int?,
      durationSeconds: json['durationSeconds'] as int?,
      defaultRestSeconds: json['defaultRestSeconds'] as int? ?? 60,
      targetForceMode: json['targetForceMode'] != null
          ? TargetForceMode.values.byName(json['targetForceMode'] as String)
          : TargetForceMode.absoluteKg,
      targetForceValue: (json['targetForceValue'] as num?)?.toDouble() ?? 10,
      isSideSwitching: json['isSideSwitching'] as bool? ?? false,
      startingHand: json['startingHand'] != null
          ? ExerciseHand.values.byName(json['startingHand'] as String)
          : ExerciseHand.left,
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}

