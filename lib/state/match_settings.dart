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

/// Captain's pre-innings field placement. Positions are normalized
/// `(x, y)` ratios of screen size, applied to the matching `Fielder`
/// instances on innings start. Each preset keeps the keeper at
/// `(kKeeperXRatio, kKeeperYRatio)` regardless.
enum FieldPreset {
  /// Default — fielders spread across the rope. Hard to score boundaries,
  /// easy to milk singles.
  defensive(
    label: 'Defensive',
    blurb: 'Spread the field — hard to score 4s & 6s, easy singles',
    placements: {
      FieldPosition.cover: (0.20, 0.50),
      FieldPosition.midOff: (0.78, 0.55),
      FieldPosition.midOn: (0.30, 0.55),
      FieldPosition.squareLeg: (0.85, 0.45),
      FieldPosition.longOff: (0.78, 0.25),
      FieldPosition.longOn: (0.22, 0.25),
      FieldPosition.midwicket: (0.15, 0.35),
    },
  ),
  /// Attacking — catchers in close, fewer at the boundary. Higher chance
  /// of edges/catches but boundaries flow easily.
  attacking(
    label: 'Attacking',
    blurb: 'Catchers in close — wicket-friendly, leaks 4s',
    placements: {
      FieldPosition.cover: (0.30, 0.55),
      FieldPosition.midOff: (0.65, 0.60),
      FieldPosition.midOn: (0.35, 0.60),
      FieldPosition.squareLeg: (0.72, 0.50),
      FieldPosition.longOff: (0.68, 0.42),
      FieldPosition.longOn: (0.32, 0.42),
      FieldPosition.midwicket: (0.25, 0.55),
    },
  ),
  /// Spin field — silly mid-off / short leg / midwicket up. Minimal cover
  /// at the boundary; designed to catch sweeps and inside edges.
  spinField(
    label: 'Spin',
    blurb: 'Bat-pad catchers, short leg, ring tight on a turner',
    placements: {
      FieldPosition.cover: (0.32, 0.55),
      FieldPosition.midOff: (0.62, 0.62),
      FieldPosition.midOn: (0.38, 0.62),
      FieldPosition.squareLeg: (0.30, 0.66),
      FieldPosition.longOff: (0.65, 0.42),
      FieldPosition.longOn: (0.35, 0.42),
      FieldPosition.midwicket: (0.32, 0.66),
    },
  );

  final String label;
  final String blurb;
  final Map<FieldPosition, (double, double)> placements;
  const FieldPreset({
    required this.label,
    required this.blurb,
    required this.placements,
  });
}

/// Pitch / surface preset — affects ball speed, bounce height, and the
/// spinner's bounce deflection. Pure scaling on existing physics; no new
/// systems. Picked from the main menu before each match.
enum PitchType {
  /// Balanced surface — all multipliers 1.0. Default.
  flat(
    label: 'Flat',
    blurb: 'Balanced surface — fair to bat & bowl',
    speedMul: 1.0,
    bounceMul: 1.0,
    deflectionMul: 1.0,
  ),
  /// Hard / fast pitch — pace bowlers thrive: faster ball, higher bounce.
  /// Spin grips less.
  green(
    label: 'Green',
    blurb: 'Hard, lively — pacers thrive, ball bounces',
    speedMul: 1.12,
    bounceMul: 1.20,
    deflectionMul: 0.70,
  ),
  /// Dry / dusty pitch — spinners thrive: lower bounce, more turn off the
  /// surface. Slightly slower deliveries overall.
  turning(
    label: 'Turning',
    blurb: 'Dry & dusty — spinners turn it square',
    speedMul: 0.92,
    bounceMul: 0.78,
    deflectionMul: 1.55,
  );

  final String label;
  final String blurb;
  /// Multiplies AIManager's per-kind speed bands.
  final double speedMul;
  /// Multiplies the first-bounce restitution (length-dependent value).
  final double bounceMul;
  /// Multiplies the spinner's bounce deflection.
  final double deflectionMul;

  const PitchType({
    required this.label,
    required this.blurb,
    required this.speedMul,
    required this.bounceMul,
    required this.deflectionMul,
  });
}

class MatchSettings {
  final MatchFormat format;
  final Difficulty difficulty;

  /// Two-innings chase. When true, after the player's innings ends the AI
  /// bats second with target = playerRuns + 1. Default false (single innings).
  final bool chase;

  /// Pitch preset — defaults to flat (no scaling). Applied by `CricketGame`
  /// at innings start.
  final PitchType pitchType;

  /// Captain's field placement preset. Defaults to a spread defensive field.
  final FieldPreset fieldPreset;

  const MatchSettings({
    this.format = MatchFormat.t5,
    this.difficulty = Difficulty.normal,
    this.chase = false,
    this.pitchType = PitchType.flat,
    this.fieldPreset = FieldPreset.defensive,
  });

  int get maxOvers => format.overs;
  int get maxWickets => kMaxWickets;
  double get swingWindowSec => difficulty.swingWindowSec;
  double get runUpSec => difficulty.runUpSec;
  double get minBallSpeed => difficulty.minSpeed * pitchType.speedMul;
  double get maxBallSpeed => difficulty.maxSpeed * pitchType.speedMul;
  double get fielderSpeedMul => difficulty.fielderSpeedMul;
  double get fielderMaxChase => difficulty.fielderMaxChase;
  double get runOutMultiplier => difficulty.runOutMultiplier;
  double get pitchBounceMul => pitchType.bounceMul;
  double get pitchDeflectionMul => pitchType.deflectionMul;

  MatchSettings copyWith({
    MatchFormat? format,
    Difficulty? difficulty,
    bool? chase,
    PitchType? pitchType,
    FieldPreset? fieldPreset,
  }) =>
      MatchSettings(
        format: format ?? this.format,
        difficulty: difficulty ?? this.difficulty,
        chase: chase ?? this.chase,
        pitchType: pitchType ?? this.pitchType,
        fieldPreset: fieldPreset ?? this.fieldPreset,
      );
}
