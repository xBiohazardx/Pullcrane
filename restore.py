import re

with open('lib/ui/workouts/active_workout_page.dart', 'r') as f:
    content = f.read()

# 1. Imports
if "import 'animated_instruction_overlay.dart';" not in content:
    content = content.replace(
        "import 'package:pullcrane/ui/bluetooth_connection_sheet.dart';",
        "import 'package:pullcrane/ui/bluetooth_connection_sheet.dart';\nimport 'animated_instruction_overlay.dart';"
    )

# 2. Haptics Fix
old_sync = """  void _syncTargetFeedback(int force) {
    final bool nextInTargetRange = _isInsideTarget(force);
    if (nextInTargetRange == isInTargetRange) {
      return;
    }

    isInTargetRange = nextInTargetRange;"""

new_sync = """  void _syncTargetFeedback(int force) {
    final bool isForceInTarget = _isInsideTarget(force);
    final bool shouldVibrate = (phase == SessionPhase.activeSet || (phase == SessionPhase.waitingForForce && setStartArmed));
    final bool nextInTargetRange = isForceInTarget && shouldVibrate;

    if (nextInTargetRange == isInTargetRange) {
      return;
    }

    isInTargetRange = nextInTargetRange;"""
content = content.replace(old_sync, new_sync)

sync_injects = [
    (
"""      setState(() {
        phase = SessionPhase.activeSet;
        setStartArmed = false;
      });""",
"""      setState(() {
        phase = SessionPhase.activeSet;
        setStartArmed = false;
      });
      _syncTargetFeedback(currentForce);"""
    ),
    (
"""    setState(() {
      phase = SessionPhase.activeSet;
    });""",
"""    setState(() {
      phase = SessionPhase.activeSet;
    });
    _syncTargetFeedback(currentForce);"""
    ),
    (
"""    setState(() {
      remainingRestSeconds = effectiveRestSeconds;
      phase = SessionPhase.resting;
      suggestedSwitchHand = switchTarget;
      setStartArmed = false;
    });""",
"""    setState(() {
      remainingRestSeconds = effectiveRestSeconds;
      phase = SessionPhase.resting;
      suggestedSwitchHand = switchTarget;
      setStartArmed = false;
    });
    _syncTargetFeedback(currentForce);"""
    ),
    (
"""      setState(() {
        phase = SessionPhase.finished;
        suggestedSwitchHand = null;
        activeHand = null;
        pendingHandInSet = null;
        setStartArmed = false;
      });""",
"""      setState(() {
        phase = SessionPhase.finished;
        suggestedSwitchHand = null;
        activeHand = null;
        pendingHandInSet = null;
        setStartArmed = false;
      });
      _syncTargetFeedback(currentForce);"""
    ),
    (
"""    setState(() {
      currentEntryIndex++;
      currentSet = 1;
      suggestedSwitchHand = null;
      activeHand = null;
      pendingHandInSet = null;
      setStartArmed = false;
    });
    _prepareCurrentSet();""",
"""    setState(() {
      currentEntryIndex++;
      currentSet = 1;
      suggestedSwitchHand = null;
      activeHand = null;
      pendingHandInSet = null;
      setStartArmed = false;
    });
    _prepareCurrentSet();
    _syncTargetFeedback(currentForce);"""
    )
]

for old, new in sync_injects:
    content = content.replace(old, new)


# 3. UI logic
action_logic = """
    final int targetMinForce = _targetMinForceKg(exercise, entry);
    final int targetMaxForce = _targetMaxForceKg(exercise, entry);

    String actionLabel = 'Target';
    String actionValue = '';
    Color? actionColor;

    if (phase == SessionPhase.activeSet) {
      if (entry?.mode == ExerciseMode.duration) {
        actionLabel = 'Hold';
        actionValue = '${remainingSetSeconds}s';
      } else {
        actionLabel = 'Target';
        actionValue = '${entry?.reps ?? 0} Reps';
      }
    } else if (phase == SessionPhase.resting) {
      actionLabel = 'Rest';
      actionValue = '${remainingRestSeconds}s';
      actionColor = Colors.orange;
    } else if (phase == SessionPhase.waitingForForce) {
      actionLabel = 'Target';
      actionValue = entry?.mode == ExerciseMode.duration
          ? '${entry?.durationSeconds ?? 0}s'
          : '${entry?.reps ?? 0} Reps';
    } else {
      actionLabel = 'Status';
      actionValue = 'Done';
    }
"""
content = content.replace(
    "    final int targetMinForce = _targetMinForceKg(exercise, entry);\n    final int targetMaxForce = _targetMaxForceKg(exercise, entry);",
    action_logic
)

