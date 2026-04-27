import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../services/shot_intent.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

/// The bat hitbox — child of Batsman. Only active during the swing window.
class Bat extends PositionComponent {
  bool active = false;
  ShotIntent currentIntent = ShotIntent.defensive();

  /// Mirrors `CricketGame.powerOn.value` — set by Batsman each frame.
  /// When true, the bat renders a subtle gold tint as a "ready" cue, and the
  /// active glow is stronger / more golden.
  bool powerReady = false;

  late RectangleHitbox _hitbox;

  /// Activation timer — used to scale + glow the bat on impact.
  double _activeElapsed = 0;

  Bat() : super(priority: 0);

  @override
  Future<void> onLoad() async {
    size = Vector2(14, 58);
    position = Vector2(30, 6);
    _hitbox = RectangleHitbox(size: size)
      ..collisionType = CollisionType.inactive;
    add(_hitbox);
  }

  void activate(ShotIntent intent) {
    active = true;
    currentIntent = intent;
    _activeElapsed = 0;
    _hitbox.collisionType = CollisionType.passive;
  }

  void deactivate() {
    active = false;
    _hitbox.collisionType = CollisionType.inactive;
  }

  @override
  void update(double dt) {
    if (active) _activeElapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    final r = Rect.fromLTWH(0, 0, size.x, size.y);

    // POWER-ready cue — soft, persistent gold halo so the player can tell
    // "I'm armed for a lofted shot" without watching the toggle. Only when
    // not actively swinging (so it doesn't fight the impact glow).
    if (powerReady && !active) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.inflate(3), const Radius.circular(5)),
        Paint()
          ..color = kPalette.primary.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // Per-shot swing rotation, around the handle pivot (top-centre of bat).
    // The hitbox itself does NOT rotate (it stays at the original rect for
    // forgiving collisions); this is purely visual feedback so the player
    // sees a real swing instead of a static stick.
    final rotation = active ? _swingRotation() : 0.0;
    final motionTrail = active && rotation.abs() > 0.4;

    canvas.save();
    if (rotation != 0) {
      // Pivot at top-centre of the bat = where the batsman's hand grips.
      canvas.translate(size.x / 2, 0);
      canvas.rotate(rotation);
      canvas.translate(-size.x / 2, 0);
    }

    if (active) {
      // Glow halo — strongest at activation, decays over swing window.
      // Stronger + brighter when this swing is a power shot.
      final t = (_activeElapsed / kSwingWindowSec).clamp(0.0, 1.0);
      final glow = (1 - t).clamp(0.0, 1.0);
      final isPower = currentIntent.powerOn;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          r.inflate(6 + glow * (isPower ? 8 : 4)),
          const Radius.circular(8),
        ),
        Paint()
          ..color = kPalette.primary
              .withValues(alpha: (isPower ? 0.85 : 0.55) * glow)
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, isPower ? 12 : 8),
      );
    }
    // Bat blade — gradient for grain effect
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(3)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFB17143), Color(0xFF6B3F1A), Color(0xFF8C5429)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(r),
    );
    // Centre seam (the meat of the bat)
    canvas.drawLine(
      Offset(size.x * 0.5, 4),
      Offset(size.x * 0.5, size.y - 4),
      Paint()
        ..color = const Color(0xFF3E2410)
        ..strokeWidth = 1,
    );
    // Sticker — a thin gold stripe
    canvas.drawRect(
      Rect.fromLTWH(2, size.y * 0.55, size.x - 4, 1.6),
      Paint()..color = kPalette.primary,
    );

    // Motion blur streak at the bat tip during big swings — sells the speed.
    if (motionTrail) {
      final tipY = size.y;
      canvas.drawRect(
        Rect.fromLTWH(size.x * 0.2, tipY - 14, size.x * 0.6, 12),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.restore();
  }

  /// Rotation applied to the bat blade during a swing, in radians, around
  /// the handle pivot. Each shot type has a distinct arc so the player can
  /// see what they played.
  ///
  /// Convention (Flutter Canvas): positive angle = clockwise; angle 0 = bat
  /// hangs straight down (default rest pose). Anatomical accuracy isn't the
  /// goal — visual differentiation is.
  double _swingRotation() {
    final t = (_activeElapsed / kSwingWindowSec).clamp(0.0, 1.0);
    switch (currentIntent.type) {
      case ShotType.defensive:
        // Quick stab forward then settle — sin(πt) curve = out and back.
        return math.sin(t * math.pi) * 0.22;
      case ShotType.coverDrive:
        // Counter-clockwise sweep from a cocked-right windup to a left-
        // pointing follow-through (bat tip ends pointing toward the off side).
        return _ease(t, from: 0.7, to: -1.4);
      case ShotType.pullShot:
        // Big horizontal sweep across the body — leg-side power shot.
        return _ease(t, from: -1.0, to: 1.9);
      case ShotType.straightDrive:
        // Forward drive — modest arc, ends pointing roughly toward bowler.
        return _ease(t, from: -0.55, to: 0.85);
    }
  }

  double _ease(double t, {required double from, required double to}) {
    // easeOutCubic — quick acceleration, gentle settle.
    final eased = 1 - math.pow(1 - t, 3).toDouble();
    return from + (to - from) * eased;
  }
}
