import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../services/shot_intent.dart';
import '../services/sprite_service.dart';
import '../utils/constants.dart';
import 'ai_manager.dart';
import 'bat.dart';
import 'fielder.dart';
import 'stumps.dart';

class Ball extends CircleComponent with HasGameReference, CollisionCallbacks {
  Ball()
      : super(
          radius: kBallRadius,
          priority: 5,
          paint: Paint()..color = kColorBall,
        );

  Vector2 velocity = Vector2.zero();
  BallState ballState = BallState.waiting;
  bool collisionProcessed = false;
  bool wasHitByBat = false;
  double _settleTimer = 0;

  /// Set by `throwTo()` — when true, `update(dt)` skips gravity, deceleration,
  /// boundary detection and settle detection so the ball flies straight at
  /// constant velocity (a fielder's throw at the stumps). Cleared on
  /// `_placeAtBowler()` so the next delivery starts clean.
  bool _throwing = false;
  bool get isThrowing => _throwing;

  /// Lateral kick (px/s) applied at the next pitch bounce — non-zero only
  /// for spinner deliveries. Consumed (zeroed) after the bounce fires so
  /// it doesn't keep deflecting on later in-flight rebounds.
  double _pendingDeflection = 0;

  /// Restitution to apply on the *first* bounce after launch. Set in
  /// `launch()` based on `BowlConfig.length` — yorker barely lifts, short
  /// ball rears up. Subsequent bounces fall back to `kBounceRestitution`.
  double _firstBounceRestitution = kBounceRestitution;
  bool _isFirstBounce = false;

  /// Pitch-type multiplier applied to all bounce restitutions (first and
  /// later). 1.0 = flat. > 1 for green pitches (extra bounce), < 1 for
  /// turning pitches (low bounce). Written by `CricketGame._applySettings`.
  double bounceMultiplier = 1.0;

  /// Past world-positions used to render the motion trail. Newest first.
  final List<Vector2> _trail = [];

  /// Accumulated rotation (radians) for the spinning seam.
  double _spin = 0;

  // Screen size cached at onLoad to avoid game reference in update
  Vector2 _screenSize = Vector2.zero();

  // Callbacks set by CricketGame
  void Function(ShotIntent intent)? onBatHit;
  void Function()? onStumpsHit;
  void Function()? onBallDead;
  void Function(Fielder fielder)? onCaught;
  void Function(Fielder fielder)? onFielded;
  /// Fires when a hit ball clears the screen edge. `runs` = 6 if the ball
  /// never bounced, otherwise 4.
  void Function(int runs)? onBoundary;

  /// Fired the instant the ball touches the pitch (a bounce). The argument
  /// is the world-space contact point — used to spawn a dust puff effect.
  void Function(Vector2 worldPos)? onBounce;

  @override
  Future<void> onLoad() async {
    _screenSize = game.size.clone();
    add(CircleHitbox()..collisionType = CollisionType.active);
    _placeAtBowler();
  }

  /// Send the ball straight toward [worldTarget] at [speed] px/s — used by
  /// `CricketGame` to model a fielder throwing at the stumps for a run-out.
  /// During a throw the ball ignores gravity, deceleration, boundary rules
  /// and settle detection. `wasHitByBat` is cleared so the safety-net path
  /// fires `onBallDead` (= safe outcome) if the throw misses the stumps.
  void throwTo(Vector2 worldTarget, {required double speed}) {
    final ballCentre = position + Vector2.all(radius);
    final dir = worldTarget - ballCentre;
    if (dir.length == 0) return;
    velocity = dir.normalized() * speed;
    ballState = BallState.inFlight;
    collisionProcessed = false;
    wasHitByBat = false;
    _throwing = true;
    _settleTimer = 0;
    _trail.clear();
  }

  void _placeAtBowler() {
    position = Vector2(_screenSize.x / 2 - radius, _screenSize.y * 0.28);
    velocity = Vector2.zero();
    ballState = BallState.waiting;
    collisionProcessed = false;
    wasHitByBat = false;
    _settleTimer = 0;
    _pendingDeflection = 0;
    _throwing = false;
    _isFirstBounce = false;
    _trail.clear();
    _spin = 0;
  }

  void launch(BowlConfig config) {
    final rad = config.swingAngle * math.pi / 180.0;
    velocity = Vector2(config.speed * 0.12 * rad, config.speed);
    // Wides get a lateral starting offset so the ball arrives off the bat.
    if (config.lateralOffsetPx != 0) {
      position = Vector2(position.x + config.lateralOffsetPx, position.y);
    }
    // Spinner deflection — consumed at the next bounce.
    _pendingDeflection = config.bounceDeflection;
    // Length-based first-bounce restitution.
    _firstBounceRestitution = switch (config.length) {
      BowlLength.yorker => kBounceRestitutionYorker,
      BowlLength.fullToss => kBounceRestitutionFullToss,
      BowlLength.goodLength => kBounceRestitutionGoodLength,
      BowlLength.shortPitch => kBounceRestitutionShortPitch,
    };
    _isFirstBounce = true;
    ballState = BallState.inFlight;
    collisionProcessed = false;
  }

