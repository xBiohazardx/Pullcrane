import re

with open('lib/ui/workouts/active_workout_page.dart', 'r') as f:
    content = f.read()

# Add actionLabel logic
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

# Remove old Force top
old_force = """              Text(
                'Force: ${currentForce}kg',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: isInTargetRange ? Colors.green : null,
                ),
              ),
              const SizedBox(height: 16),"""
content = content.replace(old_force, "")

# Replace middle texts
old_middle = """                          Text(
                            entry.mode == ExerciseMode.duration
                                ? 'Hold ${entry.durationSeconds ?? 0}s'
                                : '${entry.reps ?? 0} reps',
                          ),"""

new_middle = """                          Row(
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
                          ),"""
content = content.replace(old_middle, new_middle)

# Remove bottom redundant texts
old_bottom = """                          if (phase == SessionPhase.activeSet &&
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
content = content.replace(old_bottom, "")

with open('lib/ui/workouts/active_workout_page.dart', 'w') as f:
    f.write(content)
