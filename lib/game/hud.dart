import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../events/delivery_event.dart';
import '../events/delivery_event_bus.dart';
import '../services/shot_intent.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import 'ai_manager.dart';
import 'score_manager.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// Game HUD — broadcasted score panel, run rate, recent-balls strip, and
/// banner animations for SIX/FOUR/OUT events.
///
/// Owns its own state for performance: keeps a small ring buffer of recent
/// outcomes (driven by `BallSettled`) and animates the banner / run prompt
/// using local timers in `update()`. All drawing is via custom `paint()` —
/// no child TextComponents — so layout stays in one place.
/// ───────────────────────────────────────────────────────────────────────────
class GameHud extends PositionComponent with HasGameReference {
  final DeliveryEventBus eventBus;

  GameHud({required this.eventBus}) : super(priority: 10);

  // Live data driven by events.
  int _targetRuns = 0;
  int _targetWickets = 0;
  double _displayedRuns = 0; // lerps toward _targetRuns for tick-up effect
  double _displayedWickets = 0;
  String _overText = '0.0';
  double _runRate = 0;
  /// Set on `ScoreChanged.target` — only non-null during the AI chase.
  int? _target;
  /// Updated on every `BallLaunched`; renders as a small kind badge in the
  /// top-right corner so the player can read the attack type at a glance.
  BowlerKind? _bowlerKind;

  /// True from `FreeHitCalled` until the delivery settles. Drives a
  /// persistent "FREE HIT" pill rendered next to the bowler badge so the
  /// player knows they can't be bowled / caught for the rest of this ball.
  bool _freeHitActive = false;

  // Recent-balls ring buffer with per-entry age for the entry-pop animation.
  final List<_RecentEntry> _recent = [];
  static const int _recentMax = 8;

  // Run prompt (during running window).
  String _runPrompt = '';

  // Banner — shown briefly after SIX/FOUR/OUT.
  String _bannerText = '';
  Color _bannerColor = Colors.white;
  double _bannerElapsed = 999;
  static const double _bannerDuration = 1.2;

  // Commentary line — flavour text that fades in / out below the banner.
  String _commentary = '';
  double _commentaryElapsed = 999;
  static const double _commentaryDuration = 2.4;
  final math.Random _commentaryRng = math.Random();

  /// Per-event phrase pools — picked randomly so the same event doesn't
  /// always read the same line.
  static const Map<String, List<String>> _phrases = {
    'six': [
      "That's a peach!",
      'Sailed over the rope!',
      'Maximum!',
      'Out of the ground!',
      'Cleared it with ease.',
    ],
    'four': [
      'Cracking shot!',
      'Through the covers!',
      'To the boundary in a flash.',
      'Beautifully timed.',
      'Off the meat of the bat.',
    ],
    'wicket': [
      'Got him!',
      'Stumps cartwheeling!',
      'What a delivery!',
      'Big wicket — game on.',
      'Through the gate!',
    ],
    'caught': [
      'Brilliant catch!',
      'Held in the deep.',
      'Safe hands!',
      'Lapped it up.',
    ],
    'runOut': [
      'Direct hit — RUN OUT!',
      'Inches short!',
      'Glorious throw!',
    ],
    'edge': [
      'Just feathered it.',
      'Lucky escape — thin edge.',
      'Beat the bat for once.',
    ],
    'mistimed': [
      'Off the toe end.',
      "Couldn't get hold of it.",
    ],
    'saved': [
      'Saved at the rope!',
      'Heroic stop on the boundary.',
      'Great fielding!',
    ],
    'wide': [
      'Down the leg side — wide.',
      'Wayward delivery.',
    ],
    'noBall': [
      'Front foot fault!',
      'No ball — free hit coming.',
    ],
  };

  // ── TextPainter caches ─────────────────────────────────────────────────
  // The HUD redraws every frame; rebuilding a TextPainter per glyph per
  // frame is the single biggest GC source. We cache TPs keyed by the
  // values that actually drive their content, and rebuild only on change.
  TextPainter? _liveTagTp;
  TextPainter? _scoreTp;
  int _scoreCacheRuns = -1;
  int _scoreCacheWickets = -1;
  TextPainter? _overRrTp;
  String _overRrCacheKey = '';
  TextPainter? _targetTp;
  String _targetCacheKey = '';
  TextPainter? _bannerTp;
  String _bannerCacheKey = '';
  /// Pre-built labels for the recent-balls badges — fixed set, built once.
  final Map<BallOutcome, TextPainter> _badgeTps = {};

