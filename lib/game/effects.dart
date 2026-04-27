import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/theme.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// Lightweight effect components — each removes itself after its lifetime.
/// They're spawned by `CricketGame` in response to delivery events. Kept tiny
/// so we can throw a handful per delivery without GC pressure.
/// ───────────────────────────────────────────────────────────────────────────

class DustPuff extends Component {
  final Vector2 origin;
  final double duration;
  double _t = 0;
  final List<_Particle> _particles;

  DustPuff({required this.origin, this.duration = 0.55, math.Random? rng})
      : _particles = _makeParticles(rng ?? math.Random()) {
    priority = 6;
  }

  static List<_Particle> _makeParticles(math.Random rng) {
    return List.generate(10, (_) {
      final angle = -math.pi + rng.nextDouble() * math.pi; // upper hemisphere
      final speed = 30 + rng.nextDouble() * 70;
      return _Particle(
        offset: Vector2.zero(),
        velocity: Vector2(math.cos(angle) * speed, math.sin(angle) * speed),
        radius: 2 + rng.nextDouble() * 3,
        color: const Color(0xFFC9A97A),
      );
    });
  }

  @override
  void update(double dt) {
    _t += dt;
    for (final p in _particles) {
      p.offset += p.velocity * dt;
      p.velocity.y += 200 * dt; // gravity
      p.velocity *= 0.92;
    }
    if (_t >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final progress = (_t / duration).clamp(0.0, 1.0);
    final alpha = (1.0 - progress).clamp(0.0, 1.0);
    for (final p in _particles) {
      canvas.drawCircle(
        Offset(origin.x + p.offset.x, origin.y + p.offset.y),
        p.radius * (1 + progress * 0.6),
        Paint()..color = p.color.withValues(alpha: alpha * 0.7),
      );
    }
  }
}

class HitSpark extends Component {
  final Vector2 origin;
  final double duration;
  double _t = 0;
  final List<_Particle> _particles;

  HitSpark({required this.origin, this.duration = 0.45, math.Random? rng})
      : _particles = _makeParticles(rng ?? math.Random()) {
    priority = 7;
  }

  static List<_Particle> _makeParticles(math.Random rng) {
    return List.generate(14, (_) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed = 90 + rng.nextDouble() * 130;
      return _Particle(
        offset: Vector2.zero(),
        velocity: Vector2(math.cos(angle) * speed, math.sin(angle) * speed),
        radius: 1.5 + rng.nextDouble() * 2,
        color: rng.nextBool() ? kPalette.primary : Colors.white,
      );
    });
  }

