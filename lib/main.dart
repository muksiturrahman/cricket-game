import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'game/cricket_game.dart';
import 'screens/main_menu.dart';
import 'screens/splash_overlay.dart';
import 'screens/tutorial_overlay.dart';
import 'services/save_service.dart';
import 'services/sprite_service.dart';
import 'services/stats_service.dart';
import 'state/game_state_notifier.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Kick off persisted-stats load in the background — first paint sees the
  // empty cache, then `notifyListeners` rebuilds anything that's watching.
  StatsService.instance.init();
  SaveService.instance.init();
  SpriteService.instance.init();
  // Lock to landscape on mobile only. On desktop the OS controls window
  // orientation; calling this can cause the renderer to apply a rotation
  // transform when the window is portrait-shaped.
  final isMobile = defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
  if (isMobile) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]).then((_) => runApp(const CricketApp()));
  } else {
    runApp(const CricketApp());
  }
}

class CricketApp extends StatefulWidget {
  const CricketApp({super.key});

  @override
  State<CricketApp> createState() => _CricketAppState();
}

class _CricketAppState extends State<CricketApp> {
  late final CricketGame _game;

  @override
  void initState() {
    super.initState();
    _game = CricketGame();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _game.stateNotifier),
        ChangeNotifierProvider.value(value: StatsService.instance),
        ChangeNotifierProvider.value(value: SaveService.instance),
      ],
      child: MaterialApp(
        title: 'Cricket Game',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Stack(
            children: [
              GameWidget<CricketGame>(
                game: _game,
                overlayBuilderMap: {
                  'Splash': (ctx, game) => SplashOverlay(game: game),
                  'Tutorial': (ctx, game) => TutorialOverlay(game: game),
                  'MainMenu': (ctx, game) => MainMenuOverlay(game: game),
                  'Pause': (ctx, game) => PauseOverlay(game: game),
                  'GameOver': (ctx, game) => GameOverOverlay(game: game),
                },
                initialActiveOverlays: const ['Splash'],
              ),
              _PauseButton(game: _game),
              _PowerButton(game: _game),
              _RunButton(game: _game),
            ],
          ),
        ),
      ),
    );
  }
}

/// On-screen RUN button — bottom-right, only visible while the running
/// window is open (i.e. between BatContact and end-of-delivery). Tapping
/// calls `game.takeRun()`. Mobile users have no other way to take 1s/2s
/// (the keyboard R / ⏎ binding works on desktop but isn't reachable on
/// touch). Watches `CricketGame.runningActive` via `ValueListenableBuilder`.
class _RunButton extends StatelessWidget {
  final CricketGame game;
  const _RunButton({required this.game});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<GameStateNotifier>();
    final phase = notifier.phase;
    final innings = notifier.innings;
    if (phase != GamePhase.playing) return const SizedBox.shrink();
    // Hide during the AI's chase — only the player needs the RUN button,
    // and showing it during the AI's innings invites confused taps that
    // would have piled runs on the AI's score.
    if (innings != Innings.playerBats) return const SizedBox.shrink();
    return Positioned(
      right: 18,
      bottom: 26,
      child: ValueListenableBuilder<bool>(
        valueListenable: game.runningActive,
        builder: (context, on, _) {
          return AnimatedOpacity(
            opacity: on ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !on,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: game.takeRun,
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFC93C), Color(0xFFE5A91A)],
                      ),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          blurRadius: 18,
                          color: kPalette.primary.withValues(alpha: 0.7),
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_run,
                            color: Color(0xFF1A1100), size: 28),
                        Text(
                          'RUN',
                          style: TextStyle(
                            color: Color(0xFF1A1100),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Power-toggle pill — shows whether the next shot will be lofted (POWER ON,
/// gold) or grounded (POWER OFF, slate). Tapping flips the flag. Only visible
/// during active play, sat on the right edge below the pause button.
class _PowerButton extends StatelessWidget {
  final CricketGame game;
  const _PowerButton({required this.game});

  @override
  Widget build(BuildContext context) {
    final phase = context.watch<GameStateNotifier>().phase;
    if (phase != GamePhase.playing) return const SizedBox.shrink();
    return Positioned(
      top: 64,
      right: 14,
      child: ValueListenableBuilder<bool>(
        valueListenable: game.powerOn,
        builder: (context, on, _) {
          final accent = on ? kPalette.primary : Colors.white60;
          final fillColors = on
              ? [const Color(0xCC2A2002), const Color(0xCC4D3A00)]
              : [const Color(0xCC07140A), const Color(0xCC183024)];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: game.togglePower,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: fillColors,
                  ),
                  border: Border.all(color: accent, width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: on ? 14 : 6,
                      color: on
                          ? kPalette.primary.withValues(alpha: 0.6)
                          : const Color(0x77000000),
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      on ? Icons.bolt : Icons.bolt_outlined,
                      color: accent,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      on ? 'POWER' : 'GROUND',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Always-on top-right pause toggle. Only visible during active play so it
/// doesn't intercept taps on the menu/pause/game-over overlays.
class _PauseButton extends StatelessWidget {
  final CricketGame game;
  const _PauseButton({required this.game});

  @override
  Widget build(BuildContext context) {
    final phase = context.watch<GameStateNotifier>().phase;
    if (phase != GamePhase.playing) return const SizedBox.shrink();
    return Positioned(
      top: 12,
      right: 14,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: game.togglePause,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xCC07140A),
                  const Color(0xCC183024),
                ],
              ),
              border: Border.all(
                  color: kPalette.primary.withValues(alpha: 0.6),
                  width: 1.4),
              boxShadow: const [
                BoxShadow(
                    blurRadius: 8,
                    color: Color(0x99000000),
                    offset: Offset(0, 3)),
              ],
            ),
            child: Icon(Icons.pause, color: kPalette.primary, size: 22),
          ),
        ),
      ),
    );
  }
}
