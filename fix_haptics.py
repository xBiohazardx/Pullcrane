import re

with open('lib/ui/workouts/active_workout_page.dart', 'r') as f:
    content = f.read()

# Update _syncTargetFeedback
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

# Find all setState calls that modify phase or setStartArmed and inject _syncTargetFeedback after them
# Wait, let's just make a small helper function that wraps setState and syncs feedback, 
# or we just manually inject them.
# A simpler approach: just inject _syncTargetFeedback(currentForce); right after setState(() { phase = ... }); blocks

replacements = [
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
    )
]

for old, new in replacements:
    content = content.replace(old, new)

with open('lib/ui/workouts/active_workout_page.dart', 'w') as f:
    f.write(content)
