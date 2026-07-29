class AppSettings {
  const AppSettings({
    required this.forceThresholdKg,
    required this.targetHysteresisKg,
    required this.enableTargetHaptics,
    required this.requireZeroBeforeSetStart,
    required this.maxForceKg,
  });

  static const AppSettings defaults = AppSettings(
    forceThresholdKg: 10,
    targetHysteresisKg: 2,
    enableTargetHaptics: true,
    requireZeroBeforeSetStart: true,
    maxForceKg: 200,
  );

  final int forceThresholdKg;
  final int targetHysteresisKg;
  final bool enableTargetHaptics;
  final bool requireZeroBeforeSetStart;

  /// Upper bound for displayed/target force. Real scale readings are clamped
  /// to this value, so it should comfortably exceed the user's heaviest lift.
  final int maxForceKg;

  AppSettings copyWith({
    int? forceThresholdKg,
    int? targetHysteresisKg,
    bool? enableTargetHaptics,
    bool? requireZeroBeforeSetStart,
    int? maxForceKg,
  }) {
    return AppSettings(
      forceThresholdKg: forceThresholdKg ?? this.forceThresholdKg,
      targetHysteresisKg: targetHysteresisKg ?? this.targetHysteresisKg,
      enableTargetHaptics: enableTargetHaptics ?? this.enableTargetHaptics,
      requireZeroBeforeSetStart:
          requireZeroBeforeSetStart ?? this.requireZeroBeforeSetStart,
      maxForceKg: maxForceKg ?? this.maxForceKg,
    );
  }
}