  // Score-panel pulse on score change + ambient clock for live-dot pulse.
  double _scorePulse = 0;
  double _clock = 0;

  StreamSubscription<DeliveryEvent>? _sub;

  @override
  Future<void> onLoad() async {
    size = game.size;
    _sub = eventBus.stream.listen(_onEvent);
    _liveTagTp = _buildPainter(
      'LIVE',
      TextStyle(
        color: kPalette.primary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 2.4,
      ),
    );
    // Pre-build the recent-balls badge labels — fixed strings, never change.
    for (final outcome in BallOutcome.values) {
      _badgeTps[outcome] = _buildPainter(
        outcome.label,
        TextStyle(
          color: outcome == BallOutcome.dot ? Colors.white60 : Colors.white,
          fontSize: outcome == BallOutcome.dot ? 18 : 14,
          fontWeight: FontWeight.w900,
        ),
      );
    }
  }

  /// Helper — build + layout a TextPainter once.
  TextPainter _buildPainter(String text, TextStyle style) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void _onEvent(DeliveryEvent event) {
    switch (event) {
      case ScoreChanged():
        // Parse "runs/wickets" and tick toward the new totals.
        final parts = event.scoreString.split('/');
        _targetRuns = int.tryParse(parts[0]) ?? _targetRuns;
        _targetWickets =
            parts.length > 1 ? (int.tryParse(parts[1]) ?? _targetWickets) : 0;
        _overText = event.overString;
        _runRate = event.runRate;
        _target = event.target;
        _scorePulse = 1.0;

      case BatContact():
        _runPrompt = 'TAP R / ⏎ TO RUN';

      case RunTaken():
        _runPrompt = 'RUNS THIS BALL: ${event.totalThisBall}';

      case BoundaryHit():
        _runPrompt = '';
        _showBanner(
          event.runs == kBoundarySixRuns ? 'SIX!' : 'FOUR!',
          event.runs == kBoundarySixRuns ? kPalette.primary : kPalette.accent,
        );
        _showCommentary(event.runs == kBoundarySixRuns ? 'six' : 'four');

      case WicketFallen():
        _runPrompt = '';
        _showBanner('OUT!', kPalette.danger);
        _showCommentary('wicket');

      case BallCaught():
        _runPrompt = '';
        _showBanner('OUT!', kPalette.danger);
        _showCommentary('caught');

      case RunOutCalled():
        _runPrompt = '';
        _showBanner('RUN OUT!', kPalette.danger);
        _showCommentary('runOut');

      case BallSettled(:final outcome):
        _recent.add(_RecentEntry(outcome));
        if (_recent.length > _recentMax) _recent.removeAt(0);
        // Free hit only covers the one delivery — drop the pill once the
        // ball settles. CricketGame may set it true again on the next
        // BallLaunched if back-to-back no-balls were bowled.
        _freeHitActive = false;

      case ExtraCalled():
        _runPrompt = '';
        _showBanner(
          event.kind == ExtraKind.wide ? 'WIDE!' : 'NO BALL!',
          const Color(0xFF42A5F5),
        );
        _showCommentary(event.kind == ExtraKind.wide ? 'wide' : 'noBall');

      case ShotQualityCalled(:final quality):
        // Small mistime / edge feedback flashed via the same banner system.
        // Edge uses the danger color so it visually warns "you might be out".
        if (quality == ShotQuality.edge) {
          _showBanner('EDGE!', kPalette.danger);
          _showCommentary('edge');
        } else if (quality == ShotQuality.mistimed) {
          _showBanner('MISTIMED', const Color(0xFFFFCC00));
          _showCommentary('mistimed');
        }

      case BoundarySaved():
        _showBanner('SAVED!', kPalette.primary);
        _showCommentary('saved');

      case FreeHitCalled():
        // Set the persistent pill (rendered alongside the bowler badge)
        // and pop a transient banner so the cue is unmissable.
        _freeHitActive = true;
        _showBanner('FREE HIT', const Color(0xFF42A5F5));

      case BallFielded() || BallDead():
        _runPrompt = '';

      case BallLaunched():
        _runPrompt = '';
        _bannerElapsed = _bannerDuration; // hide
        _bowlerKind = event.config.kind;
    }
  }

