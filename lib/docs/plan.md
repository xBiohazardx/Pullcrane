# Pullcrane Plan

This document describes the app **as built**. It was rewritten after the
initial delivery phases to match the actual implementation.

## Confirmed decisions (current state)

- Navigation tabs (order): Home, Workouts, Exercises, Settings.
  Benchmarking lives on the exercise form/progression pages, not as its own tab.
- Data: local SQLite only (sqflite on Android/iOS, sqflite_common_ffi on
  desktop), no cloud sync.
- Schema is versioned with incremental, data-preserving migrations:
  - v2 → v3: settings table rebuilt (dead `user_max_lift_kg` dropped,
    `max_force_kg` added).
  - v3 → v4: workout history tables (`workout_sessions`, `set_logs`).
- Exercises: name, description, side-switching flag, per-hand max lifts,
  dated max-lift history.
- Workouts: ordered entries; each entry defines sets, mode (reps or
  duration), reps/duration, rest, target force, and starting hand.
- Target force: absolute kg or relative (% of the exercise's max lift for the
  active hand). Without a benchmark, a 60 kg fallback is used and surfaced in
  the active workout UI.
- Force ceiling (`maxForceKg`, default 200 kg) is configurable in Settings and
  applies to BLE parsing, simulated input, targets, and charts.
- Force trigger: a set starts only above the configurable threshold
  (default 10 kg), optionally requiring a release to 0 kg first.
- If force drops during a timed set, the timer continues.
- Hand switching: app-controlled. Rest before switching equals the opposite
  hand's *leftover* rest (clamped at 0); leftover rest debt persists across
  entries within a workout on purpose (physiological carryover).
- All session countdowns are anchored to wall-clock end times, so backgrounded
  apps and screen lock do not stretch sets or rests. The screen is kept awake
  during workouts (wakelock).
- Force source: BLE crane scale (WH-C06, passive advertisements; device name
  filter configurable, default `IF_B7`) or a simulated finger-drag device.
  - On Android, force data streams through a native Kotlin `FastBleScanHandler`
    (EventChannel, LOW_LATENCY scan) with 3x retry and a 10 s data watchdog.
    The native side filters by the compiled-in `IF_B7` name and does not clamp
    force (the Dart side clamps to the configured max force).
  - On other platforms, a Dart fallback parses advertisements from the
    universal_ble scan stream via `CraneScaleParser`.
  - universal_ble is pinned to ^1.2.0: 2.x requires Dart >=3.11.4/3.12
    (Flutter >=3.44), 1.2.0 offers the same ScanFilter API on Dart 3.11.0.
- Rep-mode sets count reps automatically: a rep counts when force crosses the
  threshold and then drops below a release threshold (half the trigger
  threshold, min 2 kg); the set auto-completes at the planned rep count.
- Workout sessions are recorded (start/finish time, completion flag, per-set
  target vs. peak force, planned vs. actual duration) and survive workout and
  exercise deletion (denormalized names, no foreign keys).
- History UI: session list + per-session detail under the Workouts tab.
  Per-exercise analytics (sessions, time under tension, best peak, recent
  sets) on the exercise progression page.

## Architecture

- `lib/domain/models/` — plain data classes.
- `lib/domain/services/` — `CraneScaleService` (BLE + simulated input
  singleton), `FastBleScanner` (native Android force stream via EventChannel),
  `CraneScaleParser` (pure advertisement parsing, non-Android fallback),
  `WorkoutSessionController` (pure, timer-free session state machine; the UI
  feeds it force readings and wall-clock ticks).
- `lib/data/` — `AppDatabase` (schema + migrations) and stores for exercises,
  workouts, settings, and sessions.
- `lib/ui/` — pages per tab; the active workout page is a thin binding over
  the session controller.
- Tests: unit tests for the engine, BLE parser, stores, and DB migrations
  (`flutter test`).

## Deferred / future ideas

- Richer analytics (volume trends, force curves per set, adherence).
- Automatic rep detection for rep-mode sets.
- Export/backup of the database.
- Multiple BLE device profiles.
