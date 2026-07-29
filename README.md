# pullcrane

Force-training app for climbers. Connects to a WH-C06 Bluetooth crane scale
(or a simulated finger-drag device), measures per-exercise max lifts, and
guides structured workouts with force-triggered timed/rep sets, rest timers,
and hand switching. Records every session for history and per-exercise
analytics.

## Features

- Guided workouts: threshold-triggered sets, wall-clock accurate timers,
  automatic hand switching with rest carryover, haptic target-zone feedback.
- Benchmarks: per-hand max-lift measurement with progression graphs.
- History: every session persisted (target vs. peak force per set), with
  per-exercise training summaries.
- Configurable: force threshold, target hysteresis, maximum force, BLE device
  name filter, optional external database location.

## Development

```sh
flutter pub get
flutter analyze   # lints
flutter test      # unit + widget tests (engine, BLE parser, stores, migrations)
flutter run       # Android / Linux desktop
```

See `lib/docs/plan.md` for architecture and design decisions.
