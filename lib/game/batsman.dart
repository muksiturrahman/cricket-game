import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../services/shot_intent.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import 'bat.dart';
import 'cricket_game.dart';

class Batsman extends PositionComponent with HasGameReference {
  /// [homeAtStriker] — true for the player on strike at the bottom crease,
  /// false for their partner at the bowler's end. Both share the same
  /// running-between-wickets logic; their `_atStriker` flag is set from
  /// `homeAtStriker` at start of innings (and reset on `recenterHome`).
  /// [jerseyNumber] — only affects the rendered shirt number.
  Batsman({this.homeAtStriker = true, this.jerseyNumber = '7'})
      : super(priority: 4);

  final bool homeAtStriker;
  final String jerseyNumber;

  late Bat bat;

  // ── Per-batsman stats (used by the end-of-innings scorecard) ──────────
  /// Runs scored by this batsman across the innings.
  int runs = 0;
  /// Legitimate deliveries faced (wides excluded; no-balls included since
  /// the batsman still faces them).
  int ballsFaced = 0;
  int fours = 0;
  int sixes = 0;
  /// True once this batsman has been dismissed.
  bool isOut = false;
  /// Strike rate (runs per 100 balls). Returns 0 when no balls faced yet.
  double get strikeRate => ballsFaced == 0 ? 0 : runs * 100.0 / ballsFaced;
  /// Reset all per-innings stats — called from `CricketGame.restartGame` /
  /// `quitToMenu` / `_transitionToSecondInnings` so each innings tallies
  /// from scratch. Deliberately NOT called from `recenterHome()` (which
  /// fires on every wicket) — stats persist across the partnership.
  void resetStats() {
    runs = 0;
    ballsFaced = 0;
    fours = 0;
    sixes = 0;
    isOut = false;
  }

  bool _isSwinging = false;
  double _swingTimer = 0;
  ShotIntent _currentIntent = ShotIntent.defensive();

  /// Mutable so MatchSettings can override per innings.
  double swingWindowSec = kSwingWindowSec;

  // ── Running between wickets ─────────────────────────────────────────────
  Vector2 _strikerCrease = Vector2.zero();
  Vector2 _nonStrikerCrease = Vector2.zero();
  bool _atStriker = true;
  bool _isRunning = false;
  double _runElapsed = 0;
  double _runDuration = 0.55;

  // ── Lateral positioning (off side ↔ leg side) ─────────────────────────
  /// Offset from striker crease in pixels. Negative = leg side (screen left
  /// for a right-handed batsman), positive = off side (screen right).
  double _lateralOffset = 0;

  /// -1 (move left), 0 (idle), or +1 (move right). Set each frame by
  /// `CricketGame.update(dt)` from held A/D keys, or pulsed by drag input.
  double lateralVelocity = 0;

  // Idle clock — drives the breath / stance bob.
  double _idleClock = 0;

  @override
  Future<void> onLoad() async {
    size = Vector2(48, 80);
    _strikerCrease = Vector2(
      game.size.x / 2 - size.x / 2,
      game.size.y * 0.70 - size.y,
    );
    // The non-striker stands at the bowler's end, *behind* the popping crease
    // (drawn at 0.28h) and off to one side of the bowler — never directly
    // behind them, which is both visually wrong and dangerous in real cricket
    // (in the bowler's follow-through path). Offset 55 px right of centre,
    // y = 0.20h so the body sits cleanly behind the bowler's crease at 0.28h.
    _nonStrikerCrease = Vector2(
      game.size.x / 2 - size.x / 2 + kNonStrikerXOffset,
      game.size.y * 0.20,
    );
    _atStriker = homeAtStriker;
    position = (homeAtStriker ? _strikerStance : _nonStrikerCrease).clone();
    bat = Bat();
    await add(bat);
    bat.deactivate();
  }

  void playSwing(ShotIntent intent) {
    if (_isSwinging) return;
    _isSwinging = true;
    _swingTimer = 0;
    _currentIntent = intent;
    bat.activate(intent);
  }

  void runToOtherEnd(double duration) {
    if (_isRunning) return;
    _isRunning = true;
    _runElapsed = 0;
    _runDuration = duration;
  }

  /// Clean transient swing/run state at end of delivery. Does NOT move the
  /// batsman — strike rotation is owned by `CricketGame`, which decides
  /// whether to swap references after odd runs / end of over. The lateral
  /// stance offset is preserved across balls (cricket convention).
  void resetIdle() {
    _isSwinging = false;
    _swingTimer = 0;
    bat.deactivate();
    // If a run was mid-flight (e.g. wicket interrupted it), snap to the
    // destination so the batsman doesn't freeze mid-pitch.
    if (_isRunning) {
      _isRunning = false;
      _runElapsed = 0;
      _atStriker = !_atStriker;
      if (_strikerCrease != Vector2.zero()) {
        position = (_atStriker ? _strikerStance : _nonStrikerCrease).clone();
      }
    }
  }

