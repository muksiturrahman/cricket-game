import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';

class Stumps extends PositionComponent with HasGameReference {
  Stumps() : super(priority: 2);

  bool _bailsFlying = false;
  double _bailTimer = 0;
  /// Wobble timer — set when stumps are hit; bails launch after `_wobbleSec`.
  double _wobbleElapsed = 999;
  static const double _wobbleSec = 0.18;

  @override
  Future<void> onLoad() async {
    size = Vector2(36, 52);
    position = Vector2(
      game.size.x / 2 - size.x / 2,
      game.size.y * 0.70 - size.y,
    );
    add(RectangleHitbox(size: size)..collisionType = CollisionType.passive);
  }

  void flyBails() {
    // Start with a brief wobble — bails actually launch after `_wobbleSec`.
    _wobbleElapsed = 0;
    _bailsFlying = false;
    _bailTimer = 0;
  }

  @override
  void update(double dt) {
    if (_wobbleElapsed < _wobbleSec) {
      _wobbleElapsed += dt;
      if (_wobbleElapsed >= _wobbleSec) {
        _bailsFlying = true;
        _bailTimer = 0;
      }
    }
    if (_bailsFlying) {
      _bailTimer += dt;
      if (_bailTimer > 1.2) _bailsFlying = false;
    }
  }

  @override
  void render(Canvas canvas) {
    // Drop shadow on the pitch behind the stumps
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(size.x / 2, size.y + 2), width: size.x * 1.1, height: 6),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // Wobble stumps when struck — high-frequency lateral shake that decays.
    final wobbling = _wobbleElapsed < _wobbleSec;
    if (wobbling) {
      final t = _wobbleElapsed / _wobbleSec;
      final wobble = math.sin(_wobbleElapsed * 110) * 3.0 * (1 - t);
      canvas.save();
      canvas.translate(wobble, 0);
    }

    final w = size.x / 5;
    for (int i = 0; i < 3; i++) {
      final x = w * 0.5 + i * (size.x / 3);
      // Each stump: gradient from light to dark for cylindrical look
      final r = Rect.fromLTWH(x - w / 2, 0, w, size.y);
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              const Color(0xFFEFD7A4),
              kColorStumps,
              const Color(0xFF8C6A3F),
            ],
            stops: const [0.0, 0.45, 1.0],
          ).createShader(r),
      );
      // Top dark cap
      canvas.drawOval(
        Rect.fromLTWH(x - w / 2, -2, w, 4),
        Paint()..color = const Color(0xFF7A5530),
      );
    }

    if (!_bailsFlying) {
      final bp = Paint()..color = kColorBails;
      // During the wobble (still attached) the bails twitch a bit.
      double bailNudge = 0;
      if (wobbling) {
        bailNudge = math.sin(_wobbleElapsed * 130) * 1.4;
      }
      _drawBail(canvas,
          Rect.fromLTWH(0, -7 + bailNudge, size.x * 0.45, 5), bp);
      _drawBail(canvas,
          Rect.fromLTWH(size.x * 0.55, -7 - bailNudge, size.x * 0.45, 5), bp);
    } else {
      final t = _bailTimer;
      final alpha = (1.0 - t).clamp(0.0, 1.0);
      final bp = Paint()..color = kColorBails.withValues(alpha: alpha);
      // Bails fly with rotation
      _drawRotatingBail(
        canvas,
        cx: -8 - t * 28 + size.x * 0.2,
        cy: -7 - t * 45,
        w: size.x * 0.4,
        h: 5,
        rot: -t * 6,
        paint: bp,
      );
      _drawRotatingBail(
        canvas,
        cx: size.x + t * 28 + size.x * 0.2,
        cy: -7 - t * 45,
        w: size.x * 0.4,
        h: 5,
        rot: t * 6,
        paint: bp,
      );
    }

    if (wobbling) canvas.restore();
  }

  void _drawBail(Canvas canvas, Rect r, Paint p) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(2)),
      p,
    );
    // Highlight stripe
    canvas.drawRect(
      Rect.fromLTWH(r.left, r.top, r.width, 1.2),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  void _drawRotatingBail(
    Canvas canvas, {
    required double cx,
    required double cy,
    required double w,
    required double h,
    required double rot,
    required Paint paint,
  }) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rot);
    final r = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(2)),
      paint,
    );
    canvas.restore();
  }
}
