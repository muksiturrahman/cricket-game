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

  /// Where the bowler stands at the moment of release — just behind the
  /// popping crease. Cached in `onLoad`.
  Vector2 _crease = Vector2.zero();

  /// Run-up start point — set in `prepareBowl` from the bowler kind. Pacer
  /// starts off-screen above; spinner only takes a few strides.
  Vector2 _runUpStart = Vector2.zero();

  void Function(BowlConfig)? onRelease;

  /// Public accessor used by `Bowler.render` and external animations to
  /// scale stride amplitude / frequency by archetype.
  BowlerKind? get currentKind => _config?.kind;

  @override
  Future<void> onLoad() async {
    size = Vector2(48, 80);
    _crease = Vector2(
      game.size.x / 2 - size.x / 2,
      game.size.y * 0.22,
    );
    _runUpStart = _crease.clone();
    position = _crease.clone();
  }

  /// Per-kind run-up start fraction of screen height. Pacers get a long
  /// approach (off-screen above); spinners only a few strides.
  static double _startYRatioFor(BowlerKind kind) => switch (kind) {
        BowlerKind.pacer => -0.05,
        BowlerKind.medium => 0.02,
        BowlerKind.swing => 0.05,
        BowlerKind.spinner => 0.13,
      };

  void prepareBowl(BowlConfig config) {
    _config = config;
    _runUpStart = Vector2(
      _crease.x,
      game.size.y * _startYRatioFor(config.kind),
    );
    // Teleport to the run-up mark — the settling delay between deliveries
    // gives the player time to register the bowler's new starting position.
    position = _runUpStart.clone();
    _runningUp = true;
    _runUpTimer = 0;
  }

  void cancel() {
    _runningUp = false;
    _runUpTimer = 0;
    _config = null;
    if (_crease != Vector2.zero()) position = _crease.clone();
  }

  @override
  void update(double dt) {
    if (!_runningUp) return;
    _runUpTimer += dt;
    final t = (_runUpTimer / runUpSec).clamp(0.0, 1.0);
    // Smoothstep — start slow, accelerate, decelerate at release. Distance
    // from start to crease is set by the bowler kind, so pacers cover more
    // ground in the same time = visibly faster sprint.
    final eased = t * t * (3 - 2 * t);
    position = Vector2(
      _runUpStart.x,
      _runUpStart.y + (_crease.y - _runUpStart.y) * eased,
    );
    if (_runUpTimer >= runUpSec && _config != null) {
      _runningUp = false;
      onRelease?.call(_config!);
      _config = null;
      // Stay at the crease after release — next prepareBowl will teleport
      // to the new run-up mark.
    }
  }

  @override
  void render(Canvas canvas) {
    final centerX = size.x / 2;
    final t = _runningUp ? (_runUpTimer / runUpSec).clamp(0.0, 1.0) : 0.0;
    // Stride amplitude / frequency vary by archetype — pacer takes big fast
    // strides, spinner an easy walking pace.
    final kind = _config?.kind;
    final strideAmp = switch (kind) {
      BowlerKind.pacer => 8.0,
      BowlerKind.medium => 5.5,
      BowlerKind.swing => 5.0,
      BowlerKind.spinner => 3.0,
      _ => 4.5,
    };
    final strideFreq = switch (kind) {
      BowlerKind.pacer => 18.0,
      BowlerKind.medium => 14.0,
      BowlerKind.swing => 13.0,
      BowlerKind.spinner => 9.0,
      _ => 14.0,
    };
    // Bob: small vertical hop during run-up; bigger for fast types.
    final bob = _runningUp
        ? math.sin(_runUpTimer * (strideFreq + 2)) * (1.0 + strideAmp * 0.12)
        : 0.0;

    canvas.save();
    canvas.translate(0, bob);

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centerX, 64 - bob), width: 36, height: 7),
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );

    // Legs (dark trousers) — alternating stride: when one leg is forward,
    // the other is back. `stridePhase` swings -1..+1 over each step.
    final trousers = Paint()..color = const Color(0xFF1F2A37);
    final stridePhase =
        _runningUp ? math.sin(_runUpTimer * strideFreq) : 0.0;
    final legSpread = stridePhase.abs() * strideAmp;
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
