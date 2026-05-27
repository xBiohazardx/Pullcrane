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
    this.isSideSwitching = false,
    this.maxLiftLeftKg = 0,
    this.maxLiftRightKg = 0,
    this.maxLiftHistory = const [],
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String description;
  final bool isSideSwitching;
  final int maxLiftLeftKg;
  final int maxLiftRightKg;
  final List<MaxLiftRecord> maxLiftHistory;
  final bool isDefault;

  Exercise copyWith({
    String? id,
    String? name,
    String? description,
    bool? isSideSwitching,
    int? maxLiftLeftKg,
    int? maxLiftRightKg,
    List<MaxLiftRecord>? maxLiftHistory,
    bool? isDefault,
  }) {
    return Exercise(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isSideSwitching: isSideSwitching ?? this.isSideSwitching,
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
      'isSideSwitching': isSideSwitching,
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
      isSideSwitching: json['isSideSwitching'] as bool? ?? false,
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