  void _showBanner(String text, Color color) {
    _bannerText = text;
    _bannerColor = color;
    _bannerElapsed = 0;
  }

  /// Pick a random commentary line from `_phrases[key]` and start a fresh
  /// fade-in/out cycle. Silent if the key has no phrase pool.
  void _showCommentary(String key) {
    final pool = _phrases[key];
    if (pool == null || pool.isEmpty) return;
    _commentary = pool[_commentaryRng.nextInt(pool.length)];
    _commentaryElapsed = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _clock += dt;
    if (_bannerElapsed < _bannerDuration) _bannerElapsed += dt;
    if (_commentaryElapsed < _commentaryDuration) _commentaryElapsed += dt;
    if (_scorePulse > 0) {
      _scorePulse = math.max(0, _scorePulse - dt * 3);
    }
    // Tick-up: lerp displayed numbers toward target. ~12 units/sec for runs
    // so a +6 boundary takes about half a second to count up.
    final dr = _targetRuns - _displayedRuns;
    if (dr.abs() > 0.05) {
      final step = math.max(dt * 14, dt * dr.abs() * 4);
      if (step >= dr.abs()) {
        _displayedRuns = _targetRuns.toDouble();
      } else {
        _displayedRuns += dr.sign * step;
      }
    } else {
      _displayedRuns = _targetRuns.toDouble();
    }
    final dw = _targetWickets - _displayedWickets;
    if (dw.abs() > 0.05) {
      _displayedWickets += dw.sign * dt * 6;
    } else {
      _displayedWickets = _targetWickets.toDouble();
    }
    // Age out badge entries (drives the pop-in).
    for (final e in _recent) {
      if (e.age < 1) e.age += dt;
    }
  }

  @override
  void render(Canvas canvas) {
    final w = size.x;

    _renderScorePanel(canvas);
    _renderTargetLine(canvas);
    _renderBowlerBadge(canvas, w);
    if (_freeHitActive) _renderFreeHitBadge(canvas, w);
    _renderRecentBalls(canvas, w);
    if (_runPrompt.isNotEmpty) _renderRunPrompt(canvas, w);
    if (_bannerElapsed < _bannerDuration) _renderBanner(canvas);
    if (_commentaryElapsed < _commentaryDuration) _renderCommentary(canvas, w);
  }

