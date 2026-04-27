import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/theme.dart';

/// Renders the cricket ground. The visible white ellipse IS the boundary —
/// `Ball._isOutsideBoundary` checks position against the same dimensions.
///
/// The render method paints in layers:
///   sky gradient → distant clouds → stadium silhouette → crowd speckle
///   → outfield (radial gradient + mowing stripes) → boundary rope
///   → 30-yard inner circle (dashed) → sponsor boards → pitch strip
///   → crease box detail
///
/// Crowd specks and stadium silhouette are pre-baked in `onLoad()` (deterministic
/// seeded random) so we don't allocate per frame.
class Pitch extends PositionComponent with HasGameReference {
  Pitch() : super(priority: 0);

  /// When true, render the night-mode palette: deep blue sky, dimmer
  /// outfield, four floodlight halos around the boundary. Set by
  /// `CricketGame._applySettings` from `MatchSettings.timeOfDay`.
  bool isNight = false;

  // Pre-baked decorations cached at onLoad.
  final List<_CrowdSpeck> _crowdSpecks = [];
  final List<_Cloud> _clouds = [];
  Path? _stadiumSilhouette;
  Path? _innerRingDashed;
  final List<_Sponsor> _sponsors = [];

  // Animation state.
  double _clock = 0;
  /// Time-since-last-cheer. While < kCheerDuration the crowd "waves".
  double _cheerElapsed = 999;
  static const double _cheerDuration = 2.4;

  @override
  Future<void> onLoad() async {
    size = game.size;
    final rng = math.Random(7);

    // Stadium silhouette — a wavy band along the horizon.
    _stadiumSilhouette = _buildStadiumPath(size, rng);

    // Distant clouds.
    for (int i = 0; i < 6; i++) {
      _clouds.add(_Cloud(
        cx: rng.nextDouble() * size.x,
        cy: size.y * (0.04 + rng.nextDouble() * 0.07),
        rx: 36 + rng.nextDouble() * 50,
        ry: 10 + rng.nextDouble() * 6,
        alpha: 0.15 + rng.nextDouble() * 0.18,
        driftSpeed: 4 + rng.nextDouble() * 8,
      ));
    }

    // Crowd ring — speckle dots in a band hugging the boundary, outside the
    // playable ellipse but inside the stadium silhouette.
    final cx = size.x / 2;
    final cy = size.y / 2;
    final hw = size.x * kBoundaryWidthRatio / 2;
    final hh = size.y * kBoundaryHeightRatio / 2;
    final palette = [
      kPalette.crowdSpeck1,
      kPalette.crowdSpeck2,
      kPalette.crowdSpeck3,
      kPalette.crowdSpeck4,
    ];
    for (int i = 0; i < 320; i++) {
      // Sample within an outer ellipse and reject if it lands inside the
      // boundary ellipse — gives a ring shape.
      final angle = rng.nextDouble() * 2 * math.pi;
      final t = 1.0 + rng.nextDouble() * 0.16; // 1.0–1.16 of boundary radii
      final x = cx + math.cos(angle) * hw * t;
      final y = cy + math.sin(angle) * hh * t;
      // Don't draw specks above the horizon — that's where the stadium is.
      if (y < size.y * 0.13) continue;
      // Phase = how far around the ring this speck sits (0..1) — used so
      // the cheer wave sweeps from one side to the other.
      final phase = (math.atan2(y - cy, x - cx) + math.pi) / (2 * math.pi);
      _crowdSpecks.add(_CrowdSpeck(
        x: x,
        y: y,
        r: 1.2 + rng.nextDouble() * 1.4,
        color: palette[rng.nextInt(palette.length)],
        phase: phase,
        bobSeed: rng.nextDouble() * math.pi * 2,
      ));
    }

    // Inner-ring dashed path.
    _innerRingDashed = _buildDashedOval(
      cx: cx,
      cy: cy,
      rx: size.x * kInnerRingWidthRatio / 2,
      ry: size.y * kInnerRingHeightRatio / 2,
      dashCount: 60,
      dashFraction: 0.55,
    );

    // Sponsor boards along the inner edge of the boundary.
    final sponsorLabels = ['CRICKET PRO', 'STADIUM', 'CHAMPIONS', 'XI'];
    for (int i = 0; i < 16; i++) {
      final theta = (i / 16) * 2 * math.pi - math.pi / 2;
      final px = cx + math.cos(theta) * (hw - 18);
      final py = cy + math.sin(theta) * (hh - 18);
      // Skip sponsors directly above the pitch corridor — they'd overlap text.
      if ((py - cy).abs() < hh * 0.28 && (px - cx).abs() < size.x * 0.1) {
        continue;
      }
      _sponsors.add(_Sponsor(
        cx: px,
        cy: py,
        angle: theta + math.pi / 2,
        text: sponsorLabels[i % sponsorLabels.length],
      ));
    }
  }

