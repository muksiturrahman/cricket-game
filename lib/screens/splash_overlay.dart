import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/cricket_game.dart';
import '../services/stats_service.dart';
import '../utils/theme.dart';
import 'main_menu.dart';

/// Brief animated intro shown on cold start, then auto-transitions to the
/// main menu. Tap anywhere to skip. Only registered as the initial overlay,
/// so subsequent menu returns (via `quitToMenu`) skip the splash entirely.
class SplashOverlay extends StatefulWidget {
  final CricketGame game;
  const SplashOverlay({super.key, required this.game});

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay>
    with TickerProviderStateMixin {
  static const Duration _entry = Duration(milliseconds: 800);
  static const Duration _hold = Duration(milliseconds: 700);

  late final AnimationController _entryCtrl;
  late final AnimationController _spinCtrl;
  bool _transitioned = false;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(vsync: this, duration: _entry)..forward();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    Future.delayed(_entry + _hold, _goToMenu);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  void _goToMenu() {
    if (_transitioned || !mounted) return;
    _transitioned = true;
    widget.game.overlays.remove('Splash');
    // First-run players see the 4-step tutorial before the menu. Subsequent
    // launches skip straight to the menu (gate stored via `StatsService`).
    if (!StatsService.instance.current.tutorialSeen) {
      widget.game.overlays.add('Tutorial');
    } else {
      widget.game.overlays.add('MainMenu');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _goToMenu,
      behavior: HitTestBehavior.opaque,
      child: StadiumBackdrop(
        child: Center(
          child: AnimatedBuilder(
            animation: _entryCtrl,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_entryCtrl.value);
              return Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: 0.85 + 0.15 * t,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _spinCtrl,
                        builder: (_, _) => CricketEmblem(
                          rotation: _spinCtrl.value * math.pi * 2,
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text('CRICKET', style: AppText.hero),
                      const SizedBox(height: 6),
                      Text(
                        'STADIUM PRO',
                        style: AppText.label.copyWith(
                          color: kPalette.primary,
                          fontSize: 13,
                          letterSpacing: 6,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Opacity(
                        opacity: t * 0.6,
                        child: const Text(
                          'TAP TO SKIP',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                            letterSpacing: 3,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
