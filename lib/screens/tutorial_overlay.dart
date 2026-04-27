import 'package:flutter/material.dart';

import '../game/cricket_game.dart';
import '../services/stats_service.dart';
import '../utils/theme.dart';
import 'main_menu.dart' show StadiumBackdrop;

/// First-run walkthrough — 4 cards explaining swipe → run → power → wickets.
/// Shown once on cold start (gated by `StatsService.tutorialSeen`). After
/// dismissal, control hands off to `MainMenuOverlay`.
class TutorialOverlay extends StatefulWidget {
  final CricketGame game;
  const TutorialOverlay({super.key, required this.game});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  int _step = 0;

  static const _steps = <_TutorialStep>[
    _TutorialStep(
      icon: Icons.gesture,
      title: 'PLAY ANY SHOT',
      body:
          'Swipe in any direction on the pitch and the ball goes that way. '
          'Swipe length controls force — longer swipes hit harder.',
    ),
    _TutorialStep(
      icon: Icons.bolt,
      title: 'POWER ON / OFF',
      body:
          'Tap the POWER pill (top-right) to toggle lofted shots. POWER ON '
          'lofts the ball into the air — high reward but catchable. POWER '
          'OFF stays grounded — usually a single or four, never a six.',
    ),
    _TutorialStep(
      icon: Icons.directions_run,
      title: 'TAKE RUNS',
      body:
          'After contact, tap the gold RUN button (or press R / ⏎ on '
          'keyboard) to take a single. Tap again for two, and again for '
          'three — but mind the throw at the stumps.',
    ),
    _TutorialStep(
      icon: Icons.shield,
      title: 'WATCH THE WICKETS',
      body:
          'Get bowled, caught (lofted shot in the air), or run out (mid-'
          'sprint when a fielder hits the stumps) — and your innings is '
          'one closer to over.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final isLast = _step == _steps.length - 1;
    return StadiumBackdrop(
      darken: 0.65,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: AppPanels.card(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppGradients.goldButton(),
                        boxShadow: [
                          BoxShadow(
                            color: kPalette.primary.withValues(alpha: 0.5),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        step.icon,
                        color: const Color(0xFF1A1100),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      step.title,
                      style: AppText.h1.copyWith(letterSpacing: 2),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      step.body,
                      style: AppText.body.copyWith(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _steps.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _step ? 22 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _step
                                  ? kPalette.primary
                                  : const Color(0x55FFFFFF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: _dismiss,
                          child: Text(
                            isLast ? '' : 'SKIP',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap:
                              isLast ? _dismiss : () => setState(() => _step++),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: AppGradients.goldButton(),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                    blurRadius: 10, color: Color(0x66000000))
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isLast ? 'LET\'S PLAY' : 'NEXT',
                                  style: const TextStyle(
                                    color: Color(0xFF1A1100),
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.arrow_forward,
                                  color: Color(0xFF1A1100),
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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

  void _dismiss() {
    StatsService.instance.markTutorialSeen();
    widget.game.dismissTutorial();
  }
}

class _TutorialStep {
  final IconData icon;
  final String title;
  final String body;
  const _TutorialStep({
    required this.icon,
    required this.title,
    required this.body,
  });
}
