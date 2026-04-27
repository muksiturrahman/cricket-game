import '../utils/constants.dart';

enum MatchFormat {
  t5(label: 'T5', overs: 5),
  t10(label: 'T10', overs: 10),
  t20(label: 'T20', overs: 20);

  final String label;
  final int overs;
  const MatchFormat({required this.label, required this.overs});
}

/// Per-difficulty parameters. Bowling speed + swing window come from here,
/// plus the new fielding multipliers added in the Tier 2 pass.
enum Difficulty {
  easy(
    label: 'Easy',
    swingWindowSec: 0.45,
    runUpSec: 2.0,
    minSpeed: 200.0,
    maxSpeed: 380.0,
    fielderSpeedMul: 0.80,
    fielderMaxChase: 55.0,
    runOutMultiplier: 0.55,
  ),
  normal(
    label: 'Normal',
    swingWindowSec: 0.30,
    runUpSec: 1.5,
    minSpeed: kMinBallSpeed,
    maxSpeed: kMaxBallSpeed,
    fielderSpeedMul: 1.0,
    fielderMaxChase: 70.0,
    runOutMultiplier: 1.0,
  ),
  hard(
    label: 'Hard',
    swingWindowSec: 0.20,
    runUpSec: 1.1,
    minSpeed: 360.0,
    maxSpeed: 640.0,
    fielderSpeedMul: 1.20,
    fielderMaxChase: 95.0,
    runOutMultiplier: 1.35,
  );

  final String label;
  final double swingWindowSec;
  final double runUpSec;
  final double minSpeed;
  final double maxSpeed;
  /// Multiplier on `kFielderSpeed` (230 px/s).
  final double fielderSpeedMul;
  /// Replaces `kFielderMaxChaseDistance` (px) — how far a fielder commits.
  final double fielderMaxChase;
  /// Multiplier on the base run-out throw success probability.
  final double runOutMultiplier;
  const Difficulty({
    required this.label,
    required this.swingWindowSec,
    required this.runUpSec,
    required this.minSpeed,
    required this.maxSpeed,
    required this.fielderSpeedMul,
    required this.fielderMaxChase,
    required this.runOutMultiplier,
  });
}

class MatchSettings {
  final MatchFormat format;
  final Difficulty difficulty;

  /// Two-innings chase. When true, after the player's innings ends the AI
  /// bats second with target = playerRuns + 1. Default false (single innings).
  final bool chase;

  const MatchSettings({
    this.format = MatchFormat.t5,
    this.difficulty = Difficulty.normal,
    this.chase = false,
  });

  int get maxOvers => format.overs;
  int get maxWickets => kMaxWickets;
  double get swingWindowSec => difficulty.swingWindowSec;
  double get runUpSec => difficulty.runUpSec;
  double get minBallSpeed => difficulty.minSpeed;
  double get maxBallSpeed => difficulty.maxSpeed;
  double get fielderSpeedMul => difficulty.fielderSpeedMul;
  double get fielderMaxChase => difficulty.fielderMaxChase;
  double get runOutMultiplier => difficulty.runOutMultiplier;

  MatchSettings copyWith({
    MatchFormat? format,
    Difficulty? difficulty,
    bool? chase,
  }) =>
      MatchSettings(
        format: format ?? this.format,
        difficulty: difficulty ?? this.difficulty,
        chase: chase ?? this.chase,
      );
}