  void reset() => _placeAtBowler();

  @override
  void update(double dt) {
    if (ballState == BallState.waiting || ballState == BallState.dead) return;

    // Throw mode — straight-line ballistic toward the stumps. No gravity, no
    // bounce, no boundary; just translate. Off-screen → onBallDead (treated
    // as a fumbled / missed throw by `CricketGame`).
    if (_throwing) {
      position += velocity * dt;
      // Trail sample so the throw renders with motion blur.
      final centerNow = position + Vector2.all(radius);
      if (_trail.isEmpty ||
          (_trail.first - centerNow).length >= kBallTrailSampleStep) {
        _trail.insert(0, centerNow.clone());
        if (_trail.length > kBallTrailMaxSamples) _trail.removeLast();
      }
      _spin += velocity.length * dt * 0.04;
      // Off-screen safety — fielder fumbled the throw, fire onBallDead.
      if (position.y > _screenSize.y + 40 ||
          position.y < -40 ||
          position.x < -40 ||
          position.x > _screenSize.x + 40) {
        ballState = BallState.dead;
        velocity = Vector2.zero();
        _throwing = false;
        onBallDead?.call();
      }
      return;
    }

    // Gravity
    velocity.y += kGravity * dt;

    // Horizontal deceleration when rolling
    if (velocity.y > 0) {
      final decel = kRollDeceleration * dt;
      if (velocity.x.abs() > decel) {
        velocity.x -= velocity.x.sign * decel;
      } else {
        velocity.x = 0;
      }
    }

    position += velocity * dt;

    // Record a trail sample if we've moved far enough since the last one.
    final centerNow = position + Vector2.all(radius);
    if (_trail.isEmpty ||
        (_trail.first - centerNow).length >= kBallTrailSampleStep) {
      _trail.insert(0, centerNow.clone());
      if (_trail.length > kBallTrailMaxSamples) {
        _trail.removeLast();
      }
    }

    // Spin scales with horizontal velocity — gives a satisfying tumble.
    _spin += velocity.length * dt * 0.04;

    // Bounce at pitch level — first bounce uses length-specific restitution,
    // subsequent bounces use the default. Bat-hit balls always use default
    // (the rebound from the bat, not the bowler's pitch length).
    final pitchY = _screenSize.y * 0.70;
    if (position.y >= pitchY && velocity.y > 0) {
      position.y = pitchY;
      final wasFastBounce = velocity.y.abs() > 80;
      final baseRestitution = (_isFirstBounce && !wasHitByBat)
          ? _firstBounceRestitution
          : kBounceRestitution;
      final restitution = baseRestitution * bounceMultiplier;
      velocity.y = -velocity.y * restitution;
      if (velocity.y.abs() < 20) velocity.y = 0;
      _isFirstBounce = false;
      // Spinner — apply the lateral kick once, then clear it so subsequent
      // (post-bat) bounces don't keep deflecting.
      if (_pendingDeflection != 0 && !wasHitByBat) {
        velocity.x += _pendingDeflection;
        _pendingDeflection = 0;
      }
      ballState = BallState.afterBounce;
      if (wasFastBounce) {
        onBounce?.call(Vector2(position.x + radius, position.y + radius));
      }
    }

    // Boundary rope — a hit ball that crosses the visible white ellipse is a
    // 4 (rolled past after bouncing) or 6 (still airborne when crossing).
    if (wasHitByBat && _isOutsideBoundary(position)) {
      _markDead();
      return;
    }

    // Off-screen safety net — unhit ball drifting off, or any weird trajectory.
    if (position.y > _screenSize.y + 40 ||
        position.y < -40 ||
        position.x < -40 ||
        position.x > _screenSize.x + 40) {
      _markDead();
      return;
    }

    // Settled mid-field — ball came to rest in play, no fielder reached it,
    // no boundary cleared. End the delivery so any running runs commit (or,
    // for an unhit wide, so `_callWide` can re-bowl). The check intentionally
    // does NOT require `wasHitByBat`: a wide bowl loses energy through
    // bouncing + roll deceleration and frequently settles inside the field
    // without any fielder being able to reach it (fielder collisions also
    // require `wasHitByBat`). Without this, the game would freeze on every
    // wide that didn't quite roll off-screen — which is the common case.
    if (ballState == BallState.afterBounce &&
        velocity.length2 < kBallSettleSpeedSq) {
      _settleTimer += dt;
      if (_settleTimer >= kBallSettleSec) {
        ballState = BallState.dead;
        velocity = Vector2.zero();
        _settleTimer = 0;
        onBallDead?.call();
      }
    } else {
      _settleTimer = 0;
    }
  }

  bool _isOutsideBoundary(Vector2 pos) {
    final dx = pos.x - _screenSize.x / 2;
    final dy = pos.y - _screenSize.y / 2;
    final hw = _screenSize.x * kBoundaryWidthRatio / 2;
    final hh = _screenSize.y * kBoundaryHeightRatio / 2;
    return (dx * dx) / (hw * hw) + (dy * dy) / (hh * hh) > 1.0;
  }

