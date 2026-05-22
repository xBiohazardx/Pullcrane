class AppSettings {
  const AppSettings({
    required this.forceThresholdKg,
    required this.userMaxLiftKg,
    required this.targetHysteresisKg,
    required this.enableTargetHaptics,
    required this.requireZeroBeforeSetStart,
  });

  static const AppSettings defaults = AppSettings(
    forceThresholdKg: 10,
    userMaxLiftKg: 60,
    targetHysteresisKg: 2,
    enableTargetHaptics: true,
    requireZeroBeforeSetStart: true,
  );

  final int forceThresholdKg;
  final int userMaxLiftKg;
  final int targetHysteresisKg;
  final bool enableTargetHaptics;
  final bool requireZeroBeforeSetStart;

  AppSettings copyWith({
    int? forceThresholdKg,
    int? userMaxLiftKg,
    int? targetHysteresisKg,
    bool? enableTargetHaptics,
    bool? requireZeroBeforeSetStart,
  }) {
    return AppSettings(
      forceThresholdKg: forceThresholdKg ?? this.forceThresholdKg,
      userMaxLiftKg: userMaxLiftKg ?? this.userMaxLiftKg,
      targetHysteresisKg: targetHysteresisKg ?? this.targetHysteresisKg,
      enableTargetHaptics: enableTargetHaptics ?? this.enableTargetHaptics,
      requireZeroBeforeSetStart:
          requireZeroBeforeSetStart ?? this.requireZeroBeforeSetStart,
    );
  }
}


