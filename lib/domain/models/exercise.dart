enum ExerciseMode { reps, duration }

enum TargetForceMode { absoluteKg, relativePercent }

enum ExerciseHand { left, right }

class MaxLiftRecord {
  MaxLiftRecord({
    required this.date,
    required this.leftKg,
    required this.rightKg,
  });

  final DateTime date;
  final int leftKg;
  final int rightKg;

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'leftKg': leftKg,
      'rightKg': rightKg,
    };
  }

  factory MaxLiftRecord.fromJson(Map<String, dynamic> json) {
    return MaxLiftRecord(
      date: DateTime.parse(json['date'] as String),
      leftKg: json['leftKg'] as int,
      rightKg: json['rightKg'] as int,
    );
  }
}

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
    this.maxLiftLeftKg = 0,
    this.maxLiftRightKg = 0,
    this.maxLiftHistory = const [],
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
  final int maxLiftLeftKg;
  final int maxLiftRightKg;
  final List<MaxLiftRecord> maxLiftHistory;
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
    int? maxLiftLeftKg,
    int? maxLiftRightKg,
    List<MaxLiftRecord>? maxLiftHistory,
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
      maxLiftLeftKg: maxLiftLeftKg ?? this.maxLiftLeftKg,
      maxLiftRightKg: maxLiftRightKg ?? this.maxLiftRightKg,
      maxLiftHistory: maxLiftHistory ?? this.maxLiftHistory,
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
      'maxLiftLeftKg': maxLiftLeftKg,
      'maxLiftRightKg': maxLiftRightKg,
      'maxLiftHistory': maxLiftHistory.map((r) => r.toJson()).toList(),
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
      maxLiftLeftKg: (json['maxLiftLeftKg'] as num?)?.round() ?? 0,
      maxLiftRightKg: (json['maxLiftRightKg'] as num?)?.round() ?? 0,
      maxLiftHistory:
          (json['maxLiftHistory'] as List<dynamic>?)
              ?.map((e) => MaxLiftRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
}