  void _markDead() {
    if (ballState == BallState.dead) return;
    final wasFlying = ballState == BallState.inFlight;
    final wasRolling = ballState == BallState.afterBounce;
    // Capture vy before zeroing — a 6 requires the ball to be still
    // rising (or at apex) when it crosses the rope. If it has already
    // started descending without bouncing, it's a 4 (steep but not over).
    final vyAtDeath = velocity.y;
    ballState = BallState.dead;
    velocity = Vector2.zero();
    if (wasHitByBat && wasFlying && vyAtDeath <= 0) {
      onBoundary?.call(kBoundarySixRuns);
    } else if (wasHitByBat && (wasFlying || wasRolling)) {
      onBoundary?.call(kBoundaryFourRuns);
    } else {
      onBallDead?.call();
    }
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (collisionProcessed) return;

    if (other is Bat && other.active) {
      collisionProcessed = true;
      wasHitByBat = true;
      onBatHit?.call(other.currentIntent);
    } else if (other is Stumps) {
      collisionProcessed = true;
      onStumpsHit?.call();
      ballState = BallState.dead;
      velocity = Vector2.zero();
    } else if (other is Fielder && wasHitByBat) {
      final airborne = ballState == BallState.inFlight;
      // Real-cricket rule: a still-rising ball is too high overhead to
      // catch — let it pass through. Catches only count once the ball is
      // descending (post-apex). After-bounce always stops as a field.
      if (airborne && velocity.y < 0) {
        // Don't mark collisionProcessed — let the ball keep going and
        // potentially hit another fielder higher up the trajectory.
        return;
      }
      collisionProcessed = true;
      ballState = BallState.dead;
      velocity = Vector2.zero();
      if (airborne) {
        onCaught?.call(other);
      } else {
        onFielded?.call(other);
      }
    }
  }

  @override
  void render(Canvas canvas) {
    // Render trail in world space — translate back to (0,0) of this component
    // and draw past samples relative to current position.
    final ballCenter = position + Vector2.all(radius);
    for (int i = 0; i < _trail.length; i++) {
      final p = _trail[i];
      final t = i / _trail.length; // 0 = newest, 1 = oldest
      final alpha = (1 - t) * 0.55;
      final r = radius * (0.95 - t * 0.7);
      final dx = p.x - ballCenter.x + radius;
      final dy = p.y - ballCenter.y + radius;
      canvas.drawCircle(
        Offset(dx, dy),
        r,
        Paint()..color = kColorBall.withValues(alpha: alpha),
      );
    }

    // Drop shadow under ball — projects on the pitch level
    final shadowY = (_screenSize.y * 0.70) - position.y;
    if (shadowY > 0 && shadowY < _screenSize.y) {
      // closer to ground = smaller, sharper shadow
      final t = (shadowY / (_screenSize.y * 0.5)).clamp(0.0, 1.0);
      final shadowR = radius * (0.6 + t * 0.8);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(radius, shadowY + radius),
            width: shadowR * 2,
            height: shadowR * 0.6),
        Paint()..color = Colors.black.withValues(alpha: 0.30 * (1 - t * 0.5)),
      );
    }

    // Sprite path — if a `ball.png` is bundled, draw it (rotated by `_spin`)
    // and skip the procedural body / seam / stitches below. Otherwise fall
    // back to the canvas-drawn ball that ships by default.
    final sprite = SpriteService.instance.get('ball.png');
    if (sprite != null) {
      canvas.save();
      canvas.translate(radius, radius);
      canvas.rotate(_spin);
      sprite.render(
        canvas,
        position: Vector2(-radius, -radius),
        size: Vector2.all(radius * 2),
      );
      canvas.restore();
      return;
    }

    // Canvas fallback — ball body with subtle radial highlight.
    final c = Offset(radius, radius);
    canvas.drawCircle(c, radius, Paint()..color = kColorBall);
    canvas.drawCircle(
      Offset(radius - 2, radius - 3),
      radius * 0.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(
            center: Offset(radius - 2, radius - 3), radius: radius * 0.55)),
    );

    // Rotating seam — two short white arcs offset by the spin angle
    canvas.save();
    canvas.translate(radius, radius);
    canvas.rotate(_spin);
    final seamPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final seamRect = Rect.fromCircle(center: Offset.zero, radius: radius - 1);
    canvas.drawArc(seamRect, -0.6, 1.2, false, seamPaint);
    canvas.drawArc(seamRect, 3.14 - 0.6, 1.2, false, seamPaint);
    // Stitch ticks
    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;
    for (int i = -3; i <= 3; i++) {
      final a = i * 0.18;
      final r1 = radius - 2.5;
      final r2 = radius - 0.5;
      canvas.drawLine(
        Offset(math.cos(a) * r1, math.sin(a) * r1),
        Offset(math.cos(a) * r2, math.sin(a) * r2),
        tickPaint,
      );
      final b = math.pi + a;
      canvas.drawLine(
        Offset(math.cos(b) * r1, math.sin(b) * r1),
        Offset(math.cos(b) * r2, math.sin(b) * r2),
        tickPaint,
      );
    }
    canvas.restore();
  }
}
