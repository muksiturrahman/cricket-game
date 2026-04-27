import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/theme.dart';

class Fielder extends PositionComponent with HasGameReference {
  Fielder({required this.fieldPosition, required Vector2 anchorRatio})
      : _anchorRatio = anchorRatio,
        super(priority: 3);

  final FieldPosition fieldPosition;
  final Vector2 _anchorRatio;

  bool _highlight = false;
  double _highlightTimer = 0;

  /// Active when this fielder dove at the rope to save a boundary. Used by
  /// `render` to draw a momentarily-stretched body / motion blur.
  bool _diving = false;
  double _diveTimer = 0;

  /// Cached top-left position of the fielder's home spot (computed in onLoad).
  Vector2 _homePos = Vector2.zero();

  /// Per-innings tunable. Defaults to the constants but `MatchSettings`
  /// overrides them via `CricketGame._applySettings`. Catch radius itself is
  /// fixed at `kFielderCatchRadius` (the hitbox is built once in `onLoad`)
  /// — only speed + chase distance vary with difficulty.
  double speed = kFielderSpeed;
  double maxChaseDistance = kFielderMaxChaseDistance;

  /// Top-left destination the fielder is running toward. `null` ⇒ return to
  /// `_homePos`. Updated every frame by `CricketGame` while a chase is active.
  Vector2? _target;

  /// Returns the centre of the fielder in world coordinates — used by the
  /// chase-picker to compare against the ball's predicted centre.
  Vector2 get centre =>
      Vector2(position.x + size.x / 2, position.y + size.y / 2);

  @override
  Future<void> onLoad() async {
    final r = kFielderCatchRadius;
    size = Vector2.all(r * 2);
    position = Vector2(
      game.size.x * _anchorRatio.x - r,
      game.size.y * _anchorRatio.y - r,
    );
    _homePos = position.clone();
    add(CircleHitbox(radius: r)..collisionType = CollisionType.passive);
  }

  void flashHighlight() {
    _highlight = true;
    _highlightTimer = 0;
  }

  /// Trigger the boundary-save dive animation. Renders a stretched body +
  /// motion-blur trail for `kFielderDiveSec`.
  void dive() {
    _diving = true;
    _diveTimer = 0;
    _highlight = true;
    _highlightTimer = 0;
  }

  /// Chase a ball whose centre is at [ballCentre]. The fielder moves toward
  /// the ball so its own centre converges with the ball's.
  void chaseTo(Vector2 ballCentre) {
    _target = Vector2(ballCentre.x - size.x / 2, ballCentre.y - size.y / 2);
  }

  /// Stop chasing and lerp back to the home position.
  void returnHome() {
    _target = null;
  }

  /// Reposition this fielder's home spot — used by the captain-set field
  /// preset. Snaps the fielder to the new home if they're not currently
  /// chasing; otherwise the lerp-back-home logic will pull them there
  /// once the chase target clears.
  void setHome(Vector2 anchorRatio) {
    final r = kFielderCatchRadius;
    _homePos = Vector2(
      game.size.x * anchorRatio.x - r,
      game.size.y * anchorRatio.y - r,
    );
    if (_target == null) {
      position = _homePos.clone();
    }
  }

  @override
  void update(double dt) {
    if (_highlight) {
      _highlightTimer += dt;
      if (_highlightTimer >= kFielderHighlightSec) {
        _highlight = false;
        _highlightTimer = 0;
      }
    }
    if (_diving) {
      _diveTimer += dt;
      if (_diveTimer >= kFielderDiveSec) {
        _diving = false;
        _diveTimer = 0;
      }
    }

    var dest = _target ?? _homePos;
    // Clamp the destination to within max-chase-distance of home so we
    // never sprint across the field.
    if (_target != null) {
      final fromHome = dest - _homePos;
      if (fromHome.length > maxChaseDistance) {
        dest = _homePos + fromHome.normalized() * maxChaseDistance;
      }
    }
    final delta = dest - position;
    final dist = delta.length;
    if (dist > 0.5) {
      final step = speed * dt;
      if (step >= dist) {
        position = dest.clone();
      } else {
        position += delta.normalized() * step;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Drop shadow under fielder
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy + kFielderRadius * 0.85),
          width: kFielderRadius * 1.8,
          height: kFielderRadius * 0.5),
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );

    if (_highlight) {
      final t = (_highlightTimer / kFielderHighlightSec).clamp(0.0, 1.0);
      // Outer pulse ring
      canvas.drawCircle(
        Offset(cx, cy),
        kFielderCatchRadius + 4 + t * 12,
        Paint()
          ..color = kPalette.primary.withValues(alpha: 1.0 - t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      // Inner glow
      canvas.drawCircle(
        Offset(cx, cy),
        kFielderCatchRadius * (0.9 + t * 0.4),
        Paint()
          ..color = kPalette.primary.withValues(alpha: (1 - t) * 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // Boundary-save dive — flatten the body (taller-than-wide oval) and
    // paint a motion-blur smear behind. Briefly stretches outward as the
    // fielder slides at the rope.
    if (_diving) {
      final dt = (_diveTimer / kFielderDiveSec).clamp(0.0, 1.0);
      final stretch = 1.0 + (1 - (dt - 0.5).abs() * 2) * 0.55; // peaks mid-anim
      // Smear trail behind the body
      for (int i = 1; i <= 4; i++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx - i * 4.0, cy + 2),
            width: kFielderRadius * 2.2 * stretch,
            height: kFielderRadius * 1.5,
          ),
          Paint()
            ..color = kColorFielderKit.withValues(alpha: 0.18 - i * 0.035),
        );
      }
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, cy + 2),
          width: kFielderRadius * 2.2 * stretch,
          height: kFielderRadius * 1.5,
        ),
        Paint()..color = kColorFielderKit,
      );
      // Head trails behind during the dive
      canvas.drawCircle(
        Offset(cx + kFielderRadius * (stretch - 1.0) * 0.6,
            cy - kFielderRadius * 0.3),
        kFielderRadius * 0.55,
        Paint()..color = kColorSkin,
      );
      // Skip the standard upright body render below.
      return;
    }

    // Body — kit jersey base + collar accent
    final bodyCenter = Offset(cx, cy + 2);
    canvas.drawCircle(
      bodyCenter,
      kFielderRadius,
      Paint()..color = kColorFielderKit,
    );
    // Body highlight (top curve)
    canvas.drawArc(
      Rect.fromCircle(center: bodyCenter, radius: kFielderRadius),
      3.6,
      1.8,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // Side stripes
    canvas.drawArc(
      Rect.fromCircle(
          center: bodyCenter, radius: kFielderRadius - 0.5),
      -1.6,
      0.5,
      false,
      Paint()
        ..color = kPalette.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // Head
    canvas.drawCircle(
      Offset(cx, cy - kFielderRadius * 0.6),
      kFielderRadius * 0.55,
      Paint()..color = kColorSkin,
    );
    // Cap
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(cx, cy - kFielderRadius * 0.6),
          width: kFielderRadius * 1.2,
          height: kFielderRadius * 1.2),
      3.14,
      3.14,
      false,
      Paint()..color = const Color(0xFF263238),
    );
  }
}