  /// Italic commentary line below the banner. Fade-in/out over the
  /// commentary duration; centred horizontally.
  void _renderCommentary(Canvas canvas, double w) {
    final t = (_commentaryElapsed / _commentaryDuration).clamp(0.0, 1.0);
    // Fade-in 0..0.18, hold, fade-out 0.75..1.0.
    double alpha;
    if (t < 0.18) {
      alpha = t / 0.18;
    } else if (t > 0.75) {
      alpha = (1 - t) / 0.25;
    } else {
      alpha = 1;
    }
    alpha = alpha.clamp(0.0, 1.0);
    if (alpha <= 0.01) return;
    final tp = TextPainter(
      text: TextSpan(
        text: _commentary,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92 * alpha),
          fontSize: 16,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          shadows: [
            Shadow(blurRadius: 6, color: Colors.black.withValues(alpha: 0.8)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w * 0.85);
    final y = size.y * 0.46; // just under the banner (which sits at ~0.40)
    tp.paint(canvas, Offset((w - tp.width) / 2, y));
  }

  /// Small pill below the recent-balls strip showing the current bowler
  /// archetype label (Pacer / Medium / Swing / Spinner). Tinted by kind so
  /// the player can tell at a glance what they're facing.
  TextPainter? _bowlerKindTp;
  BowlerKind? _bowlerKindTpKey;
  void _renderBowlerBadge(Canvas canvas, double w) {
    final kind = _bowlerKind;
    if (kind == null) return;
    if (_bowlerKindTp == null || _bowlerKindTpKey != kind) {
      _bowlerKindTpKey = kind;
      _bowlerKindTp = _buildPainter(
        kind.label.toUpperCase(),
        TextStyle(
          color: _kindColor(kind),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.8,
        ),
      );
    }
    final tp = _bowlerKindTp!;
    final padX = 10.0;
    final padY = 4.0;
    final pillW = tp.width + padX * 2 + 14; // +14 for the leading dot
    final pillH = tp.height + padY * 2;
    final cx = w / 2;
    final pillRect = Rect.fromCenter(
      center: Offset(cx, 64), // sat under the recent-balls strip (~y 30)
      width: pillW,
      height: pillH,
    );
    final pill = RRect.fromRectAndRadius(pillRect, const Radius.circular(12));
    canvas.drawRRect(pill, Paint()..color = const Color(0xCC0E1A0F));
    canvas.drawRRect(
      pill,
      Paint()
        ..color = _kindColor(kind).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    // Coloured dot leading the label.
    canvas.drawCircle(
      Offset(pillRect.left + padX + 3, pillRect.center.dy),
      3.4,
      Paint()..color = _kindColor(kind),
    );
    tp.paint(
        canvas, Offset(pillRect.left + padX + 12, pillRect.top + padY));
  }

  /// Persistent "FREE HIT" pill — sits to the right of the bowler badge for
  /// the duration of the delivery after a no-ball. Cleared on `BallSettled`.
  void _renderFreeHitBadge(Canvas canvas, double w) {
    final tp = _buildPainter(
      'FREE HIT',
      const TextStyle(
        color: Color(0xFF42A5F5),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.8,
      ),
    );
    const padX = 10.0;
    const padY = 4.0;
    final pillW = tp.width + padX * 2;
    final pillH = tp.height + padY * 2;
    // Sit just below the bowler-kind pill, same y band the recent-ball strip
    // and bowler badge already occupy. Centre-aligned, offset down so it
    // doesn't overlap the bowler pill at y=64.
    final pillRect = Rect.fromCenter(
      center: Offset(w / 2, 88),
      width: pillW,
      height: pillH,
    );
    final pill = RRect.fromRectAndRadius(pillRect, const Radius.circular(12));
    // Pulsing alpha so the pill catches the eye.
    final pulse = (math.sin(_clock * 4.5) + 1) / 2; // 0..1
    canvas.drawRRect(
      pill,
      Paint()..color = const Color(0xCC0E1A28),
    );
    canvas.drawRRect(
      pill,
      Paint()
        ..color = const Color(0xFF42A5F5)
            .withValues(alpha: 0.55 + pulse * 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    tp.paint(canvas, Offset(pillRect.left + padX, pillRect.top + padY));
  }

  Color _kindColor(BowlerKind k) {
    switch (k) {
      case BowlerKind.pacer:
        return const Color(0xFFFF5252); // red — fast
      case BowlerKind.medium:
        return const Color(0xFFFFB74D); // amber — workhorse
      case BowlerKind.swing:
        return const Color(0xFF4FC3F7); // sky — swing
      case BowlerKind.spinner:
        return const Color(0xFFAB47BC); // purple — spin
    }
  }

  // ── Score panel (top-left) ──────────────────────────────────────────────
  void _renderScorePanel(Canvas canvas) {
    final pulse = 1 + _scorePulse * 0.05;
    final pad = 14.0;
    final panelW = 240.0 * pulse;
    final panelH = 78.0 * pulse;
    final panelRect = Rect.fromLTWH(12, 12, panelW, panelH);

    final rrect = RRect.fromRectAndRadius(panelRect, const Radius.circular(14));
    // Drop shadow
    canvas.drawRRect(
      rrect.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Gradient fill
    canvas.drawRRect(
      rrect,
      Paint()..shader = AppGradients.panel().createShader(panelRect),
    );
    // Gold border
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = kPalette.primary.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Top-left LIVE tag with pulsing red dot
    final dotPulse = 0.6 + 0.4 * math.sin(_clock * 4.5);
    canvas.drawCircle(
      Offset(panelRect.left + pad + 3, panelRect.top + 12),
      3.6,
      Paint()
        ..color = kPalette.accent.withValues(alpha: 0.45 * dotPulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(panelRect.left + pad + 3, panelRect.top + 12),
      3,
      Paint()..color = kPalette.accent.withValues(alpha: dotPulse),
    );
    _liveTagTp?.paint(
        canvas, Offset(panelRect.left + pad + 12, panelRect.top + 6));
    // Big score (lerped tick-up) — TP cached, rebuilt only when integers move.
    final shownRuns = _displayedRuns.round();
    final shownWickets = _displayedWickets.round();
    if (_scoreTp == null ||
        _scoreCacheRuns != shownRuns ||
        _scoreCacheWickets != shownWickets) {
      _scoreCacheRuns = shownRuns;
      _scoreCacheWickets = shownWickets;
      _scoreTp = _buildPainter(
        '$shownRuns/$shownWickets',
        const TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w900,
          height: 1.0,
          letterSpacing: 0.5,
        ),
      );
    }
    _scoreTp!.paint(canvas, Offset(panelRect.left + pad, panelRect.top + 18));
    // Overs · run rate — cache key combines both source values.
    final overRrKey =
        '$_overText|${_runRate.toStringAsFixed(2)}';
    if (_overRrTp == null || _overRrCacheKey != overRrKey) {
      _overRrCacheKey = overRrKey;
      _overRrTp = _buildPainter(
        'OV $_overText   ·   RR ${_runRate.toStringAsFixed(2)}',
        const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      );
    }
    _overRrTp!.paint(
        canvas, Offset(panelRect.left + pad, panelRect.top + panelH - 22));
  }

  /// Chase-mode line — drawn just below the score panel when `_target` is
  /// set. Shows "TARGET 88 · NEED 12 IN 24".
  void _renderTargetLine(Canvas canvas) {
    final tgt = _target;
    if (tgt == null) return;
    final shownRuns = _targetRuns;
    final need = (tgt - shownRuns).clamp(0, 999);
    final key = '$tgt|$shownRuns';
    if (_targetTp == null || _targetCacheKey != key) {
      _targetCacheKey = key;
      _targetTp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'TARGET ',
              style: TextStyle(color: kPalette.primary, fontSize: 12),
            ),
            TextSpan(
              text: '$tgt',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900),
            ),
            const TextSpan(
              text: '   ·   NEED ',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            TextSpan(
              text: '$need',
              style: TextStyle(
                  color: need == 0 ? kPalette.primary : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900),
            ),
          ],
          style:
              const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    final tp = _targetTp!;
    final padX = 14.0;
    final padY = 6.0;
    final rect = Rect.fromLTWH(
      12,
      96, // just below the 78px tall score panel + 6px gap
      tp.width + padX * 2,
      tp.height + padY * 2,
    );
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
        rr, Paint()..color = const Color(0xCC0E1A0F));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = kPalette.primary.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    tp.paint(canvas, Offset(rect.left + padX, rect.top + padY));
  }

  // ── Recent balls strip (top-center) ─────────────────────────────────────
  void _renderRecentBalls(Canvas canvas, double w) {
    if (_recent.isEmpty) return;
    const r = 14.0;
    const gap = 6.0;
    final count = _recent.length;
    final stripW = count * (r * 2) + (count - 1) * gap;
    final startX = (w - stripW) / 2;
    final cy = 30.0;

    // Backing pill
    final backing = Rect.fromLTWH(startX - 12, cy - r - 6, stripW + 24, r * 2 + 12);
    final backRR = RRect.fromRectAndRadius(backing, const Radius.circular(20));
    canvas.drawRRect(
      backRR,
      Paint()..color = const Color(0xCC0E1A0F),
    );
    canvas.drawRRect(
      backRR,
      Paint()
        ..color = kPalette.primary.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    for (int i = 0; i < count; i++) {
      final cx = startX + r + i * (r * 2 + gap);
      final entry = _recent[i];
      final outcome = entry.outcome;
      final color = _outcomeColor(outcome);

      // Entry pop animation — overshoot + settle over ~0.45s.
      const popDur = 0.45;
      final p = (entry.age / popDur).clamp(0.0, 1.0);
      final scale = p < 1
          ? Curves.easeOutBack.transform(p) // 0..~1.1..1
          : 1.0;
      final entryAlpha = p < 1 ? p : 1.0;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.scale(scale);

      // Soft glow for boundaries / wickets — extra pop on entry.
      if (outcome == BallOutcome.four ||
          outcome == BallOutcome.six ||
          outcome == BallOutcome.wicket) {
        final glowR = r + 4 + (1 - p) * 8;
        canvas.drawCircle(
          Offset.zero,
          glowR,
          Paint()
            ..color = color.withValues(alpha: 0.45 * entryAlpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawCircle(Offset.zero, r,
          Paint()..color = color.withValues(alpha: entryAlpha));
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25 * entryAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
      // Cached label — apply per-frame alpha via canvas.saveLayer.
      final tp = _badgeTps[outcome]!;
      if (entryAlpha < 0.999) {
        canvas.saveLayer(
          Rect.fromCircle(center: Offset.zero, radius: r + 4),
          Paint()
            ..colorFilter = ColorFilter.mode(
              Colors.white.withValues(alpha: entryAlpha),
              BlendMode.modulate,
            ),
        );
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      } else {
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      }
      canvas.restore();
    }
  }

  Color _outcomeColor(BallOutcome o) {
    switch (o) {
      case BallOutcome.dot:
        return const Color(0xCC1F2A37);
      case BallOutcome.one:
      case BallOutcome.two:
      case BallOutcome.three:
        return const Color(0xCC2E7D32);
      case BallOutcome.four:
        return kPalette.primary;
      case BallOutcome.six:
        return kPalette.accent;
      case BallOutcome.wicket:
        return kPalette.danger;
    }
  }

  // ── Run prompt (bottom-center) ──────────────────────────────────────────
  void _renderRunPrompt(Canvas canvas, double w) {
    final cy = size.y - 56;
    // Pulsing alpha
    final pulse = 0.55 + 0.45 * math.sin(DateTime.now().millisecondsSinceEpoch / 220);
    final tp = TextPainter(
      text: TextSpan(
        text: _runPrompt,
        style: TextStyle(
          color: kPalette.primary.withValues(alpha: pulse.clamp(0.0, 1.0)),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.2,
          shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final padX = 18.0;
    final padY = 8.0;
    final pillW = tp.width + padX * 2;
    final pillH = tp.height + padY * 2;
    final pillRect = Rect.fromCenter(
      center: Offset(w / 2, cy),
      width: pillW,
      height: pillH,
    );
    final pillRR = RRect.fromRectAndRadius(pillRect, const Radius.circular(18));
    canvas.drawRRect(
      pillRR,
      Paint()..color = const Color(0xDD0D1E0F),
    );
    canvas.drawRRect(
      pillRR,
      Paint()
        ..color = kPalette.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    tp.paint(
        canvas, Offset(pillRect.left + padX, pillRect.top + padY));
  }

  // ── Banner — SIX/FOUR/OUT animated text ─────────────────────────────────
  void _renderBanner(Canvas canvas) {
    final t = (_bannerElapsed / _bannerDuration).clamp(0.0, 1.0);
    // Slide-in for first 30%, hold 40%, fade-out last 30%.
    double alpha;
    double scale;
    double dx;
    if (t < 0.30) {
      final p = t / 0.30;
      alpha = p;
      scale = 0.6 + 0.4 * p;
      dx = -80.0 * (1 - p);
    } else if (t < 0.70) {
      alpha = 1.0;
      scale = 1.0 + math.sin((t - 0.30) * math.pi / 0.40) * 0.04;
      dx = 0;
    } else {
      final p = (t - 0.70) / 0.30;
      alpha = 1.0 - p;
      scale = 1.0 + p * 0.15;
      dx = 0;
    }

    final cx = size.x / 2 + dx;
    final cy = size.y * 0.36;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);
    // Glow halo
    canvas.drawCircle(
      Offset.zero,
      80,
      Paint()
        ..color = _bannerColor.withValues(alpha: alpha * 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32),
    );
    // Cache the banner TP — text + colour change rarely; the per-frame
    // alpha is applied via a layer colour-filter so we never rebuild the TP
    // each frame.
    final bannerKey = '$_bannerText|${_bannerColor.toARGB32()}';
    if (_bannerTp == null || _bannerCacheKey != bannerKey) {
      _bannerCacheKey = bannerKey;
      _bannerTp = _buildPainter(
        _bannerText,
        TextStyle(
          color: Colors.white,
          fontSize: 84,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
          shadows: [
            Shadow(blurRadius: 18, color: _bannerColor),
            const Shadow(blurRadius: 6, color: Colors.black),
          ],
        ),
      );
    }
    final tp = _bannerTp!;
    if (alpha < 0.999) {
      canvas.saveLayer(
        Rect.fromCenter(
            center: Offset.zero, width: tp.width + 80, height: tp.height + 80),
        Paint()
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: alpha),
            BlendMode.modulate,
          ),
      );
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    } else {
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    }
    canvas.restore();
  }

  @override
  void onRemove() {
    _sub?.cancel();
    super.onRemove();
  }
}

class _RecentEntry {
  final BallOutcome outcome;
  /// Seconds since this entry appeared. New entries pop in from 0.
  double age = 0;
  _RecentEntry(this.outcome);
}
