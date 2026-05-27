import re

with open('lib/ui/workouts/active_workout_page.dart', 'r') as f:
    content = f.read()

replacements = [
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

for old, new in replacements:
    content = content.replace(old, new)

with open('lib/ui/workouts/active_workout_page.dart', 'w') as f:
    f.write(content)