  /// Triggered by CricketGame when a boundary is scored — kicks off a wave
  /// animation across the crowd specks.
  void cheer() {
    _cheerElapsed = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;
    if (_cheerElapsed < _cheerDuration) _cheerElapsed += dt;
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    final rect = Rect.fromLTWH(0, 0, w, h);

    // 1. Sky gradient — daytime uses the standard sky; night swaps in a
    // deep-navy linear so the stadium silhouette reads as "after dark".
    final skyRect = Rect.fromLTWH(0, 0, w, h * 0.18);
    if (isNight) {
      canvas.drawRect(
        skyRect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF050B20), Color(0xFF14213D), Color(0xFF263F66)],
          ).createShader(skyRect),
      );
    } else {
      canvas.drawRect(
        skyRect,
        Paint()..shader = AppGradients.sky().createShader(skyRect),
      );
    }

    // 2. Clouds — drift slowly across the sky
    for (final c in _clouds) {
      final cx = ((c.cx + _clock * c.driftSpeed) % (w + 220)) - 110;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, c.cy), width: c.rx * 2, height: c.ry * 2),
        Paint()..color = Colors.white.withValues(alpha: c.alpha),
      );
    }

    // 3. Stadium silhouette
    if (_stadiumSilhouette != null) {
      canvas.drawPath(_stadiumSilhouette!, Paint()..color = kPalette.standDark);
      // A lighter band on top to imply roof lighting.
      canvas.drawPath(
        _stadiumSilhouette!,
        Paint()
          ..color = const Color(0x33FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }

    // 4. Crowd band (drawn before the outfield so the outfield clips its
    // bottom edge).
    final cheering = _cheerElapsed < _cheerDuration;
    final cheerT = (_cheerElapsed / _cheerDuration).clamp(0.0, 1.0);
    for (final s in _crowdSpecks) {
      // Idle micro-bob — tiny vertical jitter so the crowd looks alive.
      final idleBob = math.sin(_clock * 2.4 + s.bobSeed) * 0.4;
      // Cheer wave — a peak that sweeps phase 0 → 1 across the ring.
      double wave = 0;
      double extraR = 0;
      if (cheering) {
        // Distance of this speck's phase from the wave's current position,
        // wrapped so a peak crossing 1.0 still affects phase ~0.05.
        final waveCenter = cheerT;
        var dPhase = (s.phase - waveCenter).abs();
        if (dPhase > 0.5) dPhase = 1 - dPhase;
        // Each speck cheers when the wave is within 0.18 of its phase.
        final intensity = math.max(0.0, 1 - dPhase / 0.18);
        // Fade out the wave near the end.
        final fade = 1 - cheerT;
        wave = -8.0 * intensity * fade;
        extraR = 0.6 * intensity * fade;
      }
      canvas.drawCircle(
        Offset(s.x, s.y + idleBob + wave),
        s.r + extraR,
        Paint()..color = s.color,
      );
    }

    // 5. Outfield: ellipse filled with radial gradient + mowing stripes
    final cx = w / 2;
    final cy = h / 2;
    final hw = w * kBoundaryWidthRatio / 2;
    final hh = h * kBoundaryHeightRatio / 2;
    final outfieldRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: hw * 2,
      height: hh * 2,
    );

    // Drop shadow under field for depth.
    canvas.drawOval(
      outfieldRect.translate(0, 6),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    canvas.save();
    canvas.clipPath(Path()..addOval(outfieldRect));
    // Base radial gradient
    canvas.drawRect(
      rect,
      Paint()..shader = AppGradients.outfield().createShader(outfieldRect),
    );
    // Mowing stripes — alternating bands of slightly lighter green.
    final stripePaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    final stripeH = hh * 0.16;
    for (double y = -hh; y < hh; y += stripeH * 2) {
      canvas.drawRect(
        Rect.fromLTWH(cx - hw, cy + y, hw * 2, stripeH),
        stripePaint,
      );
    }
    canvas.restore();

    // 6. Boundary rope — two-toned: white outer + red-yellow inner stripe.
    canvas.drawOval(
      outfieldRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawOval(
      outfieldRect.deflate(2.5),
      Paint()
        ..color = kPalette.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 7. Sponsor boards — inside the rope, anchored to the boundary
    for (final s in _sponsors) {
      _drawSponsor(canvas, s);
    }

    // 8. 30-yard inner ring (dashed)
    if (_innerRingDashed != null) {
      canvas.drawPath(
        _innerRingDashed!,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }

    // 9. Pitch strip — gradient + wear marks
    final sw = w * 0.13;
    final sl = (w - sw) / 2;
    final pitchRect = Rect.fromLTWH(sl, h * 0.18, sw, h * 0.65);
    // Soft drop shadow under pitch
    canvas.drawRect(
      pitchRect.translate(2, 4),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRect(
      pitchRect,
      Paint()..shader = AppGradients.pitch().createShader(pitchRect),
    );
    // Wear marks at the bowling/batting ends
    final wearPaint = Paint()..color = kPalette.pitchWear;
    canvas.drawCircle(
        Offset(cx, h * 0.27), sw * 0.45, wearPaint); // bowler footmark
    canvas.drawCircle(
        Offset(cx - sw * 0.18, h * 0.7), sw * 0.30, wearPaint);
    canvas.drawCircle(
        Offset(cx + sw * 0.18, h * 0.7), sw * 0.30, wearPaint);
    // Pitch edge highlights
    canvas.drawLine(
      Offset(sl, h * 0.18),
      Offset(sl, h * 0.83),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(sl + sw, h * 0.18),
      Offset(sl + sw, h * 0.83),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..strokeWidth = 1,
    );

    // 10. Crease boxes (popping + return creases) at each end
    _drawCreaseBox(canvas, cx, h * 0.70, sw);
    _drawCreaseBox(canvas, cx, h * 0.28, sw);

    // 11. Night-mode overlay: dim the whole field with a navy tint, then
    // paint four floodlight cones at the corners of the stadium.
    if (isNight) {
      // Dim layer — multiplicative-ish effect via translucent navy.
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0xFF0A1A33).withValues(alpha: 0.42),
      );
      // Floodlights at the four "corners" of the boundary ellipse.
      final lights = [
        Offset(w * 0.10, h * 0.15),
        Offset(w * 0.90, h * 0.15),
        Offset(w * 0.10, h * 0.88),
        Offset(w * 0.90, h * 0.88),
      ];
      for (final l in lights) {
        // Pole (just a tiny stub — the cone does most of the work)
        canvas.drawCircle(
          l,
          3,
          Paint()..color = const Color(0xFFFFE082),
        );
        // Soft radial glow
        canvas.drawCircle(
          l,
          120,
          Paint()
            ..shader = ui.Gradient.radial(
              l,
              120,
              [
                const Color(0xFFFFF59D).withValues(alpha: 0.25),
                const Color(0x00FFE082),
              ],
            ),
        );
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  void _drawCreaseBox(Canvas canvas, double cx, double cy, double pitchWidth) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 2;
    final halfW = pitchWidth / 2 + 14;
    // Popping crease (the long horizontal line)
    canvas.drawLine(
        Offset(cx - halfW, cy), Offset(cx + halfW, cy), p);
    // Return creases (perpendicular short lines marking off-stump and leg-stump)
    canvas.drawLine(
      Offset(cx - pitchWidth / 2 - 4, cy - 14),
      Offset(cx - pitchWidth / 2 - 4, cy + 14),
      p,
    );
    canvas.drawLine(
      Offset(cx + pitchWidth / 2 + 4, cy - 14),
      Offset(cx + pitchWidth / 2 + 4, cy + 14),
      p,
    );
  }

  void _drawSponsor(Canvas canvas, _Sponsor s) {
    canvas.save();
    canvas.translate(s.cx, s.cy);
    canvas.rotate(s.angle);
    final r = Rect.fromCenter(center: Offset.zero, width: 40, height: 8);
    canvas.drawRect(r, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRect(
      r,
      Paint()
        ..color = const Color(0x44000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
    final tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 5.4,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  Path _buildStadiumPath(Vector2 sz, math.Random rng) {
    final w = sz.x;
    final horizon = sz.y * 0.16;
    final path = Path()..moveTo(0, horizon);
    final segs = 18;
    for (int i = 0; i <= segs; i++) {
      final x = w * i / segs;
      final wobble = (rng.nextDouble() - 0.5) * 6;
      // Roof curve — slightly bowed so middle is higher than edges.
      final centerBias = (1 - ((i / segs) - 0.5).abs() * 2);
      final y = horizon - 18 - centerBias * 18 + wobble;
      path.lineTo(x, y);
    }
    path.lineTo(w, horizon);
    path.close();
    return path;
  }

  Path _buildDashedOval({
    required double cx,
    required double cy,
    required double rx,
    required double ry,
    required int dashCount,
    required double dashFraction,
  }) {
    final path = Path();
    final step = 2 * math.pi / dashCount;
    final dashLen = step * dashFraction;
    for (int i = 0; i < dashCount; i++) {
      final start = i * step;
      final end = start + dashLen;
      path.moveTo(cx + math.cos(start) * rx, cy + math.sin(start) * ry);
      // Approximate the arc with a few line segments.
      const segs = 4;
      for (int s = 1; s <= segs; s++) {
        final a = start + (end - start) * s / segs;
        path.lineTo(cx + math.cos(a) * rx, cy + math.sin(a) * ry);
      }
    }
    return path;
  }
}

class _CrowdSpeck {
  final double x;
  final double y;
  final double r;
  final Color color;
  /// Position around the crowd ring, 0..1. Lower values are on the left
  /// side, higher on the right — used to time the cheer wave.
  final double phase;
  /// Random offset for the idle micro-bob, so specks don't bob in lockstep.
  final double bobSeed;
  _CrowdSpeck({
    required this.x,
    required this.y,
    required this.r,
    required this.color,
    required this.phase,
    required this.bobSeed,
  });
}

class _Cloud {
  final double cx;
  final double cy;
  final double rx;
  final double ry;
  final double alpha;
  final double driftSpeed;
  _Cloud({
    required this.cx,
    required this.cy,
    required this.rx,
    required this.ry,
    required this.alpha,
    required this.driftSpeed,
  });
}

class _Sponsor {
  final double cx;
  final double cy;
  final double angle;
  final String text;
  _Sponsor({required this.cx, required this.cy, required this.angle, required this.text});
}
