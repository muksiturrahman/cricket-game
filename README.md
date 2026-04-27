# Cricket Game

A polished 2D top-down cricket game built with **Flutter** and **Flame**. Pick a format (T5 / T10 / T20), pick a difficulty (Easy / Normal / Hard), and bat against an AI bowler with rotating archetypes — pacers, swing bowlers, mediums, and spinners that actually turn the ball off the pitch.

> Offline. No sign-in. No backend. Runs on macOS, Android, iOS, and the web.

---

## Table of Contents

- [Features](#features)
- [Screens & Flow](#screens--flow)
- [Controls](#controls)
- [Quick Start](#quick-start)
- [Build & Run](#build--run)
- [Project Structure](#project-structure)
- [Architecture](#architecture)
- [Gameplay Systems](#gameplay-systems)
- [Tech Stack](#tech-stack)
- [Testing](#testing)
- [Roadmap](#roadmap)
- [License](#license)

---

## Features

- **Three match formats** — T5, T10, T20 (5 / 10 / 20 overs).
- **Three difficulties** — Easy, Normal, Hard. Affects bowl speed, swing window, fielder speed, fielder chase distance, and run-out throw speed.
- **Free-direction shots** — swipe in any direction; force scales with swipe length.
- **POWER toggle** — flip between lofted (boundary potential, catchable) and grounded (low, uncatchable) on the fly.
- **Shot timing meter** — clean / mistimed / edge bucketed from how late in the swing window contact happened. Edges deflect to the keeper.
- **Running between wickets** — press `R` / `Enter` (or tap the on-screen RUN button) for singles, doubles, threes. Boundaries override partial runs.
- **Bowler archetypes** — pacer, medium, swing, spinner. Rotated every over. Spinners actually deflect the ball off the pitch.
- **Wides, no-balls, and run-outs** with proper scoring and replay rules.
- **Active fielding** — the closest fielder chases on each shot; a backup fielder commits to the deeper line. Catches require descending balls; rising balls pass overhead.
- **Two-innings chase mode** — bat first, then defend the target as the AI chases.
- **Strike rotation** — odd runs and end-of-over rotate strike, with a real second batsman on the pitch.
- **Persistent stats** — best score, matches played, win %, fours, sixes, wickets — saved across sessions.
- **Mid-match save / resume** — quit to menu mid-innings and pick up where you left off.
- **First-run tutorial** — 4-card walkthrough on cold start, gated by a once-only flag.
- **Procedural audio** — bat hits, bounces, stump breaks, catches, crowd cheers, and run whistles synthesized in code (no audio files bundled).
- **Haptic feedback** — light/medium/heavy on key events (mobile only).

## Screens & Flow

```
Splash (cold start, ~1.5s)
   └── Tutorial (first-run only) → Main Menu
        └── Main Menu (format + difficulty + chase toggle)
             ├── PLAY MATCH ─→ Gameplay
             │     ├── Pause   ─→ Pause Overlay
             │     └── Innings end ─→ Game Over Overlay (full scorecard)
             └── RESUME (only when a saved match exists)
```

## Controls

### Touch / Mouse

| Action | Gesture |
|---|---|
| Play a shot | Swipe in any direction |
| Defensive block | Quick tap (no swipe) |
| Move batsman laterally | Slow drag on the batsman's body |
| Take a run | Tap the on-screen **RUN** button (visible after bat contact) |
| Toggle POWER | Tap the **POWER** pill (top-right) |
| Pause | Tap the pause button (top-left) |

### Keyboard

| Action | Key |
|---|---|
| Cover Drive | **C** |
| Straight Drive | **V** |
| Pull Shot | **↑** / **W** |
| Defensive | **↓** / **S** / **Space** |
| Move left (leg side) | Hold **←** / **A** |
| Move right (off side) | Hold **→** / **D** |
| Take a run | **R** / **Enter** |
| Pause | **P** / **Esc** |

## Quick Start

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.10.4`).

```bash
git clone https://github.com/muksiturrahman/cricket-game.git
cd cricket-game
flutter pub get
flutter run -d macos      # or: -d chrome, or any connected device
```

## Build & Run

```bash
flutter run -d macos                # macOS desktop
flutter run -d chrome               # Web browser
flutter run                         # Connected Android / iOS device

flutter build apk --release         # Android APK
flutter build apk --debug           # Android APK (debug)
flutter build ios --no-codesign     # iOS build (requires Xcode for signing)
flutter build macos --release       # macOS app
flutter build web --release         # Web bundle
```

## Project Structure

```
lib/
├── main.dart                       # Entry point — Provider wrapper, overlays, on-screen buttons
├── events/                         # Sealed event hierarchy + sync broadcast bus
│   ├── delivery_event.dart
│   └── delivery_event_bus.dart
├── services/                       # Pure-Dart services (testable in isolation)
│   ├── shot_intent.dart            # Value object: direction + force + powerOn
│   ├── input_service.dart          # Swipe → ShotIntent
│   ├── physics_service.dart        # ShotIntent → rebound velocity
│   ├── sound_service.dart          # Procedural WAV synthesis + playback pool
│   ├── haptic_service.dart         # Mobile-gated HapticFeedback wrapper
│   ├── stats_service.dart          # Persisted aggregate stats
│   ├── save_service.dart           # Mid-innings save / resume
│   └── sprite_service.dart         # Optional PNG sprite loader (canvas fallback)
├── state/
│   ├── game_state_notifier.dart    # ChangeNotifier — phase + final score snapshot
│   └── match_settings.dart         # MatchFormat + Difficulty + chase flag
├── game/
│   ├── cricket_game.dart           # Flame orchestrator — wires components + event bus
│   ├── pitch.dart                  # Stadium scene (sky, crowd, mowing stripes, ring)
│   ├── ball.dart                   # Physics, collisions, motion trail, shadow
│   ├── bat.dart                    # Hitbox + swing rotation
│   ├── batsman.dart                # Detailed art, swing/run animation, lateral movement
│   ├── bowler.dart                 # AI bowler with animated arm sweep
│   ├── stumps.dart                 # Stumps + bail break animation
│   ├── fielder.dart                # Fielder with active chase + flash on action
│   ├── effects.dart                # DustPuff, HitSpark, BoundaryBurst, RunPopup
│   ├── hud.dart                    # Score panel, recent-balls strip, banners
│   ├── score_manager.dart          # Runs, wickets, overs, ball history
│   └── ai_manager.dart             # Bowler archetypes + per-delivery config
├── screens/
│   ├── main_menu.dart              # Main menu / pause / game over overlays
│   ├── splash_overlay.dart         # 1.5s cold-start splash (tap-to-skip)
│   └── tutorial_overlay.dart       # First-run 4-card walkthrough
└── utils/
    ├── constants.dart              # Tunables + enums (game rules, physics)
    └── theme.dart                  # Centralized palette, gradients, text styles
test/
├── widget_test.dart                # ScoreManager unit tests (7)
├── shot_intent_test.dart           # ShotIntent factory + classification (8)
├── physics_service_test.dart       # reboundVelocity defensive/grounded/lofted/quality (13+6)
└── input_service_test.dart         # swipeToIntent threshold/force/direction (7)
```

## Architecture

The game uses a **two-layer hybrid** built around the constraints of a Flame game loop:

- **Flame layer** — service classes + a synchronous event bus. No reactive state inside `update(dt)`.
- **Flutter overlay layer** — `Provider` + `ChangeNotifier` for menu, pause, and game-over screens.

### Delivery state machine

Every collision and gameplay transition flows through one event bus and a single `_onDeliveryEvent` switch:

```
startGame()
  └── _scheduleNextDelivery()
       └── AIManager.decideBowl() → Bowler.prepareBowl(config)
            └── (1.5s run-up) → BallLaunched → ball.launch()
                 ├── Ball ↔ Bat       → BatContact   → reboundVelocity, runs window opens
                 ├── Ball ↔ Stumps    → WicketFallen → +1 wicket, bails fly
                 ├── Ball ↔ Fielder   → BallCaught / BallFielded
                 ├── Ball off-screen  → BoundaryHit(4|6) | BallDead
                 └── Player presses R → RunTaken (cooldown enforced)
            ↓
            BallSettled(outcome) → ScoreManager.recordOutcome + nextBall()
            ↓
            ScoreChanged → HUD refreshes
            ↓
            innings over? → GameOver overlay  |  else → next delivery
```

### Why this shape

- A central event bus keeps Flame components decoupled from Flutter overlays.
- Pure-Dart services (`InputService`, `PhysicsService`, `ShotIntent`, `ScoreManager`, `AIManager`) have zero Flame dependencies and are trivially unit-testable.
- `Provider` is only used at the overlay layer where reactive rebuilds are cheap. Inside the game loop, state changes go through the event bus, not `notifyListeners`.

## Gameplay Systems

### Free-direction shots + POWER toggle

`InputService.swipeToIntent(start, end, powerOn:)` returns a `ShotIntent { direction, force, powerOn, type }`. `PhysicsService.reboundVelocity(intent, speed, quality:)` builds the actual velocity:

- **POWER ON** — vertical bias forces a loft. Boundary potential as a 6, but catchable on descent.
- **GROUND** — vertical clamped low. Stays in for 1s/4s — almost never a 6, but largely uncatchable.

### Shot timing

`Batsman.swingProgress` (`0..1` over the swing window) is bucketed into `ShotQuality`:

- `clean` (≤ 0.55) — full power, intended trajectory.
- `mistimed` (≤ 0.80) — magnitude × 0.55, dies in the field.
- `edge` (> 0.80) — randomized lateral deflection back toward the keeper.

A small swing-timing meter renders above the batsman during contact so the player can read whether they were on time.

### Running between wickets

Bat contact opens a *running window*. Each `R` press lerps the batsman to the other crease (`kRunCooldownSec` = 0.55s) and increments a pending counter. Pending runs are committed only at end of delivery — boundaries discard them, catches discard them, fields commit them. Real cricket behaviour, no flicker.

### Bowler archetypes

Rotated every over (`% 4`). Each archetype owns absolute speed bands and a swing range, scaled by difficulty:

| Kind | Speed (Normal) | Swing | Length bias |
|---|---|---|---|
| Pacer | 440–540 px/s | ±6° | Short / yorker |
| Medium | 320–410 px/s | ±8° | Good length |
| Swing | 340–420 px/s | ±22° | Pitched up |
| Spinner | 220–310 px/s | ±12° | Avoids bouncers; deflects ±90 px/s off the pitch |

### Active fielding

The closest fielder to the predicted ball position chases live. A backup fielder commits once to the deeper line (real cricket — backups cover the throw, they don't double-chase). Each fielder is clamped to within `kFielderMaxChaseDistance` of home, so a single fielder can't sprint across the entire field.

### Run-outs

Physics-based. On a fielded ball with the striker mid-stride, `Ball.throwTo(stumps)` fires at `kThrowSpeed = 950 px/s`. If the throw hits the stumps before the runner arrives, only completed runs count and the wicket falls. Difficulty scales throw *speed*, not probability — Hard rifles in faster, Easy lobs.

### Persistence

- `StatsService` (singleton `ChangeNotifier` + `shared_preferences`) — matches played, won, best score, totals, tutorial flag.
- `SaveService` — JSON snapshot of `MatchSettings` + scoreboard + history + innings + target. Saved between deliveries; cleared on innings finalize / restart.

## Tech Stack

| | |
|---|---|
| **Framework** | Flutter |
| **Game engine** | [Flame](https://flame-engine.org/) `^1.35.1` |
| **Dart SDK** | `^3.10.4` |
| **State** | [`provider`](https://pub.dev/packages/provider) `^6.1.2` |
| **Persistence** | [`shared_preferences`](https://pub.dev/packages/shared_preferences) `^2.3.0`, [`path_provider`](https://pub.dev/packages/path_provider) `^2.1.5` |
| **Audio** | [`audioplayers`](https://pub.dev/packages/audioplayers) `^6.6.0` (procedural WAV bytes) |
| **Splash** | [`flutter_native_splash`](https://pub.dev/packages/flutter_native_splash) `^2.4.0` |
| **Lints** | [`flutter_lints`](https://pub.dev/packages/flutter_lints) `^6.0.0` |
| **Testing** | `flutter_test`, [`flame_test`](https://pub.dev/packages/flame_test) `^1.18.0` |

## Testing

```bash
flutter analyze    # static analysis (zero warnings expected)
flutter test       # unit tests
```

Coverage spans the pure-Dart core:

- `ScoreManager` — runs / wickets / overs / outcomes.
- `ShotIntent` — factory rules + classification.
- `PhysicsService` — defensive / grounded / lofted clamps + shot-quality scaling.
- `InputService` — swipe threshold, force normalization, direction mapping.

## Roadmap

- Drop-in PNG sprites — `SpriteService` already probes `assets/images/{batsman,bowler,fielder,ball}.png` at startup; canvas art is the current fallback.
- Free-hit follow-up after a no-ball.
- Smarter AI batsman in chase mode (currently random direction with required-rate-driven aggression).
- Mid-flight resume (current save/resume only captures the clean state between deliveries).

## License

This project is released under the [MIT License](LICENSE).
