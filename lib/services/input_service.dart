import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import 'shot_intent.dart';

/// Translates raw swipe geometry into a `ShotIntent` (direction + force).
/// Stateless — power flag is owned by `CricketGame` and passed in.
class InputService {
  /// Min swipe length (px) to treat as a directional shot. Below this is a
  /// defensive block.
  static const double _minSwipePx = 16.0;

  /// Swipe length that maps to full force. Anything longer is clamped.
  static const double _maxSwipePx = 140.0;

  ShotIntent swipeToIntent(Offset start, Offset end, {required bool powerOn}) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < _minSwipePx * _minSwipePx) {
      return ShotIntent.defensive();
    }
    final len = math.sqrt(lenSq);
    final force = (len / _maxSwipePx).clamp(0.0, 1.0);
    return ShotIntent.directed(
      direction: Vector2(dx, dy),
      force: force,
      powerOn: powerOn,
    );
  }
}
