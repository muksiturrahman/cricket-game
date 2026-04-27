import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../events/delivery_event.dart';
import '../events/delivery_event_bus.dart';
import '../services/haptic_service.dart';
import '../services/input_service.dart';
import '../services/physics_service.dart';
import '../services/save_service.dart';
import '../services/shot_intent.dart';
import '../services/sound_service.dart';
import '../services/stats_service.dart';
import '../state/game_state_notifier.dart';
import '../state/match_settings.dart';
import '../utils/constants.dart';
import 'ai_manager.dart';
import 'ball.dart';
import 'batsman.dart';
import 'bowler.dart';
import 'fielder.dart';
import 'hud.dart';
import 'effects.dart';
import 'pitch.dart';
import 'score_manager.dart';
import 'stumps.dart';

class CricketGame extends FlameGame
    with HasCollisionDetection, TapCallbacks, DragCallbacks, KeyboardEvents {
  // ── Services ───────────────────────────────────────────────────────────────
  final DeliveryEventBus eventBus = DeliveryEventBus();
  final GameStateNotifier stateNotifier = GameStateNotifier();
  final InputService _input = InputService();
  final PhysicsService _physics = PhysicsService();

  // ── Managers ───────────────────────────────────────────────────────────────
  final ScoreManager scoreManager = ScoreManager();
  final AIManager aiManager = AIManager();

  // ── Components ─────────────────────────────────────────────────────────────
  late Ball ball;
  /// Whichever physical Batsman is currently at the striker's crease and
  /// owns the next shot. Swapped by `_swapStrike()` after odd-runs / EoO.
  late Batsman striker;
  /// The partner — at the bowler's end. Doesn't swing; only runs alongside.
  late Batsman nonStriker;
  /// Backwards-compatible alias for code paths still written against
  /// `batsman.X`. Always points to the current striker.
  Batsman get batsman => striker;
  late Bowler bowler;
  late Stumps stumps;
  late GameHud hud;
  final Map<FieldPosition, Fielder> fielders = {};

  // ── State ──────────────────────────────────────────────────────────────────
  GamePhase phase = GamePhase.mainMenu;
  MatchSettings settings = const MatchSettings();
  bool _inputEnabled = false;
  Offset? _tapStart;
  StreamSubscription<DeliveryEvent>? _eventSub;

  /// Current innings — only `aiBats` if `settings.chase` is true and the
  /// player's innings has finished. Drives input gating + HUD.
  Innings innings = Innings.playerBats;

  /// Captured at end of the player's innings (chase mode) so the GameOver
  /// overlay can show both totals + the winner.
  ScoreSnapshot? firstInningsScore;

  /// Player batting stats (4s / 6s / wickets) snapshotted at the end of the
  /// player's innings — needed by `StatsService` after the AI's chase has
  /// already wiped the live `ScoreManager`. Null in single-innings mode.
  _PlayerInningsStats? _playerStats;

  /// Set during `aiBats` — runs needed for AI to win. Read by HUD.
  int? target;

  /// Power toggle — when true the next shot is *lofted* (high arc, can clear
  /// the rope as a 6 but is catchable by deep fielders); when false the shot
  /// stays *grounded* (low trajectory, harder to dismiss but rarely a 6).
  /// Bound to the on-screen POWER button in `main.dart`. Exposed as a
  /// `ValueNotifier` so the Flutter widget can rebuild on toggle.
  final ValueNotifier<bool> powerOn = ValueNotifier(false);

  void togglePower() => powerOn.value = !powerOn.value;

  /// Called by `TutorialOverlay` when the player dismisses the walk-through.
  /// Swaps the active overlay over to the splash → main-menu sequence.
  void dismissTutorial() {
    overlays.remove('Tutorial');
    overlays.add('MainMenu');
  }

  // Live snapshot of keys currently held — updated in onKeyEvent. Read each
  // frame in update(dt) to drive batsman lateral movement (A / ←, D / →).
  Set<LogicalKeyboardKey> _heldKeys = const {};

  // Running between wickets — active from BatContact until ball ends.
  bool _runningActive = false;
  int _runsThisBall = 0;
  double _gameTime = 0;
  double _lastRunAt = -1000;

  /// Mirrors `_runningActive` for Flutter widgets to listen on. Drives the
  /// on-screen RUN button visibility.
  final ValueNotifier<bool> runningActive = ValueNotifier(false);

  /// Update both the internal flag and the public notifier so the RUN
  /// button rebuilds.
  void _setRunning(bool active) {
    _runningActive = active;
    runningActive.value = active;
  }

  /// Public entry-point for the on-screen RUN button (mobile). Keyboard goes
  /// through `_takeRun` directly.
  void takeRun() => _takeRun();

  // Outcome of the in-progress delivery — finalized in _finishDelivery().
  int _outcomeRuns = 0;
  bool _outcomeWicket = false;

  /// The active delivery's BowlConfig — captured on `BallLaunched` so the
  /// terminal handlers can see whether it was a wide / no-ball.
  BowlConfig? _currentBowl;

  /// Per-bowler-kind innings stats, tallied in `_finishDelivery`. Drives
  /// the bowling card on the GameOver overlay.
  final Map<BowlerKind, BowlerStats> bowlerStats = {
    for (final kind in BowlerKind.values) kind: BowlerStats(),
  };

  // ── DRS / replay ──────────────────────────────────────────────────────
  /// Captured ball-centre positions during the live delivery — replayed in
  /// slow-mo on wickets / sixes. Cleared on `BallLaunched`.
  final List<Vector2> _replayFrames = [];
  /// Times (in `_gameTime`) for each captured frame, used to scrub the
  /// playhead during replay.
  final List<double> _replayTimes = [];
  /// True while a `ReplayOverlay` is on screen — extends the settling delay
  /// in `_finishDelivery` so the next ball doesn't bowl over the replay.
  bool _replayActive = false;

  // Screen-shake — magnitude in pixels, decays linearly each frame.
  double _shake = 0;
  final math.Random _shakeRng = math.Random();

  // Active fielder — picked on BatContact, tracks the ball each frame for
  // ground shots; for lofted shots it commits to the predicted landing once.
  Fielder? _chasingFielder;
  /// Backup fielder — picked alongside the primary on BatContact and
  /// committed to a point `kBackupOffsetPx` *past* the primary's target
  /// along the ball's velocity. Covers the ball if it slips past the
  /// chaser. Stationary at its commit point; not live-tracked.
  Fielder? _backupFielder;
  /// True when the last contact was a lofted (POWER) shot. Suppresses live
  /// air-tracking in update(dt) so outfielders can't perfectly follow the ball.
  bool _lastShotWasLofted = false;
  /// True between two deliveries while we're waiting on a Future.delayed
  /// (settling gap or innings-change pause). Cleared once the next delivery
  /// is scheduled. Used by `togglePause` to recover from a pause that lands
  /// inside one of those gaps and would otherwise leave the game stalled.
  bool _pendingDeliveryScheduled = false;

  // Standard field placement, normalized (x, y) ratios of screen size.
  // All positions sit just inside the boundary ellipse (kBoundaryWidthRatio ×
  // kBoundaryHeightRatio) so deep fielders intercept boundary-bound shots.
  // The keeper sits behind the striker's stumps and is excluded from the
  // chase picker — they're a stationary catcher for edges.
  static const Map<FieldPosition, (double, double)> _fieldLayout = {
    FieldPosition.cover: (0.20, 0.50),
    FieldPosition.midOff: (0.78, 0.55),
    FieldPosition.midOn: (0.30, 0.55),
    FieldPosition.squareLeg: (0.85, 0.45),
    FieldPosition.longOff: (0.78, 0.25),
    FieldPosition.longOn: (0.22, 0.25),
    FieldPosition.midwicket: (0.15, 0.35),
    FieldPosition.keeper: (kKeeperXRatio, kKeeperYRatio),
  };

  @override
  Future<void> onLoad() async {
    _eventSub = eventBus.stream.listen(_onDeliveryEvent);
    // Best-effort sound preload — no-op if no asset files are bundled yet.
    unawaited(SoundService.instance.preload());

    await add(Pitch());

    stumps = Stumps();
    await add(stumps);

    bowler = Bowler();
    bowler.onRelease = (config) => eventBus.fire(BallLaunched(config));
    await add(bowler);

    striker = Batsman(homeAtStriker: true, jerseyNumber: '7');
    nonStriker = Batsman(homeAtStriker: false, jerseyNumber: '11');
    await add(striker);
    await add(nonStriker);

    for (final entry in _fieldLayout.entries) {
      final (rx, ry) = entry.value;
      final fielder = Fielder(
        fieldPosition: entry.key,
        anchorRatio: Vector2(rx, ry),
      );
      fielders[entry.key] = fielder;
      await add(fielder);
    }

    ball = Ball();
    ball.onBatHit = (shot) => eventBus.fire(BatContact(shot));
    ball.onStumpsHit = () => eventBus.fire(const WicketFallen());
    ball.onBallDead = () => eventBus.fire(const BallDead());
    ball.onCaught = (f) => eventBus.fire(BallCaught(f.fieldPosition));
    ball.onFielded = (f) => eventBus.fire(BallFielded(f.fieldPosition));
    ball.onBoundary = (runs) => eventBus.fire(BoundaryHit(runs));
    ball.onBounce = (pos) {
      add(DustPuff(origin: pos));
      SoundService.instance.bounce();
    };
    await add(ball);

    hud = GameHud(eventBus: eventBus);
    await add(hud);
  }

  // ── Single dispatcher for all delivery events ──────────────────────────────
  void _onDeliveryEvent(DeliveryEvent event) {
    switch (event) {
      case BallLaunched(:final config):
        _currentBowl = config;
        ball.launch(config);
        // Player input only during their own innings — AI controls the bat
        // when `innings == aiBats`.
        _inputEnabled = innings == Innings.playerBats;
        _runsThisBall = 0;
        _setRunning(false);
        _outcomeRuns = 0;
        _outcomeWicket = false;
        // Reset replay capture for the new delivery.
        _replayFrames.clear();
        _replayTimes.clear();
        if (innings == Innings.aiBats) {
          _scheduleAiSwing();
        }

      case BatContact(:final intent):
        _inputEnabled = false;
        // Shot quality is derived from how far through the swing window the
        // bat-ball collision happened. Small `swingProgress` = player swung
        // right as the ball arrived (clean). Large = swung well in advance
        // (mistimed → reduced power; edge → deflected to keeper).
        final progress = batsman.swingProgress;
        final ShotQuality quality;
        if (intent.isDefensive) {
          quality = ShotQuality.clean; // defensive blocks aren't graded
        } else if (progress <= kSwingCleanMax) {
          quality = ShotQuality.clean;
        } else if (progress <= kSwingMistimedMax) {
          quality = ShotQuality.mistimed;
        } else {
          quality = ShotQuality.edge;
        }
        final rebound = _physics.reboundVelocity(
          intent,
          ball.velocity.length,
          quality: quality,
        );
        ball.velocity = rebound;
        ball.ballState = BallState.inFlight;
        ball.collisionProcessed = false;
        _runningActive = true;
        _runsThisBall = 0;
        _lastRunAt = _gameTime - kRunCooldownSec;
        // Edges deflect backward toward the keeper — let the keeper catch
        // it via the existing collision system. Skip outfielder chase since
        // no outfielder will reach a ball going the other way.
        if (quality == ShotQuality.edge) {
          _chasingFielder = null;
          _backupFielder = null;
          _lastShotWasLofted = false;
        } else {
          // Lofted shots: chaser commits to the *predicted landing point* once
          // and stays there (capped to maxChaseDistance via Fielder.update).
          // Live air-tracking is suppressed in update(dt) — outfielders can't
          // track a high ball perfectly, so the player can find gaps.
          // Ground shots: chaser tracks the ball every frame as before.
          _lastShotWasLofted = intent.powerOn && !intent.isDefensive;
          // Capture the *primary's* commit point so we can position a backup
          // fielder behind them along the ball's trajectory.
          final Vector2 primaryPoint;
          if (_lastShotWasLofted) {
            final landing = _predictLandingPoint(rebound);
            _chasingFielder = _pickChaserNearPoint(landing);
            _chasingFielder?.chaseTo(landing);
            primaryPoint = landing;
          } else {
            _chasingFielder = _pickChaser(rebound);
            final ballCentre = Vector2(
              ball.position.x + ball.size.x / 2,
              ball.position.y + ball.size.y / 2,
            );
            primaryPoint =
                ballCentre + rebound * kFielderChaseLookaheadSec;
          }
          // Backup fielder: closest non-keeper, non-primary fielder to a
          // point further along the ball's trajectory. Commits once, doesn't
          // live-track — they're stationed in case the ball slips past the
          // primary or the primary fumbles.
          final backupPoint = _computeBackupPoint(primaryPoint, rebound);
          _backupFielder = _pickChaserNearPoint(
            backupPoint,
            exclude: _chasingFielder != null
                ? {_chasingFielder!.fieldPosition}
                : null,
          );
          _backupFielder?.chaseTo(backupPoint);
        }
        add(HitSpark(
          origin: Vector2(
            ball.position.x + ball.size.x / 2,
            ball.position.y + ball.size.y / 2,
          ),
        ));
        SoundService.instance.batHit();
        HapticService.instance.light();
        // Fire a feedback event for non-clean shots so the HUD can pop a
        // small banner ("MISTIMED" / "EDGE!").
        if (quality != ShotQuality.clean) {
          eventBus.fire(ShotQualityCalled(quality));
        }

      case WicketFallen():
        _inputEnabled = false;
        _setRunning(false);
        // Was this a fielder's throw smashing into the stumps for a run-out?
        // If so, route to the run-out resolver — the batsman might still be
        // safely in their crease (= no wicket, runs stand).
        if (_throwInProgress) {
          _resolveThrowAtStumps();
          return;
        }
        _runsThisBall = 0;
        _outcomeRuns = 0;
        _outcomeWicket = true;
        scoreManager.addWicket();
        stumps.flyBails();
        shakeScreen(10);
        SoundService.instance.wicket();
        HapticService.instance.medium();
        striker.resetIdle();
        nonStriker.resetIdle();
        _sendFieldersHome();
        _finishDelivery();

      case BallCaught(:final by):
        _inputEnabled = false;
        _setRunning(false);
        _runsThisBall = 0;
        _outcomeRuns = 0;
        _outcomeWicket = true;
        scoreManager.addWicket();
        fielders[by]?.flashHighlight();
        shakeScreen(8);
        SoundService.instance.caught();
        HapticService.instance.medium();
        striker.resetIdle();
        nonStriker.resetIdle();
        _sendFieldersHome();
        _finishDelivery();

      case BallFielded(:final by):
        _inputEnabled = false;
        // Don't disable running yet — if we're about to throw at the stumps,
        // the batsman keeps sprinting and the resolver clears it.
        final fielder = fielders[by];
        // Run-out scenario: batsman is mid-stride and at least one run has
        // been started. Fielder will physically rifle the ball at the stumps;
        // outcome (out vs safe) is decided when the ball arrives there.
        if (fielder != null && striker.isRunning && _runsThisBall > 0) {
          _startThrow(fielder);
          return;
        }
        _setRunning(false);
        if (_runsThisBall > 0) {
          scoreManager.addRuns(_runsThisBall);
          _outcomeRuns = _runsThisBall;
          _runsThisBall = 0;
        }
        fielder?.flashHighlight();
        striker.resetIdle();
        nonStriker.resetIdle();
        _sendFieldersHome();
        _finishDelivery();

      case BoundaryHit(:final runs):
        _inputEnabled = false;
        _setRunning(false);
        _runsThisBall = 0;
        scoreManager.addRuns(runs);
        _outcomeRuns = runs;
        add(BoundaryBurst(
          origin: size / 2,
          isSix: runs == kBoundarySixRuns,
        ));
        add(RunPopup(
          origin: Vector2(
            ball.position.x + ball.size.x / 2,
            ball.position.y + ball.size.y / 2,
          ),
          runs: runs,
        ));
        shakeScreen(runs == kBoundarySixRuns ? 14 : 8);
        if (runs == kBoundarySixRuns) {
          SoundService.instance.cheerSix();
          HapticService.instance.heavy();
        } else {
          SoundService.instance.cheerFour();
          HapticService.instance.medium();
        }
        // Crowd / 30-yard ring reaction.
        final p = children.whereType<Pitch>().firstOrNull;
        p?.cheer();
        striker.resetIdle();
        nonStriker.resetIdle();
        _sendFieldersHome();
        _finishDelivery();

      case BallDead():
        _inputEnabled = false;
        // Throw missed the stumps and went off-screen — fumble. Resolver
        // commits any in-flight runs and finalizes the delivery.
        if (_throwInProgress) {
          _resolveThrowMissed();
          return;
        }
        _setRunning(false);
        // A wide that the batsman never connected with — +1 extra, re-bowl
        // the same delivery (does NOT increment ball count).
        if (_currentBowl?.isWide == true && !ball.wasHitByBat) {
          _callWide();
          return;
        }
        if (_runsThisBall > 0) {
          scoreManager.addRuns(_runsThisBall);
          _outcomeRuns = _runsThisBall;
          _runsThisBall = 0;
        }
        striker.resetIdle();
        nonStriker.resetIdle();
        _sendFieldersHome();
        _finishDelivery();

      case RunTaken():
        break;

      case ScoreChanged():
        break;

      case BallSettled():
        // HUD-only event; CricketGame fires it but ignores incoming.
        break;

      case ExtraCalled():
        // HUD-only event; CricketGame fires it via _callWide / _callNoBall.
        break;

      case RunOutCalled():
        // HUD-only event; CricketGame fires it via _attemptRunOut.
        break;

      case ShotQualityCalled():
        // HUD-only event; CricketGame fires it from BatContact.
        break;
    }
  }

  // ── Run-out: physics-based throw ─────────────────────────────────────────
  // Replaces the old probability roll. When a fielder gets to the ball while
  // the striker is mid-stride and at least one run is in flight, they throw
  // at the stumps. Outcome is decided by the live race between the throw
  // (constant `kThrowSpeed`) and the batsman's remaining run progress —
  // close fielders beat the batsman home, deep fielders rarely do.
  bool _throwInProgress = false;
  Fielder? _throwingFielder;

  Vector2 get _stumpsCentre => Vector2(
        stumps.position.x + stumps.size.x / 2,
        stumps.position.y + stumps.size.y / 2,
      );

  /// Begin a run-out attempt — the fielder rifles the ball at the stumps.
  /// `WicketFallen` (stumps hit) or `BallDead` (throw missed) will resolve.
  /// Difficulty's `runOutMultiplier` modulates the throw speed so Easy / Hard
  /// keep their fielding-pressure deltas from the old probabilistic version.
  void _startThrow(Fielder fielder) {
    _throwInProgress = true;
    _throwingFielder = fielder;
    fielder.flashHighlight();
    HapticService.instance.light();
    // Tiny pickup delay so the player sees "fielder has it" before the throw
    // whips out. Skipped if the engine is paused (defensive).
    Future.delayed(
      Duration(milliseconds: (kThrowReactionSec * 1000).round()),
      () {
        if (phase != GamePhase.playing) return;
        if (!_throwInProgress) return;
        // Speed scales with difficulty so Easy throws are slower (more
        // forgiving), Hard throws are faster (harder to make ground).
        final speed = kThrowSpeed * settings.runOutMultiplier;
        ball.throwTo(_stumpsCentre, speed: speed);
        SoundService.instance.run(); // re-purpose run whoosh as throw whoosh
      },
    );
  }

  /// Throw arrived at the stumps — settle the run-out vs safe outcome based
  /// on whether the batsman has reached their crease yet.
  void _resolveThrowAtStumps() {
    final by = _throwingFielder;
    _throwInProgress = false;
    _throwingFielder = null;

    if (striker.isRunning) {
      // Mid-stride when the bails came off — batsman is short of the crease.
      // Only the runs already completed count; the in-flight one doesn't.
      final completed = math.max(0, _runsThisBall - 1);
      _runsThisBall = 0;
      if (completed > 0) scoreManager.addRuns(completed);
      _outcomeRuns = completed;
      _outcomeWicket = true;
      scoreManager.addWicket();
      stumps.flyBails();
      shakeScreen(10);
      SoundService.instance.wicket();
      HapticService.instance.heavy();
      if (by != null) eventBus.fire(RunOutCalled(completed, by.fieldPosition));
    } else {
      // Batsman made the crease before the ball arrived — all runs stand.
      if (_runsThisBall > 0) {
        scoreManager.addRuns(_runsThisBall);
        _outcomeRuns = _runsThisBall;
        _runsThisBall = 0;
      }
    }
    striker.resetIdle();
    nonStriker.resetIdle();
    _sendFieldersHome();
    _finishDelivery();
  }

  /// Throw missed — went off-screen / fielder fumbled. All runs stand.
  void _resolveThrowMissed() {
    _throwInProgress = false;
    _throwingFielder = null;
    if (_runsThisBall > 0) {
      scoreManager.addRuns(_runsThisBall);
      _outcomeRuns = _runsThisBall;
      _runsThisBall = 0;
    }
    striker.resetIdle();
    nonStriker.resetIdle();
    _sendFieldersHome();
    _finishDelivery();
  }

  /// Player pressed R — take a run. Score isn't committed yet; final tally is
  /// awarded when the delivery ends (so a boundary cleanly supersedes pending
  /// runs). Capped by cooldown + max-runs. Animates BOTH batsmen — they run
  /// past each other to swap ends.
  void _takeRun() {
    if (!_runningActive) return;
    if (_runsThisBall >= kMaxRunsPerBall) return;
    if (_gameTime - _lastRunAt < kRunCooldownSec) return;
    _lastRunAt = _gameTime;
    _runsThisBall += 1;
    striker.runToOtherEnd(kRunCooldownSec);
    nonStriker.runToOtherEnd(kRunCooldownSec);
    add(RunPopup(
      origin: Vector2(
        striker.position.x + striker.size.x / 2,
        striker.position.y - 8,
      ),
      runs: 1,
    ));
    SoundService.instance.run();
    HapticService.instance.selection();
    eventBus.fire(RunTaken(_runsThisBall));
  }

  /// Swap which physical Batsman is on strike. Called after odd running
  /// runs and at end of over (the visual swap is already done by the run
  /// animation; this just updates the *reference* so subsequent calls to
  /// `striker.X` target the batsman now at the bottom crease).
  void _swapStrike() {
    final tmp = striker;
    striker = nonStriker;
    nonStriker = tmp;
  }

  /// Reset the field so a "new partnership" is set up at start of innings,
  /// after a wicket, or on game restart. Both batsmen go to their original
  /// home ends; the strike reference snaps to the original `striker`
  /// (whoever started the innings at the bottom).
  void _newPartnership() {
    // If references were swapped earlier (mid-innings odd-run rotation),
    // unswap so the bat-equipped striker is the one whose home is the
    // bottom crease.
    if (!striker.homeAtStriker) _swapStrike();
    striker.recenterHome();
    nonStriker.recenterHome();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _gameTime += dt;
    if (_shake > 0) {
      _shake = (_shake - dt * 40).clamp(0.0, 60.0);
    }

    // Batsman lateral movement — A / ← move toward leg side, D / → toward off.
    // Disabled outside active play so paused / menu state can't be edited.
    if (phase == GamePhase.playing) {
      double v = 0;
      if (_heldKeys.contains(LogicalKeyboardKey.keyA) ||
          _heldKeys.contains(LogicalKeyboardKey.arrowLeft)) {
        v -= 1;
      }
      if (_heldKeys.contains(LogicalKeyboardKey.keyD) ||
          _heldKeys.contains(LogicalKeyboardKey.arrowRight)) {
        v += 1;
      }
      batsman.lateralVelocity = v;
    } else {
      batsman.lateralVelocity = 0;
    }

    // Ground shots: chaser tracks the live ball every frame. Lofted shots:
    // chaser already committed to the predicted landing point on contact, so
    // we do NOT update it — outfielders aren't perfect ball-trackers, which
    // is what gives the player a real chance at clearing the rope.
    final chaser = _chasingFielder;
    if (chaser != null &&
        !_lastShotWasLofted &&
        ball.ballState != BallState.dead) {
      chaser.chaseTo(Vector2(
        ball.position.x + ball.size.x / 2,
        ball.position.y + ball.size.y / 2,
      ));
    }
  }

  /// Trigger a screen-shake of [amount] pixels. Decays automatically.
  void shakeScreen(double amount) {
    if (amount > _shake) _shake = amount;
  }

  @override
  void render(ui.Canvas canvas) {
    if (_shake > 0.1) {
      final dx = (_shakeRng.nextDouble() - 0.5) * _shake * 2;
      final dy = (_shakeRng.nextDouble() - 0.5) * _shake * 2;
      canvas.save();
      canvas.translate(dx, dy);
      super.render(canvas);
      canvas.restore();
    } else {
      super.render(canvas);
    }
  }

  /// Pick the fielder closest to where the ball is heading. Looks `kFielderChaseLookaheadSec`
  /// seconds ahead along the ball's velocity vector so we bias toward the
  /// shot direction, not the bat's current position.
  Fielder? _pickChaser(Vector2 ballVelocity) {
    if (fielders.isEmpty) return null;
    final ballCentre = Vector2(
      ball.position.x + ball.size.x / 2,
      ball.position.y + ball.size.y / 2,
    );
    final lookahead = ballCentre + ballVelocity * kFielderChaseLookaheadSec;
    return _pickChaserNearPoint(lookahead);
  }

  /// Pick the fielder closest to a fixed world point. Used for lofted shots,
  /// where the chaser commits to the predicted landing spot once instead of
  /// tracking the ball through the air. The keeper is excluded — they're a
  /// stationary catcher for edges, not an active chaser. Pass [exclude] to
  /// skip already-assigned fielders (e.g. when picking the backup behind
  /// the primary chaser).
  Fielder? _pickChaserNearPoint(
    Vector2 point, {
    Set<FieldPosition>? exclude,
  }) {
    if (fielders.isEmpty) return null;
    Fielder? best;
    double bestDistSq = double.infinity;
    for (final f in fielders.values) {
      if (f.fieldPosition == FieldPosition.keeper) continue;
      if (exclude != null && exclude.contains(f.fieldPosition)) continue;
      final d2 = (f.centre - point).length2;
      if (d2 < bestDistSq) {
        bestDistSq = d2;
        best = f;
      }
    }
    return best;
  }

  /// Compute the backup point — `kBackupOffsetPx` past `primaryPoint` along
  /// the ball's velocity vector. The backup commits here so they're in
  /// position if the ball slips past the primary chaser.
  Vector2 _computeBackupPoint(Vector2 primaryPoint, Vector2 ballVelocity) {
    if (ballVelocity.length == 0) return primaryPoint;
    return primaryPoint + ballVelocity.normalized() * kBackupOffsetPx;
  }

  /// Approximate where a lofted ball will land (return to launch height) given
  /// its rebound velocity. Uses pure ballistic kinematics with `kGravity` —
  /// ignores horizontal deceleration since it only kicks in once the ball is
  /// rolling.
  Vector2 _predictLandingPoint(Vector2 vel) {
    final ballCentre = Vector2(
      ball.position.x + ball.size.x / 2,
      ball.position.y + ball.size.y / 2,
    );
    if (vel.y >= 0) return ballCentre; // already descending — land here-ish
    final tFlight = -2 * vel.y / kGravity; // up + down
    return Vector2(
      ballCentre.x + vel.x * tFlight,
      ballCentre.y,
    );
  }

  void _sendFieldersHome() {
    _chasingFielder = null;
    _backupFielder = null;
    _lastShotWasLofted = false;
    for (final f in fielders.values) {
      f.returnHome();
    }
  }

  void _broadcastScore() {
    eventBus.fire(ScoreChanged(
      scoreString: scoreManager.scoreString,
      overString: scoreManager.overString,
      runRate: scoreManager.runRate,
      target: innings == Innings.aiBats ? target : null,
    ));
  }

  // ── Public API called from overlay widgets ─────────────────────────────────
  void startGame([MatchSettings? newSettings]) {
    if (newSettings != null) _applySettings(newSettings);
    overlays.remove('MainMenu');
    scoreManager.reset();
    striker.resetStats();
    nonStriker.resetStats();
    for (final s in bowlerStats.values) {
      s.reset();
    }
    innings = Innings.playerBats;
    firstInningsScore = null;
    target = null;
    _playerStats = null;
    phase = GamePhase.playing;
    stateNotifier.setPhase(GamePhase.playing);
    stateNotifier.setInnings(innings, target: target);
    _broadcastScore();
    _scheduleNextDelivery();
  }

  void _applySettings(MatchSettings s) {
    settings = s;
    scoreManager.maxOvers = s.maxOvers;
    scoreManager.maxWickets = s.maxWickets;
    aiManager.minSpeed = s.minBallSpeed;
    aiManager.maxSpeed = s.maxBallSpeed;
    bowler.runUpSec = s.runUpSec;
    striker.swingWindowSec = s.swingWindowSec;
    nonStriker.swingWindowSec = s.swingWindowSec;
    // Tier 2: fielding scales with difficulty
    for (final f in fielders.values) {
      f.speed = kFielderSpeed * s.fielderSpeedMul;
      f.maxChaseDistance = s.fielderMaxChase;
    }
  }

  void togglePause() {
    if (phase == GamePhase.playing) {
      phase = GamePhase.paused;
      stateNotifier.setPhase(GamePhase.paused);
      pauseEngine();
      overlays.add('Pause');
    } else if (phase == GamePhase.paused) {
      phase = GamePhase.playing;
      stateNotifier.setPhase(GamePhase.playing);
      resumeEngine();
      overlays.remove('Pause');
      // If we paused inside the gap between two deliveries, the queued
      // `Future.delayed` callback ran (without effect) while paused, so
      // nothing is going to schedule the next ball. Re-kick it here.
      // Same fix recovers a pause taken during the innings-change pause
      // in chase mode — without this the game appeared "stuck".
      if (_pendingDeliveryScheduled && ball.ballState != BallState.inFlight) {
        _pendingDeliveryScheduled = false;
        ball.reset();
        striker.resetIdle();
        nonStriker.resetIdle();
        _scheduleNextDelivery();
      }
    }
  }

  void restartGame() {
    phase = GamePhase.playing;
    stateNotifier.setPhase(GamePhase.playing);
    if (paused) resumeEngine();
    overlays.remove('GameOver');
    overlays.remove('Pause');
    scoreManager.reset();
    ball.reset();
    _newPartnership();
    striker.resetStats();
    nonStriker.resetStats();
    for (final s in bowlerStats.values) {
      s.reset();
    }
    bowler.cancel();
    _sendFieldersHome();
    _throwInProgress = false;
    _throwingFielder = null;
    _inputEnabled = false;
    _setRunning(false);
    _runsThisBall = 0;
    innings = Innings.playerBats;
    firstInningsScore = null;
    target = null;
    _playerStats = null;
    stateNotifier.setInnings(innings);
    stateNotifier.setFirstInningsScore(null);
    SaveService.instance.clear();
    _broadcastScore();
    _scheduleNextDelivery();
  }

  /// Exit the active innings and return to the main menu so the player can
  /// pick a new format / difficulty. Safe to call from Pause or GameOver.
  void quitToMenu() {
    phase = GamePhase.mainMenu;
    stateNotifier.setPhase(GamePhase.mainMenu);
    if (paused) resumeEngine();
    overlays.remove('Pause');
    overlays.remove('GameOver');
    scoreManager.reset();
    ball.reset();
    _newPartnership();
    striker.resetStats();
    nonStriker.resetStats();
    for (final s in bowlerStats.values) {
      s.reset();
    }
    bowler.cancel();
    _sendFieldersHome();
    _throwInProgress = false;
    _throwingFielder = null;
    _inputEnabled = false;
    _setRunning(false);
    _runsThisBall = 0;
    innings = Innings.playerBats;
    firstInningsScore = null;
    target = null;
    _playerStats = null;
    stateNotifier.setInnings(innings);
    stateNotifier.setFirstInningsScore(null);
    overlays.add('MainMenu');
  }

  // ── AI batsman (chase mode) ────────────────────────────────────────────
  /// Schedule the AI's swing for the current delivery. The reaction time
  /// is randomized so the AI sometimes mistimes (= no swing). Direction +
  /// force + power are also randomized so the AI plays a varied innings.
  void _scheduleAiSwing() {
    final rng = _shakeRng;
    // Skip the swing entirely ~15% of the time → pure dot or wicket.
    if (rng.nextDouble() < 0.15) return;
    // Aim for the swing window, jittered slightly so the AI can be early /
    // late and miss the ball cleanly.
    final swingWindow = batsman.swingWindowSec;
    final reactionMs = ((bowler.runUpSec * 0.40 +
                _ballFlightEstimateSec() * 0.55 +
                (rng.nextDouble() - 0.5) * swingWindow * 0.5) *
            1000)
        .clamp(220.0, 2400.0);
    Future.delayed(Duration(milliseconds: reactionMs.toInt()), () {
      if (phase != GamePhase.playing) return;
      if (innings != Innings.aiBats) return;
      if (ball.ballState == BallState.dead) return;
      // Random direction biased upward (toward bowler) — that's where most
      // attacking shots land in cricket.
      final dx = (rng.nextDouble() - 0.5) * 2; // -1..1
      final dy = -(0.4 + rng.nextDouble() * 0.6); // -0.4..-1.0
      final force = 0.65 + rng.nextDouble() * 0.35;
      // Power on more often when the AI is behind required rate.
      final pressure = _aiPressure();
      final powerOn = rng.nextDouble() < (0.30 + pressure * 0.55);
      batsman.playSwing(
        ShotIntent.directed(
          direction: Vector2(dx, dy),
          force: force,
          powerOn: powerOn,
        ),
      );
      // After a successful contact the running window opens — schedule a
      // few automatic R presses so the AI takes 0–2 quick singles.
      _scheduleAiRuns(rng);
    });
  }

  /// Estimated time (s) for the ball to reach the bat — used to time the
  /// AI's swing. Crude: distance / speed.
  double _ballFlightEstimateSec() {
    final speed = _currentBowl?.speed ?? 400;
    return size.y * 0.42 / speed;
  }

  /// 0..1 representing how desperate the AI is for runs. Used to bias
  /// toward power shots in the back end of a chase.
  double _aiPressure() {
    if (target == null) return 0.0;
    final ballsRemaining =
        scoreManager.maxOvers * kBallsPerOver - scoreManager.ballsBowled;
    if (ballsRemaining <= 0) return 1.0;
    final runsNeeded = (target! - scoreManager.runs).clamp(0, 999);
    final required = runsNeeded * 6 / ballsRemaining;
    return (required / 12).clamp(0.0, 1.0);
  }

  /// Schedule 0–2 automatic single-runs after a contact, with realistic
  /// gaps. Stops as soon as the running window closes.
  void _scheduleAiRuns(math.Random rng) {
    final n = rng.nextInt(3); // 0, 1, or 2
    for (var i = 1; i <= n; i++) {
      Future.delayed(
        Duration(milliseconds:
            (kRunCooldownSec * 1000 * (i + 0.4 + rng.nextDouble() * 0.4)).toInt()),
        () {
          if (innings != Innings.aiBats) return;
          if (!_runningActive) return;
          _takeRun();
        },
      );
    }
  }

  /// First innings ended in chase mode. Snapshot the score, reset the
  /// scoreboard, set up the AI target, and start the second innings.
  void _transitionToSecondInnings() {
    firstInningsScore = ScoreSnapshot(
      runs: scoreManager.runs,
      wickets: scoreManager.wickets,
      oversCompleted: scoreManager.oversCompleted,
      currentBallInOver: scoreManager.currentBallInOver,
    );
    _playerStats = _PlayerInningsStats(
      runs: scoreManager.runs,
      wickets: scoreManager.wickets,
      fours: scoreManager.fours,
      sixes: scoreManager.sixes,
    );
    stateNotifier.setFirstInningsScore(firstInningsScore);
    target = scoreManager.runs + 1;
    scoreManager.reset();
    // Reset per-batsman + per-bowler stats — the AI's innings tallies fresh.
    striker.resetStats();
    nonStriker.resetStats();
    for (final s in bowlerStats.values) {
      s.reset();
    }
    innings = Innings.aiBats;
    stateNotifier.setInnings(innings, target: target);
    _broadcastScore();
    _inputEnabled = false;
    _setRunning(false);
    ball.reset();
    _newPartnership();
    _sendFieldersHome();
    // Brief pause before the AI batsman starts — gives the player time to
    // read the target.
    _saveProgress();
    _pendingDeliveryScheduled = true;
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (phase == GamePhase.playing) _scheduleNextDelivery();
      _pendingDeliveryScheduled = false;
    });
  }

  /// Snapshot the in-progress match for cold-start resume. Called between
  /// deliveries from `_finishDelivery` and `_transitionToSecondInnings`.
  void _saveProgress() {
    if (innings == Innings.complete) return;
    final fi = firstInningsScore;
    SaveService.instance.save(SavedMatch(
      format: settings.format,
      difficulty: settings.difficulty,
      chase: settings.chase,
      runs: scoreManager.runs,
      wickets: scoreManager.wickets,
      ballsBowled: scoreManager.ballsBowled,
      oversCompleted: scoreManager.oversCompleted,
      history: List.of(scoreManager.ballHistory),
      innings: innings,
      firstInningsRuns: fi?.runs,
      firstInningsWickets: fi?.wickets,
      firstInningsOversCompleted: fi?.oversCompleted,
      firstInningsCurrentBallInOver: fi?.currentBallInOver,
      target: target,
    ));
  }

  /// Resume an earlier match from a `SavedMatch` snapshot. Called by the
  /// main menu's RESUME button instead of `startGame`.
  void resumeMatch(SavedMatch saved) {
    _applySettings(MatchSettings(
      format: saved.format,
      difficulty: saved.difficulty,
      chase: saved.chase,
    ));
    overlays.remove('MainMenu');
    scoreManager.reset();
    scoreManager.runs = saved.runs;
    scoreManager.wickets = saved.wickets;
    scoreManager.ballsBowled = saved.ballsBowled;
    scoreManager.oversCompleted = saved.oversCompleted;
    scoreManager.ballHistory.addAll(saved.history);
    innings = saved.innings;
    if (saved.firstInningsRuns != null) {
      firstInningsScore = ScoreSnapshot(
        runs: saved.firstInningsRuns!,
        wickets: saved.firstInningsWickets ?? 0,
        oversCompleted: saved.firstInningsOversCompleted ?? 0,
        currentBallInOver: saved.firstInningsCurrentBallInOver ?? 0,
      );
      stateNotifier.setFirstInningsScore(firstInningsScore);
    }
    target = saved.target;
    _playerStats = null;
    _runsThisBall = 0;
    _setRunning(false);
    _inputEnabled = false;
    phase = GamePhase.playing;
    stateNotifier.setPhase(GamePhase.playing);
    stateNotifier.setInnings(innings, target: target);
    _broadcastScore();
    _scheduleNextDelivery();
  }

  /// Match is over (either innings finished naturally, or AI in chase mode
  /// reached the target). Snapshot the final score and show GameOver.
  void _finalizeMatch() {
    phase = GamePhase.gameOver;
    innings = Innings.complete;
    stateNotifier.setFinalScore(ScoreSnapshot(
      runs: scoreManager.runs,
      wickets: scoreManager.wickets,
      oversCompleted: scoreManager.oversCompleted,
      currentBallInOver: scoreManager.currentBallInOver,
    ));
    stateNotifier.setInnings(innings, target: target);
    stateNotifier.setPhase(GamePhase.gameOver);
    pauseEngine();
    overlays.add('GameOver');

    // Persist aggregate stats. In chase mode `_playerStats` carries the
    // player's batting innings (the AI's score has already overwritten the
    // live `ScoreManager`). Otherwise pull from the live manager.
    final p = _playerStats;
    final playerRuns = p?.runs ?? scoreManager.runs;
    final playerWickets = p?.wickets ?? scoreManager.wickets;
    final playerFours = p?.fours ?? scoreManager.fours;
    final playerSixes = p?.sixes ?? scoreManager.sixes;
    // "Won" only meaningful in chase mode — defending the total = win.
    final playerWon = settings.chase &&
        target != null &&
        scoreManager.runs < target!;
    StatsService.instance.recordMatch(
      playerRuns: playerRuns,
      fours: playerFours,
      sixes: playerSixes,
      wickets: playerWickets,
      playerWon: playerWon,
    );
    SaveService.instance.clear();
  }

  /// Wide called — +1 extra, re-bowl the same delivery (no ball-count
  /// increment, no `BallSettled` outcome appended). Used only for wides
  /// where the batsman never connected; if they reached the bat, the wide
  /// flag is ignored and normal scoring applies.
  void _callWide() {
    scoreManager.addRuns(1);
    _runsThisBall = 0;
    eventBus.fire(const ExtraCalled(ExtraKind.wide, 1));
    SoundService.instance.run();
    HapticService.instance.medium();
    _broadcastScore();
    striker.resetIdle();
    nonStriker.resetIdle();
    _sendFieldersHome();
    _currentBowl = null;
    // Mark the inter-ball gap so togglePause can recover if the player
    // pauses while the wide is replaying — same pattern used by
    // `_finishDelivery` and `_transitionToSecondInnings`.
    _pendingDeliveryScheduled = true;
    Future.delayed(
      Duration(milliseconds: (kSettlingDelaySec * 1000).round()),
      () {
        if (phase == GamePhase.playing) {
          ball.reset();
          striker.resetIdle();
          nonStriker.resetIdle();
          _scheduleNextDelivery();
        }
        _pendingDeliveryScheduled = false;
      },
    );
  }

  // ── Delivery lifecycle ─────────────────────────────────────────────────────
  void _scheduleNextDelivery() {
    final config = aiManager.decideBowl(scoreManager.ballsBowled);
    bowler.prepareBowl(config);
  }

  void _finishDelivery() {
    // No-ball penalty — +1 to score, ball still counts. Fired before the
    // BallSettled outcome so the HUD banner is visible. (We don't fire on
    // wides because they re-bowl via _callWide and don't reach _finishDelivery.)
    if (_currentBowl?.isNoBall == true) {
      scoreManager.addRuns(1);
      eventBus.fire(const ExtraCalled(ExtraKind.noBall, 1));
      SoundService.instance.run();
      HapticService.instance.medium();
    }

    final outcome = BallOutcomeLabel.fromRunsThisBall(
      _outcomeRuns,
      wicket: _outcomeWicket,
    );
    scoreManager.recordOutcome(outcome);
    eventBus.fire(BallSettled(outcome));

    // ── Per-batsman attribution ──────────────────────────────────────────
    // The striker faced this delivery. Wides don't reach `_finishDelivery`
    // (they re-bowl via `_callWide`), so every ball here is "faced".
    striker.runs += _outcomeRuns;
    striker.ballsFaced += 1;
    if (_outcomeRuns == 4) striker.fours += 1;
    if (_outcomeRuns == 6) striker.sixes += 1;
    if (_outcomeWicket) striker.isOut = true;

    // ── Per-bowler attribution ───────────────────────────────────────────
    final bowlerKind = _currentBowl?.kind ?? BowlerKind.medium;
    final bStats = bowlerStats[bowlerKind]!;
    final noBallExtra = (_currentBowl?.isNoBall == true) ? 1 : 0;
    bStats.balls += 1;
    bStats.runs += _outcomeRuns + noBallExtra;
    bStats.currentOverRuns += _outcomeRuns + noBallExtra;
    if (_outcomeWicket) bStats.wickets += 1;

    // Capture for strike-rotation logic before resetting the per-ball outcome.
    final wasOddRuns = _outcomeRuns.isOdd;
    final wasWicket = _outcomeWicket;

    _outcomeRuns = 0;
    _outcomeWicket = false;
    _currentBowl = null;

    final overCompleted = scoreManager.nextBall();
    _broadcastScore();

    // Maiden detection — completed over with 0 runs conceded.
    if (overCompleted) {
      if (bStats.currentOverRuns == 0) bStats.maidens += 1;
      bStats.currentOverRuns = 0;
    }

    // Strike rotation:
    //   - Wicket: a "new partnership" comes in; both batsmen reset to home.
    //     The new striker is whoever started the innings at the bottom.
    //   - Odd running runs (1 / 3): batsmen physically swapped on each run,
    //     net result = strike has rotated.
    //   - End of over: in real cricket the bowler swaps ends, which means
    //     the previous non-striker now faces the next ball. We model that
    //     by also swapping the strike reference (so on the next ball the
    //     bat-equipped striker is whoever was at the non-striker's end).
    //     We don't physically swap creases — to keep the bowler at the top
    //     of the screen, the new striker walks across at over change.
    if (wasWicket) {
      _newPartnership();
    } else {
      final shouldSwap = wasOddRuns ^ overCompleted;
      if (shouldSwap) {
        _swapStrike();
        // At end of over (no wicket, no running rotation triggered the swap)
        // we also need a physical swap — both batsmen walk across so the
        // new striker ends up at the bottom crease facing the next ball.
        // Odd running runs already did the physical swap.
        if (overCompleted && !wasOddRuns) {
          striker.runToOtherEnd(kRunCooldownSec);
          nonStriker.runToOtherEnd(kRunCooldownSec);
        }
      }
    }

    final aiTargetReached =
        innings == Innings.aiBats && target != null && scoreManager.runs >= target!;
    if (scoreManager.isInningsOver || aiTargetReached) {
      // Player innings just ended — chase mode hands over to the AI.
      if (innings == Innings.playerBats && settings.chase) {
        _transitionToSecondInnings();
        return;
      }
      _finalizeMatch();
      return;
    }

    // Save mid-match progress — between deliveries the state is clean
    // (ball at the bowler, no in-flight components). Cold-start can
    // restore from this snapshot.
    _saveProgress();

    _pendingDeliveryScheduled = true;
    Future.delayed(
      Duration(milliseconds: (kSettlingDelaySec * 1000).round()),
      () {
        if (phase == GamePhase.playing) {
          ball.reset();
          striker.resetIdle();
          nonStriker.resetIdle();
          _scheduleNextDelivery();
        }
        _pendingDeliveryScheduled = false;
      },
    );
  }

  // ── Tap / swipe input ──────────────────────────────────────────────────────
  // Two callback families work in tandem:
  //   - TapCallbacks fires for stationary taps (= defensive block).
  //   - DragCallbacks fires for any actual finger movement. Flame routes
  //     these mutually exclusively, so a fast cover-drive swipe arrives as
  //     a *drag*, not a tap+up. Without DragCallbacks here those shots
  //     vanished entirely (onTapCancel, then nothing).
  Offset? _dragStart;
  Offset? _dragEnd;

  @override
  void onTapDown(TapDownEvent event) {
    _tapStart = Offset(event.localPosition.x, event.localPosition.y);
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (!_inputEnabled || _tapStart == null) return;
    // Pure tap (no drag) → defensive block.
    batsman.playSwing(
      _input.swipeToIntent(_tapStart!, _tapStart!, powerOn: powerOn.value),
    );
    _tapStart = null;
  }

  @override
  void onTapCancel(TapCancelEvent event) => _tapStart = null;

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!_inputEnabled) return;
    final p = Offset(event.localPosition.x, event.localPosition.y);
    _dragStart = p;
    _dragEnd = p;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (_dragEnd == null) return;
    // Flame's DragUpdateEvent only exposes deltas, so we integrate.
    _dragEnd = _dragEnd! +
        Offset(event.localDelta.x, event.localDelta.y);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    final start = _dragStart;
    final end = _dragEnd;
    _dragStart = null;
    _dragEnd = null;
    if (start == null || end == null || !_inputEnabled) return;
    batsman.playSwing(
      _input.swipeToIntent(start, end, powerOn: powerOn.value),
    );
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _dragStart = null;
    _dragEnd = null;
  }

  // ── Keyboard input (macOS / desktop / web) ─────────────────────────────────
  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    // Refresh held-key snapshot for `update(dt)` to consume — drives lateral
    // movement. Done on every event (Down / Up / Repeat) so releases register.
    _heldKeys = keysPressed.toSet();

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.keyP) {
      if (phase == GamePhase.playing || phase == GamePhase.paused) {
        togglePause();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // R = take a run between wickets (only valid after bat contact, while the
    // ball is still live and not yet caught/fielded/dead).
    if (event.logicalKey == LogicalKeyboardKey.keyR ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_runningActive) {
        _takeRun();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!_inputEnabled) return KeyEventResult.ignored;
    final intent = _intentForKey(event.logicalKey);
    if (intent == null) return KeyEventResult.ignored;
    batsman.playSwing(intent);
    return KeyEventResult.handled;
  }

  /// Note on bindings: arrow keys (← / →) and A / D are reserved for **lateral
  /// movement** of the batsman. Shots are mapped to dedicated letter keys so
  /// the two systems don't collide. C / V chosen because they sit next to
  /// each other on QWERTY (cover / straight drive — the two off-side shots).
  ///
  /// Each key fires a full-force `ShotIntent` in a fixed direction, with
  /// the current `powerOn` flag applied (lofted vs grounded). With free-
  /// direction swipes available on touch, keys are kept simple — four
  /// canonical directions.
  ShotIntent? _intentForKey(LogicalKeyboardKey key) {
    Vector2? dir;
    if (key == LogicalKeyboardKey.keyV) {
      dir = Vector2(0.05, -1); // straight drive (toward bowler)
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.keyW) {
      dir = Vector2(-0.5, -1); // pull shot (up + leg side)
    } else if (key == LogicalKeyboardKey.keyC) {
      dir = Vector2(-1, -0.5); // cover drive (left + slight up)
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS ||
        key == LogicalKeyboardKey.space) {
      return ShotIntent.defensive();
    }
    if (dir == null) return null;
    return ShotIntent.directed(
        direction: dir, force: 1.0, powerOn: powerOn.value);
  }

  @override
  void onRemove() {
    _eventSub?.cancel();
    eventBus.dispose();
    super.onRemove();
  }
}

/// Snapshot of the player's batting innings — taken at the end of their
/// innings so chase-mode (which then resets `ScoreManager` for the AI) can
/// still report the player's totals to `StatsService` at match end.
class _PlayerInningsStats {
  final int runs;
  final int wickets;
  final int fours;
  final int sixes;
  const _PlayerInningsStats({
    required this.runs,
    required this.wickets,
    required this.fours,
    required this.sixes,
  });
}
