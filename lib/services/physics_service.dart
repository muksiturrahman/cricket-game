import 'dart:math' as math;

import 'package:flame/components.dart';

import 'shot_intent.dart';

/// Computes the ball's velocity *after* a bat hit, given the player's
/// `ShotIntent`, the incoming ball speed, and how well the swing was timed.
///
/// Three scaling factors matter:
///   - `force` (0..1) — swipe length, scales the magnitude
///   - `powerOn` — if true, the ball is lofted (vy biased upward); if false
///     the ball stays low (vy capped to a small skip)
///   - `quality` — how well the player timed the swing. Mistimes drop power;
///     edges deflect the ball backward toward the keeper.
class PhysicsService {
  final math.Random _rng = math.Random();

  Vector2 reboundVelocity(
    ShotIntent intent,
    double incomingSpeed, {
    ShotQuality quality = ShotQuality.clean,
  }) {
    // Edges short-circuit the intended trajectory — ball deflects backward
    // toward the keeper regardless of swipe direction. Sign of x-deflection
    // is randomized so edges sometimes go for byes wide of the keeper.
    if (quality == ShotQuality.edge) {
      final lateral = (_rng.nextDouble() - 0.5) * incomingSpeed * 0.35;
      // +y = down toward the keeper (who sits at y ≈ 0.80 of screen).
      final back = incomingSpeed * 0.55;
      return Vector2(lateral, back);
    }

    // Defensive block — soft downward, regardless of power. Matches the
    // legacy "stays at the batsman's feet" behaviour.
    if (intent.isDefensive) {
      return Vector2(0, incomingSpeed * 0.80 * 0.15);
    }

    final base = incomingSpeed * 0.80;
    // Map swipe force 0..1 → magnitude 0.55×..1.0× of the incoming speed.
    var magnitude = base * (0.55 + 0.45 * intent.force);
    // Mistime — ball came off the bat but with a fraction of the power.
    // Drives die in the field; lofted shots fall short of the rope.
    if (quality == ShotQuality.mistimed) {
      magnitude *= 0.55;
    }
    final dx = intent.direction.x;
    final dy = intent.direction.y;

    if (intent.powerOn) {
      // Lofted shot — biased upward, but only a clean upward swipe at full
      // force lofts hard enough to clear the rope. A sideways or weak swipe
      // is a high four/catch-zone shot, not an automatic six.
      //
      // Tuning: with magnitude ≤ 320 and gravity 180, the ball clears the
      // ~330 px boundary only when vy ≲ -345 px/s (peak height = vy²/2g).
      //   Full force + dy=-1: liftedDy = -1.05 → vy = -336 → just borderline.
      //   Full force + dy=0  : liftedDy = -0.30 → vy = -96 → never a six.
      //   Half force + dy=-1: vy = -260 → no clear, lands deep (4).
      var liftedDy = dy * 0.75 - 0.30;
      if (liftedDy > -0.20) liftedDy = -0.20;
      return Vector2(dx * magnitude, liftedDy * magnitude);
    } else {
      // Ground shot — clamp the vertical component so the ball never lifts
      // more than a tiny skip (~0.15 of magnitude upward). Forward energy
      // becomes horizontal speed, not height.
      final flatDy = dy.clamp(-0.15, 0.40);
      return Vector2(dx * magnitude, flatDy * magnitude);
    }
  }
}