  /// Snap the batsman back to their *original* end (the one set by
  /// `homeAtStriker`), discarding any lateral offset and any in-progress
  /// run. Used at start of innings, on a wicket (so a "new partnership"
  /// resets the field), and on game restart / quit-to-menu.
  void recenterHome() {
    _isSwinging = false;
    _swingTimer = 0;
    bat.deactivate();
    _isRunning = false;
    _runElapsed = 0;
    _atStriker = homeAtStriker;
    _lateralOffset = 0;
    if (_strikerCrease != Vector2.zero()) {
      position = (_atStriker ? _strikerStance : _nonStrikerCrease).clone();
    }
  }

  /// Legacy alias — same as `recenterHome` for callers that expected a
  /// "snap back to crease" behaviour.
  void recenter() => recenterHome();

  /// Convenience: nudge the batsman by [delta] pixels along the crease,
  /// clamped to ±`kBatsmanMaxLateralPx`. Touch drag uses this directly.
  void nudgeLateral(double delta) {
    _lateralOffset =
        (_lateralOffset + delta).clamp(-kBatsmanMaxLateralPx, kBatsmanMaxLateralPx);
    if (_atStriker && !_isRunning) position = _strikerStance;
  }

  /// Striker crease position with the current lateral offset applied.
  Vector2 get _strikerStance =>
      Vector2(_strikerCrease.x + _lateralOffset, _strikerCrease.y);

  ShotIntent get currentIntent => _currentIntent;
  bool get isRunning => _isRunning;

  /// 0..1 — how far through the swing window we are. `1` = window expired.
  /// Read by `CricketGame` on bat-ball collision to decide shot quality
  /// (clean / mistimed / edge): a small value means the player swung right
  /// as the ball arrived; a large value means they swung well in advance.
  double get swingProgress =>
      _isSwinging ? (_swingTimer / swingWindowSec).clamp(0.0, 1.0) : 0.0;
  bool get isSwinging => _isSwinging;

