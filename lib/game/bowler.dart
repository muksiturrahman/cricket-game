import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/theme.dart';
import 'ai_manager.dart';

class Bowler extends PositionComponent with HasGameReference {
  Bowler() : super(priority: 3);

  /// Mutable so MatchSettings can override per innings.
  double runUpSec = kBowlerRunUpSec;

  bool _runningUp = false;
  double _runUpTimer = 0;
  BowlConfig? _config;

  /// Cached "home" position — where bowler stands between deliveries. Run-up
  /// progresses forward toward the crease, then snaps back to home.
  Vector2 _homePos = Vector2.zero();

  void Function(BowlConfig)? onRelease;

  @override
  Future<void> onLoad() async {
    size = Vector2(48, 80);
    position = Vector2(
      game.size.x / 2 - size.x / 2,
      game.size.y * 0.22,
    );
    _homePos = position.clone();
  }

  void prepareBowl(BowlConfig config) {
    _config = config;
    _runningUp = true;
    _runUpTimer = 0;
  }

  void cancel() {
    _runningUp = false;
    _runUpTimer = 0;
    _config = null;
    if (_homePos != Vector2.zero()) position = _homePos.clone();
  }

  @override
  void update(double dt) {
    if (!_runningUp) {
      // Lerp gently back to home between deliveries.
      final delta = _homePos - position;
      if (delta.length > 0.5) {
        position += delta * (dt * 6).clamp(0, 1);
      }
      return;
    }
    _runUpTimer += dt;
    final t = (_runUpTimer / runUpSec).clamp(0.0, 1.0);
    // Walk forward toward the bowling crease — but cap the stride so the
    // bowler never crosses past their popping crease. Bowler.position.y
    // starts at ~0.22h and the bowler-end crease is at ~0.28h; the visible
    // body already extends most of that 0.06h, so the walk only needs a
    // few-pixel forward shuffle. We cap at 4% of screen height.
    final maxForward = game.size.y * 0.04;
    final forward = math.pow(t, 1.4) * maxForward;
    position = Vector2(_homePos.x, _homePos.y + forward.toDouble());
    if (_runUpTimer >= runUpSec && _config != null) {
      _runningUp = false;
      onRelease?.call(_config!);
      _config = null;
    }
  }

  @override
  void render(Canvas canvas) {
    final centerX = size.x / 2;
    final t = _runningUp ? (_runUpTimer / runUpSec).clamp(0.0, 1.0) : 0.0;
    // Bob: small vertical hop during run-up
    final bob = _runningUp ? math.sin(_runUpTimer * 18) * 1.6 : 0.0;

    canvas.save();
    canvas.translate(0, bob);

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centerX, 64 - bob), width: 36, height: 7),
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );

    // Legs (dark trousers)
    final trousers = Paint()..color = const Color(0xFF1F2A37);
    final legSpread = _runningUp ? 4.0 + math.sin(_runUpTimer * 14) * 4.0 : 0.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - 12 - legSpread, 36, 11, 28),
        const Radius.circular(3),
      ),
      trousers,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX + 1 + legSpread, 36, 11, 28),
        const Radius.circular(3),
      ),
      trousers,
    );

    // Jersey body (white kit) with side stripe
    final bodyRect = Rect.fromLTWH(centerX - 16, -2, 32, 42);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        bodyRect,
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      ),
      Paint()..color = kColorBowlerKit,
    );
    // Collar
    canvas.drawPath(
      Path()
        ..moveTo(centerX - 6, 0)
        ..lineTo(centerX, 8)
        ..lineTo(centerX + 6, 0)
        ..close(),
      Paint()..color = const Color(0xFFB0BEC5),
    );
    // Side stripes (red/gold)
    canvas.drawRect(
      Rect.fromLTWH(centerX - 16, 8, 3, 30),
      Paint()..color = kPalette.accent,
    );
    canvas.drawRect(
      Rect.fromLTWH(centerX + 13, 8, 3, 30),
      Paint()..color = kPalette.accent,
    );
    // Number
    final numTp = TextPainter(
      text: const TextSpan(
        text: '11',
        style: TextStyle(
          color: Color(0xFF1F2A37),
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    numTp.paint(canvas, Offset(centerX - numTp.width / 2, 16));

    // Belt
    canvas.drawRect(
      Rect.fromLTWH(centerX - 16, 36, 32, 3),
      Paint()..color = const Color(0xFF263238),
    );

    // Head
    final headCenter = Offset(centerX, -14);
    canvas.drawCircle(headCenter, 13, Paint()..color = kColorSkin);
    // Hair / cap
    canvas.drawArc(
      Rect.fromCenter(center: headCenter, width: 28, height: 28),
      3.14,
      3.14,
      false,
      Paint()..color = const Color(0xFF263238),
    );
    // Cap brim
    canvas.drawRect(
      Rect.fromLTWH(centerX - 14, -16, 12, 3),
      Paint()..color = const Color(0xFF263238),
    );

    // Bowling arm — animated swing during last 40% of run-up
    final armPaint = Paint()
      ..color = kColorSkin
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    if (_runningUp) {
      // Arm sweeps from above-head (-pi/2) to extended-down at release
      final armPhase = ((t - 0.55) / 0.45).clamp(0.0, 1.0);
      final armAngle = -math.pi / 2 + armPhase * math.pi;
      final shoulder = Offset(centerX + 8, 6);
      final hand = Offset(
        shoulder.dx + math.cos(armAngle) * 22,
        shoulder.dy + math.sin(armAngle) * 22,
      );
      canvas.drawLine(shoulder, hand, armPaint);
      // Trailing "swoosh" arc when arm is near release
      if (armPhase > 0.6) {
        canvas.drawArc(
          Rect.fromCircle(center: shoulder, radius: 22),
          armAngle - 0.9,
          0.9,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.30 * (armPhase - 0.6) * 2.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
    } else {
      // Idle resting arm
      canvas.drawLine(
        Offset(centerX + 8, 6),
        Offset(centerX + 14, 28),
        armPaint,
      );
    }

    canvas.restore();
  }
}
