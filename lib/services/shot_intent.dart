import 'dart:math' as math;

import 'package:flame/components.dart';

import '../utils/constants.dart';

/// How well the player timed the swing — measured from `swingProgress` at the
/// moment the bat collided with the ball. Drives the rebound:
///   - clean    → intended trajectory + full power
///   - mistimed → intended direction, ~55% power (drives die in the field)
///   - edge     → ball deflects backward toward the keeper, low power
enum ShotQuality { clean, mistimed, edge }

/// Carries a single shot — the player's intent for what the bat should do
/// with the next ball.
///
/// Replaces the legacy "swipe → ShotType bucket" model. Now we keep the
/// actual swipe direction as a unit vector + a normalized swipe length, and
/// pair it with a `powerOn` flag (lofted vs grounded). `ShotType` is still
/// derived for analytics / banner labels but is no longer the source of
/// truth for ball trajectory.
class ShotIntent {
  /// Unit vector in screen coords (x: -1=left, +1=right; y: -1=up toward bowler,
  /// +1=down toward batsman). `(0,0)` for a tap (= defensive block).
  final Vector2 direction;

  /// Swipe length normalized into 0..1. Longer swipe = harder hit.
  final double force;

  /// Lofted (true) vs grounded (false). Lofted shots fly into the air —
  /// boundary potential, but catchable. Ground shots stay low — usually 1s/4s.
  final bool powerOn;

  /// Categorical label, derived from [direction]. Used by the swing visual,
  /// HUD banner labels and existing per-shot logic — *not* by ball physics.
  final ShotType type;

  const ShotIntent({
    required this.direction,
    required this.force,
    required this.powerOn,
    required this.type,
  });

  /// A pure defensive block (tap or very short swipe). [powerOn] is ignored.
  factory ShotIntent.defensive() => ShotIntent(
        direction: Vector2.zero(),
        force: 0,
        powerOn: false,
        type: ShotType.defensive,
      );

  /// Player explicitly chose a directional shot. [direction] is normalized
  /// internally. [force] is clamped to 0..1.
  factory ShotIntent.directed({
    required Vector2 direction,
    required double force,
    required bool powerOn,
  }) {
    final f = force.clamp(0.0, 1.0);
    final dir = direction.length == 0 ? Vector2.zero() : direction.normalized();
    return ShotIntent(
      direction: dir,
      force: f,
      powerOn: powerOn,
      type: _typeFromDirection(dir),
    );
  }

  bool get isDefensive => type == ShotType.defensive;

  /// Bucket the angle into one of the 4 legacy `ShotType`s for visual /
  /// labelling purposes. Not used for trajectory.
  static ShotType _typeFromDirection(Vector2 dir) {
    if (dir.length < 0.05) return ShotType.defensive;
    // Use screen-up convention: angle 0 = right, π/2 = up (toward bowler).
    final a = math.atan2(-dir.y, dir.x); // flip y so up is +
    final deg = (a * 180 / math.pi + 360) % 360;
    if (deg >= 315 || deg < 45) return ShotType.straightDrive; // right-ish
    if (deg >= 45 && deg < 135) return ShotType.pullShot; // upward (toward bowler)
    if (deg >= 135 && deg < 225) return ShotType.coverDrive; // left-ish
    return ShotType.defensive; // downward (back at batsman)
  }
}