  @override
  void update(double dt) {
    _idleClock += dt;
    // Mirror CricketGame.powerOn into the bat so it can render the
    // power-ready cue. Cheap getter — no listener allocation.
    final g = game;
    if (g is CricketGame) bat.powerReady = g.powerOn.value;
    if (_isSwinging) {
      _swingTimer += dt;
      if (_swingTimer >= swingWindowSec) resetIdle();
    }

    // Lateral movement — only when stationary at the striker crease.
    if (lateralVelocity != 0 && _atStriker && !_isRunning && !_isSwinging) {
      _lateralOffset = (_lateralOffset +
              lateralVelocity * kBatsmanMoveSpeedPxPerSec * dt)
          .clamp(-kBatsmanMaxLateralPx, kBatsmanMaxLateralPx);
      position = _strikerStance;
    }

    if (_isRunning) {
      _runElapsed += dt;
      final t = (_runElapsed / _runDuration).clamp(0.0, 1.0);
      // Run between the actual stance position (with lateral offset) and the
      // non-striker crease — so a batsman who's stepped to leg side sets off
      // from there, not from the original crease centre.
      final from = _atStriker ? _strikerStance : _nonStrikerCrease;
      final to = _atStriker ? _nonStrikerCrease : _strikerStance;
      position = Vector2(
        from.x + (to.x - from.x) * t,
        from.y + (to.y - from.y) * t,
      );
      if (t >= 1.0) {
        _isRunning = false;
        _atStriker = !_atStriker;
        position = (_atStriker ? _strikerStance : _nonStrikerCrease).clone();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final centerX = size.x / 2;
    // Idle bob — breathing motion while waiting for the ball, suppressed
    // during a swing or sprint so it doesn't fight the action.
    final bob =
        (!_isSwinging && !_isRunning) ? math.sin(_idleClock * 2.6) * 1.4 : 0.0;
    canvas.save();
    canvas.translate(0, bob);
    // Drop shadow under feet
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(centerX, 64), width: 38, height: 8),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // Pads (legs)
    final padPaint = Paint()..color = const Color(0xFFEDE4D2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - 14, 36, 12, 28),
        const Radius.circular(3),
      ),
      padPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX + 2, 36, 12, 28),
        const Radius.circular(3),
      ),
      padPaint,
    );
    // Pad straps
    final strap = Paint()..color = const Color(0xFFB89E70);
    for (final yy in [42.0, 50.0, 58.0]) {
      canvas.drawRect(Rect.fromLTWH(centerX - 14, yy, 12, 1.5), strap);
      canvas.drawRect(Rect.fromLTWH(centerX + 2, yy, 12, 1.5), strap);
    }

    // Jersey body (rounded)
    final bodyRect = Rect.fromLTWH(centerX - 16, -2, 32, 42);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        bodyRect,
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      ),
      Paint()..color = kColorBatsmanKit,
    );
    // Jersey collar v-neck
    canvas.drawPath(
      Path()
        ..moveTo(centerX - 6, 0)
        ..lineTo(centerX, 8)
        ..lineTo(centerX + 6, 0)
        ..close(),
      Paint()..color = const Color(0xFF0D47A1),
    );
    // Jersey side stripe (gold)
    canvas.drawRect(
      Rect.fromLTWH(centerX - 16, 8, 3, 30),
      Paint()..color = kPalette.primary,
    );
    canvas.drawRect(
      Rect.fromLTWH(centerX + 13, 8, 3, 30),
      Paint()..color = kPalette.primary,
    );
    // Jersey number
    final numTp = TextPainter(
      text: TextSpan(
        text: jerseyNumber,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    numTp.paint(canvas, Offset(centerX - numTp.width / 2, 14));

    // Belt
    canvas.drawRect(
      Rect.fromLTWH(centerX - 16, 36, 32, 3),
      Paint()..color = const Color(0xFF1C1C1C),
    );

    // Gloves
    final glovePaint = Paint()..color = const Color(0xFFE1D6BD);
    canvas.drawCircle(Offset(centerX + 16, 22), 4.5, glovePaint);
    canvas.drawCircle(Offset(centerX + 16, 27), 4.5, glovePaint);

    // Head + helmet
    final headCenter = Offset(centerX, -14);
    canvas.drawCircle(headCenter, 13, Paint()..color = kColorSkin);
    // Helmet shell
    canvas.drawArc(
      Rect.fromCenter(center: headCenter, width: 30, height: 30),
      3.14,
      3.14,
      false,
      Paint()..color = const Color(0xFF0D47A1),
    );
    // Helmet rim highlight
    canvas.drawArc(
      Rect.fromCenter(center: headCenter, width: 30, height: 30),
      3.14 + 0.3,
      0.6,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Visor grille (vertical bars)
    final grille = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (int i = -2; i <= 2; i++) {
      final x = centerX + i * 3.5;
      canvas.drawLine(Offset(x, -10), Offset(x, -2), grille);
    }

    // Swing arc indicator
    if (_isSwinging) {
      final t = _swingTimer / swingWindowSec;
      final sweepAngle = t * 3.14;
      canvas.drawArc(
        Rect.fromCenter(
            center: Offset(centerX, 30), width: 64, height: 64),
        -3.14 / 2,
        sweepAngle,
        false,
        Paint()
          ..color = kPalette.primary.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );

      // Timing meter — small bar above the helmet showing the swing-window
      // zones. A red marker tracks the live progress. Same thresholds the
      // physics service uses (kSwingCleanMax / kSwingMistimedMax).
      _renderTimingMeter(canvas, centerX, t);
    }
    canvas.restore();
  }

  void _renderTimingMeter(Canvas canvas, double centerX, double t) {
    const barW = 56.0;
    const barH = 5.0;
    final barTop = -38.0;
    final barLeft = centerX - barW / 2;
    final barRect = Rect.fromLTWH(barLeft, barTop, barW, barH);

    // Background — full bar.
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(2.5)),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    // Clean zone (green) — 0..kSwingCleanMax.
    final cleanW = barW * kSwingCleanMax;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barLeft, barTop, cleanW, barH),
        const Radius.circular(2.5),
      ),
      Paint()..color = const Color(0xFF34C759).withValues(alpha: 0.85),
    );
    // Mistime zone (yellow) — kSwingCleanMax..kSwingMistimedMax.
    final mistimeStart = barLeft + cleanW;
    final mistimeW = barW * (kSwingMistimedMax - kSwingCleanMax);
    canvas.drawRect(
      Rect.fromLTWH(mistimeStart, barTop, mistimeW, barH),
      Paint()..color = const Color(0xFFFFCC00).withValues(alpha: 0.85),
    );
    // Edge zone (red) — kSwingMistimedMax..1.0.
    final edgeStart = mistimeStart + mistimeW;
    final edgeW = barW * (1.0 - kSwingMistimedMax);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(edgeStart, barTop, edgeW, barH),
        topRight: const Radius.circular(2.5),
        bottomRight: const Radius.circular(2.5),
      ),
      Paint()..color = const Color(0xFFFF3B30).withValues(alpha: 0.85),
    );

    // Live cursor — vertical line tracking current progress through the
    // swing window. White with subtle glow so it pops against the zones.
    final cursorX = (barLeft + barW * t).clamp(barLeft, barLeft + barW);
    canvas.drawRect(
      Rect.fromLTWH(cursorX - 1, barTop - 2, 2, barH + 4),
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }
}