  @override
  void update(double dt) {
    _t += dt;
    for (final p in _particles) {
      p.offset += p.velocity * dt;
      p.velocity *= 0.88;
    }
    if (_t >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final progress = (_t / duration).clamp(0.0, 1.0);
    final alpha = (1.0 - progress * progress).clamp(0.0, 1.0);

    // Central flash
    canvas.drawCircle(
      Offset(origin.x, origin.y),
      14 * (1 - progress),
      Paint()
        ..color = kPalette.primary.withValues(alpha: alpha * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    for (final p in _particles) {
      canvas.drawCircle(
        Offset(origin.x + p.offset.x, origin.y + p.offset.y),
        p.radius,
        Paint()..color = p.color.withValues(alpha: alpha),
      );
    }
  }
}

class BoundaryBurst extends Component {
  final Vector2 origin;
  final double duration;
  double _t = 0;
  final List<_Particle> _particles;
  final bool isSix;

  BoundaryBurst({
    required this.origin,
    required this.isSix,
    this.duration = 0.85,
    math.Random? rng,
  }) : _particles = _makeParticles(rng ?? math.Random(), isSix) {
    priority = 8;
  }

  static List<_Particle> _makeParticles(math.Random rng, bool isSix) {
    final n = isSix ? 30 : 22;
    return List.generate(n, (_) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed = 140 + rng.nextDouble() * 220;
      final colors = isSix
          ? [kPalette.primary, kPalette.accent, Colors.white, kPalette.primaryDark]
          : [kPalette.primary, Colors.white];
      return _Particle(
        offset: Vector2.zero(),
        velocity: Vector2(math.cos(angle) * speed, math.sin(angle) * speed),
        radius: 2 + rng.nextDouble() * 3,
        color: colors[rng.nextInt(colors.length)],
      );
    });
  }

  @override
  void update(double dt) {
    _t += dt;
    for (final p in _particles) {
      p.offset += p.velocity * dt;
      p.velocity *= 0.94;
      p.velocity.y += 140 * dt;
    }
    if (_t >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final progress = (_t / duration).clamp(0.0, 1.0);
    final alpha = (1.0 - progress).clamp(0.0, 1.0);
    // Expanding shock ring
    canvas.drawCircle(
      Offset(origin.x, origin.y),
      30 + progress * 220,
      Paint()
        ..color = kPalette.primary.withValues(alpha: alpha * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - progress) + 1,
    );
    for (final p in _particles) {
      canvas.drawCircle(
        Offset(origin.x + p.offset.x, origin.y + p.offset.y),
        p.radius,
        Paint()..color = p.color.withValues(alpha: alpha),
      );
    }
  }
}

/// Floating "+N" text that drifts upward and fades out.
class RunPopup extends Component {
  final Vector2 origin;
  final int runs;
  final double duration;
  double _t = 0;
  late final Color _baseColor;
  late final double _fontSize;

  RunPopup({required this.origin, required this.runs, this.duration = 0.95}) {
    priority = 9;
    _baseColor = runs == 6
        ? kPalette.accent
        : (runs == 4 ? kPalette.primary : Colors.white);
    _fontSize = runs >= 4 ? 36.0 : 26.0;
  }

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = (_t / duration).clamp(0.0, 1.0);
    final alpha = (1 - p * p).clamp(0.0, 1.0);
    final dy = -60 * Curves.easeOutCubic.transform(p);
    final scale =
        0.6 + 0.5 * Curves.easeOutBack.transform((p / 0.6).clamp(0.0, 1.0));

    final tp = TextPainter(
      text: TextSpan(
        text: '+$runs',
        style: TextStyle(
          color: _baseColor.withValues(alpha: alpha),
          fontSize: _fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          shadows: [
            Shadow(blurRadius: 14, color: _baseColor.withValues(alpha: alpha)),
            Shadow(blurRadius: 4, color: Colors.black.withValues(alpha: alpha)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(origin.x, origin.y + dy);
    canvas.scale(scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }
}

class _Particle {
  Vector2 offset;
  Vector2 velocity;
  final double radius;
  final Color color;
  _Particle({
    required this.offset,
    required this.velocity,
    required this.radius,
    required this.color,
  });
}

/// Slow-motion replay overlay — spawned by `CricketGame` on wickets / sixes.
/// Dims the live scene, redraws the captured ball trajectory at
/// `kReplayPlaybackSpeed` with a fading ghost trail, and displays a "REPLAY"
/// badge with a pulsing red dot. Self-removes after [duration]; calls
/// [onDone] on removal so the game can resume normal flow.
class ReplayOverlay extends Component with HasGameReference {
  final List<Vector2> frames;
  final List<double> times;
  final String label;
  final double duration;
  final VoidCallback? onDone;

  double _elapsed = 0;
  bool _signalledDone = false;

  ReplayOverlay({
    required this.frames,
    required this.times,
    required this.label,
    this.duration = kReplayDurationSec,
    this.onDone,
  }) {
    priority = 11; // above HUD (10)
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= duration) {
      if (!_signalledDone) {
        _signalledDone = true;
        onDone?.call();
      }
      removeFromParent();
    }
  }

  @override
  void onRemove() {
    if (!_signalledDone) {
      _signalledDone = true;
      onDone?.call();
    }
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    if (frames.isEmpty || times.isEmpty) return;
    final screen = game.size;
    // Dim the scene.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, screen.x, screen.y),
      Paint()..color = Colors.black.withValues(alpha: 0.40),
    );

    // Compute playhead time within the captured window.
    final t0 = times.first;
    final tEnd = times.last;
    final playFrac = (_elapsed / duration).clamp(0.0, 1.0);
    final playheadT = t0 + playFrac * (tEnd - t0);

    // Find the most recent captured index at or before the playhead.
    int playheadIdx = 0;
    for (int i = 0; i < times.length; i++) {
      if (times[i] <= playheadT) {
        playheadIdx = i;
      } else {
        break;
      }
    }

    // Trail — fade older frames.
    for (int i = 0; i <= playheadIdx; i++) {
      final age = (playheadIdx - i) / 28.0;
      if (age > 1.4) continue;
      final alpha = (1 - age * 0.7).clamp(0.0, 0.75);
      final r = (kBallRadius * (1 - age * 0.35)).clamp(2.0, kBallRadius);
      canvas.drawCircle(
        Offset(frames[i].x, frames[i].y),
        r,
        Paint()..color = kColorBall.withValues(alpha: alpha),
      );
    }

    // Current ball — bright, with a white outline.
    final live = frames[playheadIdx];
    canvas.drawCircle(
      Offset(live.x, live.y),
      kBallRadius * 1.25,
      Paint()..color = kColorBall,
    );
    canvas.drawCircle(
      Offset(live.x, live.y),
      kBallRadius * 1.25,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // "REPLAY" badge — top-center, pulsing red dot to the left.
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          letterSpacing: 5,
          shadows: [
            Shadow(blurRadius: 8, color: kPalette.danger.withValues(alpha: 0.8)),
            const Shadow(blurRadius: 3, color: Colors.black),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final badgeY = 56.0;
    final badgeX = (screen.x - tp.width) / 2;
    // Pulsing red dot
    final pulse = (math.sin(_elapsed * 6) + 1) / 2;
    canvas.drawCircle(
      Offset(badgeX - 18, badgeY + tp.height / 2),
      6 + pulse * 1.5,
      Paint()
        ..color = kPalette.danger.withValues(alpha: 0.7 + pulse * 0.3),
    );
    tp.paint(canvas, Offset(badgeX, badgeY));

    // Tagline below the badge.
    final tag = TextPainter(
      text: const TextSpan(
        text: 'SLOW MOTION',
        style: TextStyle(
          color: Colors.white60,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tag.paint(
      canvas,
      Offset((screen.x - tag.width) / 2, badgeY + tp.height + 2),
    );
  }
}
