# Pullcrane Plan

## Confirmed decisions

- Navigation tabs (order): Home, Workouts, Exercises, Settings.
- Data: local only, no cloud sync.
- Exercise type: exactly one mode per exercise (reps or duration).
- Rest handling: exercise has default rest; workout entry can override it.
- Include a default "Rest" exercise template.
- Exercises must define a target force.
- Target force supports two modes: absolute kg or relative (% of user max lift).
- User max lift is hardcoded for now (temporary placeholder until max-lift flow is implemented).
- Force trigger: start only above a configurable threshold.
- Threshold default: 10kg (from settings).
- If force drops during a timed set: timer continues.
- Hand switching: app-controlled only (user switches when prompted).
- Rest carryover on hand switch: subtract from next opposite-side rest, clamped at 0.
- Force source for now: keep dummy input; Bluetooth comes later.
- Workout history/logging: planned, but not implemented in current phase.

## Delivery phases

### Phase 1 - App shell and navigation

- Add bottom navigation with Home, Workouts, Exercises, Settings.
- Keep current force training screen as Home.

### Phase 2 - Domain and local storage

- Model Exercise, Workout, WorkoutExerciseEntry, and execution/session models.
- Add local repository layer and persistence for exercises/workouts.

### Phase 3 - CRUD

- Exercises: create, edit, list, delete.
- Workouts: create, edit, list, delete.
- Workout editor: ordered exercise entries with set count and optional rest override.
- Add default "Rest" exercise.
- Extend exercise model/forms with target force mode/value:
  - absolute target in kg, or
  - relative target as % of user max lift.

### Phase 4 - Max lift measurement page

- Add a dedicated page to measure user max lift.
- Add flow to start/record/update user max lift.
- For now keep max lift hardcoded in execution logic until this phase is fully wired to storage/settings.

### Phase 5 - Execution engine

- Build state machine for set flow: waiting -> active set -> rest -> next.
- Timed exercises start only when force >= threshold.
- Reps exercises track completion and transition to rest.
- Rest timer starts only when exercise is completed.
- Force drop during timed set does not pause timer.
- Show target force per exercise (resolved from absolute value or % of user max lift).

### Phase 6 - Guided hand switching

- Mark exercises as side-switching where needed.
- Prompt hand switch at defined points in workout flow.
- Subtract unused rest from opposite-hand next rest, clamp to 0.

### Phase 7 - Settings

- Add configurable default force threshold (default 10kg).
- Add execution preferences needed by engine behavior.
- Add max-lift related settings entry points.

### Phase 8 - Bluetooth integration

- Add force input adapter abstraction.
- Keep dummy adapter for testing.
- Plug in BLE crane scale adapter.

### Deferred (planned, not now)

- Workout history/session logs.
- Progress analytics derived from stored sessions.