old_force = """              Text(
                'Force: ${currentForce}kg',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isInTargetRange ? Colors.green : null,
                ),
              ),
              const SizedBox(height: 16),"""
content = content.replace(old_force, "")

# Hand fix
old_hand = """                          if (activeHandForUi != null) ...[
                            const SizedBox(height: 4),
                            Text('Active hand: ${_handLabel(activeHandForUi)}'),
                          ],"""
new_hand = """                          if (activeHandForUi != null) ...[
                            const SizedBox(height: 4),
                            Visibility(
                              visible: phase != SessionPhase.resting,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: Text('Active hand: ${_handLabel(activeHandForUi)}'),
                            ),
                          ],"""
content = content.replace(old_hand, new_hand)

# Dashboard and Overlay replacement
old_chart_block = """                          Text(
                            entry.mode == ExerciseMode.duration
                                ? 'Hold ${entry.durationSeconds ?? 0}s'
                                : '${entry.reps ?? 0} reps',
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: ForceChart(
                              dataPoints: dataPoints,
                              chartMaxForce: maxForceKg,
                              targetMinForce: targetMinForce,
                              targetMaxForce: targetMaxForce,
                              showTargetArea: phase != SessionPhase.resting,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (phase == SessionPhase.waitingForForce)
                            Text(
                              setStartArmed
                                  ? 'Apply at least ${widget.forceThresholdKg} kg to start the set.'
                                  : 'Release to 0 kg first, then apply at least ${widget.forceThresholdKg} kg to start.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          if (phase == SessionPhase.activeSet &&
                              entry.mode == ExerciseMode.duration)
                            Text(
                              'Remaining hold: $remainingSetSeconds s',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          if (phase == SessionPhase.resting)
                            Text(
                              'Rest: $remainingRestSeconds s',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),"""

new_chart_block = """                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('LIVE FORCE', style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
                                    Text(
                                      '${currentForce}kg',
                                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                        color: isInTargetRange ? Colors.green : null,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(actionLabel.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
                                    Text(
                                      actionValue,
                                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                        color: actionColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Stack(
                              children: [
                                ForceChart(
                                  dataPoints: dataPoints,
                                  chartMaxForce: maxForceKg,
                                  targetMinForce: targetMinForce,
                                  targetMaxForce: targetMaxForce,
                                  showTargetArea: phase != SessionPhase.resting,
                                ),
                                AnimatedInstructionOverlay(
                                  mainText: (phase == SessionPhase.waitingForForce && setStartArmed)
                                      ? 'PULL'
                                      : 'RELEASE',
                                  subText: activeHandForUi != null
                                      ? '${_handLabel(activeHandForUi)} Hand'
                                      : null,
                                  backgroundColor: (phase == SessionPhase.waitingForForce && setStartArmed)
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : Theme.of(context).colorScheme.secondaryContainer,
                                  textColor: (phase == SessionPhase.waitingForForce && setStartArmed)
                                      ? Theme.of(context).colorScheme.onPrimaryContainer
                                      : Theme.of(context).colorScheme.onSecondaryContainer,
                                  isVisible: (phase == SessionPhase.waitingForForce && !setStartArmed) ||
                                      (phase == SessionPhase.waitingForForce && setStartArmed) ||
                                      (phase != SessionPhase.activeSet && currentForce > 0),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (phase == SessionPhase.waitingForForce)
                            Text(
                              setStartArmed
                                  ? 'Apply at least ${widget.forceThresholdKg} kg to start the set.'
                                  : 'Release to 0 kg first, then apply at least ${widget.forceThresholdKg} kg to start.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),"""

content = content.replace(old_chart_block, new_chart_block)

with open('lib/ui/workouts/active_workout_page.dart', 'w') as f:
    f.write(content)
