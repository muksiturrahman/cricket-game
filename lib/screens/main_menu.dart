import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/ai_manager.dart';
import '../game/batsman.dart';
import '../game/cricket_game.dart';
import '../game/score_manager.dart';
import '../services/save_service.dart';
import '../services/stats_service.dart';
import '../state/game_state_notifier.dart';
import '../state/match_settings.dart';
import '../utils/theme.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// Overlays — main menu, pause, game over.
///
/// All three share a single visual language defined in `lib/utils/theme.dart`:
///   - Gradient background
///   - Glassy panels with gold borders
///   - Big rounded buttons with gradient fill
///   - Pill selectors for choices
/// ───────────────────────────────────────────────────────────────────────────

class MainMenuOverlay extends StatefulWidget {
  final CricketGame game;
  const MainMenuOverlay({super.key, required this.game});

  @override
  State<MainMenuOverlay> createState() => _MainMenuOverlayState();
}

class _MainMenuOverlayState extends State<MainMenuOverlay>
    with TickerProviderStateMixin {
  MatchFormat _format = MatchFormat.t5;
  Difficulty _difficulty = Difficulty.normal;
  bool _chase = false;
  PitchType _pitch = PitchType.flat;
  FieldPreset _field = FieldPreset.defensive;
  DayNight _time = DayNight.day;
  late final AnimationController _entry;
  late final AnimationController _badgeSpin;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _badgeSpin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _entry.dispose();
    _badgeSpin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StadiumBackdrop(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: AnimatedBuilder(
                animation: _entry,
                builder: (context, child) {
                  final t = Curves.easeOutCubic.transform(_entry.value);
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 28),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _badgeSpin,
                      builder: (_, _) =>
                          CricketEmblem(rotation: _badgeSpin.value * math.pi * 2),
                    ),
                    const SizedBox(height: 14),
                    const Text('CRICKET', style: AppText.hero),
                    const SizedBox(height: 4),
                    Text(
                      'STADIUM PRO',
                      style: AppText.label.copyWith(
                        color: kPalette.primary,
                        fontSize: 13,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _CareerStatsStrip(),
                    const SizedBox(height: 14),
                    _Card(
                      child: Column(
                        children: [
                          _SectionLabel(text: 'Match Format'),
                          const SizedBox(height: 8),
                          _PillRow<MatchFormat>(
                            values: MatchFormat.values,
                            selected: _format,
                            labelOf: (f) => f.label,
                            onSelected: (f) => setState(() => _format = f),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatBlurb(_format),
                            style: AppText.body.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 18),
                          _SectionLabel(text: 'Difficulty'),
                          const SizedBox(height: 8),
                          _PillRow<Difficulty>(
                            values: Difficulty.values,
                            selected: _difficulty,
                            labelOf: (d) => d.label,
                            onSelected: (d) =>
                                setState(() => _difficulty = d),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _difficultyBlurb(_difficulty),
                            style: AppText.body.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 18),
                          _SectionLabel(text: 'Mode'),
                          const SizedBox(height: 8),
                          _PillRow<bool>(
                            values: const [false, true],
                            selected: _chase,
                            labelOf: (b) => b ? 'Chase (2 innings)' : 'Free hit',
                            onSelected: (b) => setState(() => _chase = b),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _chase
                                ? 'You bat first, then the AI chases your total'
                                : 'Single innings — score as much as you can',
                            style: AppText.body.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 18),
                          _SectionLabel(text: 'Pitch'),
                          const SizedBox(height: 8),
                          _PillRow<PitchType>(
                            values: PitchType.values,
                            selected: _pitch,
                            labelOf: (p) => p.label,
                            onSelected: (p) => setState(() => _pitch = p),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _pitch.blurb,
                            style: AppText.body.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 18),
                          _SectionLabel(text: 'Field'),
                          const SizedBox(height: 8),
                          _PillRow<FieldPreset>(
                            values: FieldPreset.values,
                            selected: _field,
                            labelOf: (f) => f.label,
                            onSelected: (f) => setState(() => _field = f),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _field.blurb,
                            style: AppText.body.copyWith(fontSize: 12),
                          ),
                          const SizedBox(height: 18),
                          _SectionLabel(text: 'Time'),
                          const SizedBox(height: 8),
                          _PillRow<DayNight>(
                            values: DayNight.values,
                            selected: _time,
                            labelOf: (t) => t.label,
                            onSelected: (t) => setState(() => _time = t),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _ResumeButton(game: widget.game),
                    _BigButton(
                      label: 'PLAY MATCH',
                      gradient: AppGradients.goldButton(),
                      icon: Icons.sports_cricket,
                      onTap: () => widget.game.startGame(MatchSettings(
                        format: _format,
                        difficulty: _difficulty,
                        chase: _chase,
                        pitchType: _pitch,
                        fieldPreset: _field,
                        timeOfDay: _time,
                      )),
                    ),
                    const SizedBox(height: 10),
                    const _HowToPlayButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatBlurb(MatchFormat f) {
    switch (f) {
      case MatchFormat.t5:
        return '5 overs · 30 balls · sharp innings';
      case MatchFormat.t10:
        return '10 overs · 60 balls · build & accelerate';
      case MatchFormat.t20:
        return '20 overs · 120 balls · full match length';
    }
  }

  String _difficultyBlurb(Difficulty d) {
    switch (d) {
      case Difficulty.easy:
        return 'Slower bowling, longer swing window';
      case Difficulty.normal:
        return 'Standard speeds and timing';
      case Difficulty.hard:
        return 'Express bowling, tight swing window';
    }
  }
}

// ── Pause overlay ─────────────────────────────────────────────────────────────

class PauseOverlay extends StatelessWidget {
  final CricketGame game;
  const PauseOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return StadiumBackdrop(
      darken: 0.7,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pause_circle_filled,
                          color: kPalette.primary, size: 30),
                      const SizedBox(width: 10),
                      const Text('PAUSED', style: AppText.h1),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _BigButton(
                    label: 'RESUME',
                    gradient: AppGradients.goldButton(),
                    icon: Icons.play_arrow,
                    onTap: game.togglePause,
                  ),
                  const SizedBox(height: 10),
                  _BigButton(
                    label: 'RESTART',
                    gradient: AppGradients.redButton(),
                    icon: Icons.refresh,
                    onTap: game.restartGame,
                  ),
                  const SizedBox(height: 10),
                  _BigButton(
                    label: 'MAIN MENU',
                    gradient: AppGradients.slateButton(),
                    icon: Icons.home,
                    onTap: game.quitToMenu,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Game-over overlay ─────────────────────────────────────────────────────────

class GameOverOverlay extends StatelessWidget {
  final CricketGame game;
  const GameOverOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<GameStateNotifier>();
    final score = notifier.finalScore;
    final firstInnings = notifier.firstInningsScore;
    final sm = game.scoreManager;
    final result = _resolveResult(score, firstInnings);
    return StadiumBackdrop(
      darken: 0.78,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
              child: _Card(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result?.title ?? 'INNINGS OVER',
                      style: AppText.label.copyWith(
                        color: result?.tone ?? kPalette.primary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (result != null) ...[
                      Text(
                        result.message,
                        textAlign: TextAlign.center,
                        style: AppText.h2.copyWith(
                          color: result.tone,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (firstInnings != null) ...[
                      Text(
                        '1ST INNINGS',
                        style: AppText.label.copyWith(fontSize: 10),
                      ),
                      Text(
                        '${firstInnings.runs}/${firstInnings.wickets}  ·  ${firstInnings.overString} ov',
                        style: AppText.h2.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '2ND INNINGS',
                        style: AppText.label.copyWith(
                            fontSize: 10, color: kPalette.primary),
                      ),
                    ],
                    // Big score row
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${score.runs}',
                            style: AppText.scoreBig.copyWith(fontSize: 76),
                          ),
                          TextSpan(
                            text: ' / ${score.wickets}',
                            style: AppText.scoreBig.copyWith(
                                fontSize: 36, color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${score.overString} OVERS',
                      style: AppText.h2.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 18),
                    _StatGrid(
                      stats: [
                        _Stat(
                            'RUN RATE',
                            sm.ballsBowled > 0
                                ? sm.runRate.toStringAsFixed(2)
                                : '0.00'),
                        _Stat('FOURS', '${sm.fours}'),
                        _Stat('SIXES', '${sm.sixes}'),
                        _Stat('DOTS', '${sm.dots}'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _RecentStrip(history: sm.ballHistory),
                    const SizedBox(height: 14),
                    _BattingCard(
                      striker: game.striker,
                      nonStriker: game.nonStriker,
                      retired: game.retiredBatsmen,
                    ),
                    const SizedBox(height: 10),
                    _BowlingCard(stats: game.bowlerStats),
                    const SizedBox(height: 22),
                    _BigButton(
                      label: 'PLAY AGAIN',
                      gradient: AppGradients.goldButton(),
                      icon: Icons.replay,
                      onTap: game.restartGame,
                    ),
                    const SizedBox(height: 10),
                    _BigButton(
                      label: 'MAIN MENU',
                      gradient: AppGradients.slateButton(),
                      icon: Icons.home,
                      onTap: game.quitToMenu,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// In chase mode, decide who won. Returns null for single-innings matches.
  _MatchResult? _resolveResult(
      ScoreSnapshot aiScore, ScoreSnapshot? firstInnings) {
    if (firstInnings == null) return null;
    final target = firstInnings.runs + 1;
    if (aiScore.runs >= target) {
      // AI reached the target → AI wins.
      final wicketsLeft = 10 - aiScore.wickets;
      return _MatchResult(
        title: 'AI WINS',
        message: 'AI chased ${firstInnings.runs} '
            'with $wicketsLeft wicket${wicketsLeft == 1 ? '' : 's'} to spare',
        tone: const Color(0xFFE53935),
      );
    }
    final margin = target - 1 - aiScore.runs;
    return _MatchResult(
      title: 'YOU WIN',
      message: 'Defended ${firstInnings.runs} by '
          '$margin run${margin == 1 ? '' : 's'}',
      tone: kPalette.primary,
    );
  }
}

class _MatchResult {
  final String title;
  final String message;
  final Color tone;
  const _MatchResult({
    required this.title,
    required this.message,
    required this.tone,
  });
}

/// Resume-match call-to-action — only renders when `SaveService` holds a
/// snapshot. Shows the saved-match summary inline so the player knows what
/// they're returning to. Tapping calls `game.resumeMatch(...)` which
/// rebuilds scoreboard state and launches the next delivery.
class _ResumeButton extends StatelessWidget {
  final CricketGame game;
  const _ResumeButton({required this.game});

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<SaveService>().current;
    if (saved == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          _BigButton(
            label: 'RESUME MATCH',
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF26A69A), Color(0xFF00695C)],
            ),
            icon: Icons.play_arrow,
            onTap: () => game.resumeMatch(saved),
          ),
          const SizedBox(height: 4),
          Text(
            saved.summary,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Career stats strip rendered above the format/difficulty card on the
/// main menu. Watches `StatsService` so it auto-updates after a match
/// completes (no need to navigate away and back).
class _CareerStatsStrip extends StatelessWidget {
  const _CareerStatsStrip();

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<StatsService>().current;
    if (stats.matchesPlayed == 0) {
      return const SizedBox.shrink();
    }
    final winRate = stats.matchesPlayed > 0
        ? (stats.matchesWon / stats.matchesPlayed * 100).round()
        : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: AppGradients.panel(),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x44FFC93C), width: 1.0),
      ),
      child: Column(
        children: [
          Text(
            'CAREER',
            style: AppText.label.copyWith(
              color: kPalette.primary,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip(label: 'BEST', value: '${stats.bestScore}'),
              _StatChip(label: 'M', value: '${stats.matchesPlayed}'),
              _StatChip(label: 'W%', value: '$winRate'),
              _StatChip(label: '4s', value: '${stats.totalFours}'),
              _StatChip(label: '6s', value: '${stats.totalSixes}'),
            ],
          ),
          if (stats.recentMatches.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: Color(0x33FFC93C), height: 1),
            const SizedBox(height: 8),
            Text(
              'LAST ${stats.recentMatches.length} MATCHES',
              style: AppText.label.copyWith(
                color: kPalette.primary,
                fontSize: 9,
              ),
            ),
            const SizedBox(height: 6),
            // Each row: format · runs/wickets · result chip
            for (final m in stats.recentMatches.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        m.format,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${m.runs}/${m.wickets}'
                        '  ·  ${m.fours}×4  ${m.sixes}×6',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: m.won
                            ? const Color(0xFF34C759).withValues(alpha: 0.22)
                            : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        m.won ? 'WON' : '—',
                        style: TextStyle(
                          color: m.won
                              ? const Color(0xFF34C759)
                              : Colors.white60,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class StadiumBackdrop extends StatelessWidget {
  final Widget child;
  final double darken;
  const StadiumBackdrop({super.key, required this.child, this.darken = 0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base gradient
        DecoratedBox(
          decoration: BoxDecoration(gradient: AppGradients.menuBackdrop()),
        ),
        // Subtle vignette
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [Colors.transparent, Color(0xCC000000)],
              radius: 1.2,
              center: Alignment.center,
            ),
          ),
        ),
        // Diagonal highlight stripes
        Positioned.fill(child: CustomPaint(painter: _StripePainter())),
        if (darken > 0)
          ColoredBox(
              color: Colors.black.withValues(alpha: darken),
              child: const SizedBox.expand()),
        child,
      ],
    );
  }
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.025);
    const stripeW = 80.0;
    for (double x = -size.height; x < size.width; x += stripeW * 2) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + stripeW, 0)
        ..lineTo(x + stripeW + size.height, size.height)
        ..lineTo(x + size.height, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CricketEmblem extends StatelessWidget {
  final double rotation;
  const CricketEmblem({super.key, required this.rotation});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: CustomPaint(painter: _EmblemPainter(rotation: rotation)),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  final double rotation;
  _EmblemPainter({required this.rotation});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Outer rotating ring
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(rotation);
    final r = size.width * 0.45;
    final paint = Paint()
      ..shader = ui.Gradient.sweep(
        Offset.zero,
        [
          kPalette.primary,
          kPalette.primary.withValues(alpha: 0),
          kPalette.primary,
        ],
        const [0.0, 0.5, 1.0],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset.zero, r, paint);
    canvas.restore();

    // Inner solid ring
    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.32,
      Paint()..color = kPalette.surface,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.32,
      Paint()
        ..color = kPalette.primary.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // Bat icon
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-math.pi / 4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 8, height: 36),
        const Radius.circular(2.5),
      ),
      Paint()..color = const Color(0xFFE5C282),
    );
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(0, -22), width: 3, height: 12),
      Paint()..color = const Color(0xFF6B3F1A),
    );
    canvas.restore();

    // Ball
    canvas.drawCircle(
      Offset(cx + 12, cy + 12),
      6,
      Paint()..color = kPalette.accent,
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx + 12, cy + 12), radius: 5.4),
      -0.6,
      1.2,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter oldDelegate) =>
      oldDelegate.rotation != rotation;
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppPanels.card(),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(width: 30, height: 1.2, color: kPalette.primary),
        const SizedBox(width: 10),
        Text(text.toUpperCase(),
            style: AppText.label.copyWith(color: kPalette.primary)),
        const SizedBox(width: 10),
        Container(width: 30, height: 1.2, color: kPalette.primary),
      ],
    );
  }
}

class _PillRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  const _PillRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          GestureDetector(
            onTap: () => onSelected(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: AppPanels.pill(selected: v == selected),
              child: Text(
                labelOf(v),
                style: TextStyle(
                  color: v == selected
                      ? const Color(0xFF1A1100)
                      : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 1.6,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BigButton extends StatefulWidget {
  final String label;
  final LinearGradient gradient;
  final IconData? icon;
  final VoidCallback onTap;

  const _BigButton({
    required this.label,
    required this.gradient,
    required this.onTap,
    this.icon,
  });

  @override
  State<_BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<_BigButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: AppPanels.bigButton(widget.gradient),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 20),
                const SizedBox(width: 10),
              ],
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HowToPlayButton extends StatelessWidget {
  const _HowToPlayButton();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.7),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _Card(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.menu_book_rounded,
                          color: kPalette.primary, size: 22),
                      const SizedBox(width: 10),
                      const Text('How to Play', style: AppText.h1),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _HelpSection(
                    title: 'POSITION (LEG ↔ OFF)',
                    rows: const [
                      ['Hold ← or A', 'Step to leg side'],
                      ['Hold → or D', 'Step to off side'],
                      ['Drag the batsman', 'Touch — slow drag = move'],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HelpSection(
                    title: 'PLAY A SHOT',
                    rows: const [
                      ['Swipe → / V', 'Straight Drive'],
                      ['Swipe ↑ / W / ↑', 'Pull Shot'],
                      ['Swipe ← / C', 'Cover Drive'],
                      ['Tap / S / ↓ / ⎵', 'Defensive'],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HelpSection(
                    title: 'TAKE RUNS',
                    rows: const [
                      ['R or ⏎', 'Take a single — repeat for 2/3'],
                      ['~0.55s cooldown', 'Between consecutive runs'],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HelpSection(
                    title: 'BOUNDARIES',
                    rows: const [
                      ['Cleared on the fly', 'SIX (+6)'],
                      ['Cleared after bounce', 'FOUR (+4)'],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HelpSection(
                    title: 'WICKETS',
                    rows: const [
                      ['Stumps hit', 'Bowled'],
                      ['Caught airborne', 'Caught — runs reverted'],
                    ],
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: Navigator.of(context).pop,
                      child: Text('GOT IT',
                          style: TextStyle(
                              color: kPalette.primary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      icon: const Icon(Icons.help_outline, color: Colors.white60, size: 16),
      label: const Text('How to Play',
          style: TextStyle(
              color: Colors.white60,
              fontSize: 13,
              letterSpacing: 1.2)),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final List<List<String>> rows;
  const _HelpSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: AppText.label.copyWith(color: kPalette.primary, fontSize: 11)),
        const SizedBox(height: 6),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(r[0],
                      style: AppText.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                Expanded(
                  child: Text(r[1],
                      style: AppText.body.copyWith(fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat {
  final String label;
  final String value;
  _Stat(this.label, this.value);
}

class _StatGrid extends StatelessWidget {
  final List<_Stat> stats;
  const _StatGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final s in stats)
          Container(
            width: 78,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0x33000000),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x33FFC93C)),
            ),
            child: Column(
              children: [
                Text(s.value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900)),
                Text(s.label, style: AppText.label),
              ],
            ),
          ),
      ],
    );
  }
}

class _RecentStrip extends StatelessWidget {
  final List<BallOutcome> history;
  const _RecentStrip({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    final last = history.length > 12
        ? history.sublist(history.length - 12)
        : history;
    return Column(
      children: [
        Text('LAST ${last.length} BALLS',
            style: AppText.label.copyWith(fontSize: 10)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (final o in last)
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _color(o),
                  shape: BoxShape.circle,
                  boxShadow: o == BallOutcome.four ||
                          o == BallOutcome.six ||
                          o == BallOutcome.wicket
                      ? [
                          BoxShadow(
                              blurRadius: 6,
                              color: _color(o).withValues(alpha: 0.6)),
                        ]
                      : null,
                ),
                child: Text(
                  o.label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Color _color(BallOutcome o) {
    switch (o) {
      case BallOutcome.dot:
        return const Color(0xFF1F2A37);
      case BallOutcome.one:
      case BallOutcome.two:
      case BallOutcome.three:
        return const Color(0xFF2E7D32);
      case BallOutcome.four:
        return kPalette.primary;
      case BallOutcome.six:
        return kPalette.accent;
      case BallOutcome.wicket:
        return kPalette.danger;
    }
  }
}

// ── Scorecard cards (game-over overlay) ────────────────────────────────────

/// Batting card — per-batsman runs / balls / 4s / 6s / SR. Lists all batsmen
/// who came in this innings: the retired (dismissed earlier) ones first,
/// then the live pair. Without the retired list the scorecard would only
/// ever show the surviving 2 — misleading after multiple wickets.
class _BattingCard extends StatelessWidget {
  final Batsman striker;
  final Batsman nonStriker;
  final List<RetiredBatsman> retired;
  const _BattingCard({
    required this.striker,
    required this.nonStriker,
    required this.retired,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xCC0E1A0F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: kPalette.primary.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('BATTING',
              style: AppText.label.copyWith(
                color: kPalette.primary,
                fontSize: 11,
              )),
          const SizedBox(height: 6),
          _ScorecardRow.header(const ['#', 'BATSMAN', 'R', 'B', '4', '6', 'SR']),
          for (final r in retired) _ScorecardRow.retired(r),
          _ScorecardRow.batsman(striker),
          _ScorecardRow.batsman(nonStriker),
        ],
      ),
    );
  }
}

/// Bowling card — per-archetype balls / runs / wickets / economy. Only
/// archetypes that actually bowled this innings are listed.
class _BowlingCard extends StatelessWidget {
  final Map<BowlerKind, BowlerStats> stats;
  const _BowlingCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final kind in BowlerKind.values) {
      final s = stats[kind]!;
      if (s.balls == 0) continue;
      rows.add(_ScorecardRow.bowler(kind, s));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xCC0E1A0F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: kPalette.primary.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('BOWLING',
              style: AppText.label.copyWith(
                color: kPalette.primary,
                fontSize: 11,
              )),
          const SizedBox(height: 6),
          _ScorecardRow.header(const ['', 'BOWLER', 'O', 'M', 'R', 'W', 'ECO']),
          ...rows,
        ],
      ),
    );
  }
}

/// One row of either card. Uses fixed flex so columns align across rows.
class _ScorecardRow extends StatelessWidget {
  final List<String> cells;
  final bool isHeader;
  final bool dim;

  const _ScorecardRow._({
    required this.cells,
    this.isHeader = false,
    this.dim = false,
  });

  factory _ScorecardRow.header(List<String> cells) =>
      _ScorecardRow._(cells: cells, isHeader: true);

  factory _ScorecardRow.batsman(Batsman b) {
    final dimRow = b.ballsFaced == 0;
    return _ScorecardRow._(
      cells: [
        '#${b.jerseyNumber}',
        b.isOut ? 'OUT' : (b.ballsFaced == 0 ? 'NOT IN' : 'NOT OUT'),
        '${b.runs}',
        '${b.ballsFaced}',
        '${b.fours}',
        '${b.sixes}',
        b.ballsFaced == 0 ? '–' : b.strikeRate.toStringAsFixed(0),
      ],
      dim: dimRow,
    );
  }

  /// Row for a dismissed batsman from the retired list. Always shows OUT.
  factory _ScorecardRow.retired(RetiredBatsman b) {
    return _ScorecardRow._(
      cells: [
        '#${b.jerseyNumber}',
        'OUT',
        '${b.runs}',
        '${b.ballsFaced}',
        '${b.fours}',
        '${b.sixes}',
        b.ballsFaced == 0 ? '–' : b.strikeRate.toStringAsFixed(0),
      ],
    );
  }

  factory _ScorecardRow.bowler(BowlerKind kind, BowlerStats s) =>
      _ScorecardRow._(cells: [
        '',
        kind.label,
        s.oversString,
        '${s.maidens}',
        '${s.runs}',
        '${s.wickets}',
        s.economy.toStringAsFixed(2),
      ]);

  @override
  Widget build(BuildContext context) {
    // Column flex: # / NAME / numeric x 5
    const flex = [10, 30, 12, 10, 8, 8, 14];
    final color = isHeader
        ? Colors.white60
        : (dim ? Colors.white38 : Colors.white);
    final weight = isHeader ? FontWeight.w700 : FontWeight.w500;
    final size = isHeader ? 10.5 : 12.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          for (int i = 0; i < cells.length; i++)
            Expanded(
              flex: flex[i],
              child: Text(
                cells[i],
                textAlign: i < 2 ? TextAlign.left : TextAlign.right,
                style: TextStyle(
                  color: color,
                  fontSize: size,
                  fontWeight: weight,
                  letterSpacing: isHeader ? 1.2 : 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
