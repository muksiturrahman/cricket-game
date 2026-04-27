import 'dart:math';

import '../utils/constants.dart';

/// What kind of bowler is operating this over. Rotated by `AIManager` based
/// on the over count so the player faces a varied attack instead of a single
/// homogeneous bowler. Each kind owns an *absolute* speed band (in px/s) so
/// pacers feel genuinely fast, spinners genuinely slow, etc. The band is
/// then scaled by `difficultyMul` (Easy / Normal / Hard) at decide time.
enum BowlerKind {
  /// Express pace — fastest on the line, tight swing, brutal short balls.
  pacer(label: 'Pacer', loSpeed: 440, hiSpeed: 540, swingDeg: 6, deflection: 0),

  /// Medium pace — workhorse. Reliable, in the corridor, occasional surprise.
  medium(label: 'Medium', loSpeed: 320, hiSpeed: 410, swingDeg: 8, deflection: 0),

  /// Swing — lower pace but big lateral movement (high `swingDeg`).
  swing(label: 'Swing', loSpeed: 340, hiSpeed: 420, swingDeg: 22, deflection: 0),

  /// Off / leg spin — slowest, modest swing in air, **turns at the bounce**
  /// (lateral kick applied by `Ball.update` when this kind is bowling).
  spinner(
      label: 'Spinner',
      loSpeed: 220,
      hiSpeed: 310,
      swingDeg: 12,
      deflection: 90);

  /// Display label for HUD.
  final String label;

  /// Absolute speed band in px/s at Normal difficulty.
  final double loSpeed;
  final double hiSpeed;

  /// Half-range of the random swing angle (degrees) — applied at launch.
  final double swingDeg;

  /// Spinner-only: absolute lateral kick in px/s applied by `Ball` at the
  /// pitch bounce. 0 for non-spinners. Direction (left/right) is randomized
  /// per delivery so the batsman can't predict.
  final double deflection;

  const BowlerKind({
    required this.label,
    required this.loSpeed,
    required this.hiSpeed,
    required this.swingDeg,
    required this.deflection,
  });
}

/// Per-archetype bowling figures across an innings — drives the bowling
/// card on the GameOver overlay. Updated by `CricketGame._finishDelivery`.
class BowlerStats {
  /// Legitimate balls bowled by this kind (excludes wides, includes
  /// no-balls — same convention as scorecard "balls").
  int balls = 0;
  /// Total runs conceded — running runs + boundaries + wide / no-ball
  /// extras (matches the scorecard "runs" column).
  int runs = 0;
  int wickets = 0;
  /// Maiden overs — completed overs in which 0 runs were conceded.
  int maidens = 0;
  /// Runs in the current over — used to detect maidens at over-end.
  int currentOverRuns = 0;

  /// "O.B" string used by the scorecard. Each over is 6 balls.
  String get oversString {
    final overs = balls ~/ 6;
    final ballsInOver = balls % 6;
    return '$overs.$ballsInOver';
  }

  /// Economy rate — runs per over. Returns 0 when no balls bowled.
  double get economy => balls == 0 ? 0 : runs * 6.0 / balls;

  void reset() {
    balls = 0;
    runs = 0;
    wickets = 0;
    maidens = 0;
    currentOverRuns = 0;
  }
}

class BowlConfig {
  final double speed;
  final BowlLine line;
  final BowlLength length;
  final double swingAngle; // degrees
  final BowlerKind kind;
  /// If true, the ball is launched from a lateral offset that puts it out of
  /// bat reach — `CricketGame` awards +1 wide and re-bowls the delivery if
  /// the player doesn't connect.
  final bool isWide;
  /// If true, +1 is awarded automatically (illegal delivery). The ball still
  /// counts in this implementation (no free hit follow-up).
  final bool isNoBall;
  /// Extra horizontal offset (px) applied at launch — non-zero for wides.
  final double lateralOffsetPx;
  /// Lateral kick (px/s) applied when the ball pitches. Non-zero only for
  /// spinners. Sign is the turn direction (negative = leg-side, positive =
  /// off-side from a right-handed batsman's perspective).
  final double bounceDeflection;

  const BowlConfig({
    required this.speed,
    required this.line,
    required this.length,
    required this.swingAngle,
    required this.kind,
    this.isWide = false,
    this.isNoBall = false,
    this.lateralOffsetPx = 0,
    this.bounceDeflection = 0,
  });
}

class AIManager {
  final Random _rng = Random();

  /// Mutable so MatchSettings can override the speed range per innings.
  /// These now drive a *difficulty multiplier* applied to each kind's
  /// absolute band, instead of being the band itself.
  double minSpeed = kMinBallSpeed;
  double maxSpeed = kMaxBallSpeed;

  /// Pitch-type multiplier on the spinner's bounce deflection — > 1 for
  /// turning pitches, < 1 for green / fast pitches. 1.0 = flat surface.
  double pitchDeflectionMul = 1.0;

  /// Probability of each illegal delivery. Tuned for "happens but doesn't
  /// dominate" — about one wide every 12 balls, one no-ball every 25.
  static const double _wideProb = 0.08;
  static const double _noBallProb = 0.04;

  /// Cycle bowler archetypes through the innings — switches every over.
  /// Pacer → Medium → Swing → Spinner → repeat. Four-pronged attack so the
  /// player faces a real variety arc.
  BowlerKind _kindForOver(int oversCompleted) {
    const cycle = [
      BowlerKind.pacer,
      BowlerKind.medium,
      BowlerKind.swing,
      BowlerKind.spinner,
    ];
    return cycle[oversCompleted % cycle.length];
  }

  /// Public lookup — used by HUD to label the current bowler.
  BowlerKind kindForOver(int oversCompleted) => _kindForOver(oversCompleted);

  /// Difficulty multiplier on absolute speed bands. Derived from the
  /// `MatchSettings` min/max relative to the Normal-difficulty defaults.
  double get _difficultyMul {
    return (minSpeed + maxSpeed) / (kMinBallSpeed + kMaxBallSpeed);
  }

  BowlConfig decideBowl(int ballsBowled) {
    final overs = ballsBowled ~/ kBallsPerOver;
    final kind = _kindForOver(overs);

    final isNoBall = _rng.nextDouble() < _noBallProb;
    // Don't stack a wide on top of a no-ball — too punishing.
    final isWide = !isNoBall && _rng.nextDouble() < _wideProb;

    var swing = (_rng.nextDouble() * 2 - 1) * kind.swingDeg;
    var lateral = 0.0;
    if (isWide) {
      // Push the ball ~55 px off centre — wide of the bat's reach. Direction
      // randomized so wides go down both sides.
      final side = _rng.nextBool() ? 1.0 : -1.0;
      lateral = 55.0 * side;
      swing = (swing.abs() + 6) * side; // bias swing to the same side
    }

    // Spinner-only: pick a turn direction at delivery time. Pitch type
    // scales the magnitude — turning pitches grip more, green pitches less.
    var deflection = 0.0;
    if (kind == BowlerKind.spinner) {
      final side = _rng.nextBool() ? 1.0 : -1.0;
      // Vary the amount so each ball turns differently.
      final amt = kind.deflection * (0.6 + _rng.nextDouble() * 0.7);
      deflection = amt * side * pitchDeflectionMul;
    }

    return BowlConfig(
      speed: _pickSpeed(ballsBowled, kind),
      line: isWide ? BowlLine.wide : _pickLine(),
      length: _pickLength(ballsBowled, kind),
      swingAngle: swing,
      kind: kind,
      isWide: isWide,
      isNoBall: isNoBall,
      lateralOffsetPx: lateral,
      bounceDeflection: deflection,
    );
  }

  double _pickSpeed(int balls, BowlerKind kind) {
    // Innings-progression bias — early balls slightly easier, later harder.
    final progress = balls >= kLateInningsThreshold
        ? 1.0
        : balls >= kMidInningsThreshold
            ? 0.85
            : 0.70;
    final lo = kind.loSpeed;
    final hi = kind.hiSpeed;
    final raw = lo + _rng.nextDouble() * (hi - lo) * progress;
    return raw * _difficultyMul;
  }

  BowlLine _pickLine() {
    final r = _rng.nextDouble();
    if (r < 0.55) return BowlLine.onStumps;
    if (r < 0.92) return BowlLine.offStump;
    return BowlLine.wide;
  }

  /// Length distribution per archetype — pacers love short balls, spinners
  /// stick to good length / full toss territory.
  BowlLength _pickLength(int balls, BowlerKind kind) {
    final r = _rng.nextDouble();
    switch (kind) {
      case BowlerKind.pacer:
        // 35% short, 30% good, 20% yorker, 15% fullToss.
        if (r < 0.35) return BowlLength.shortPitch;
        if (r < 0.65) return BowlLength.goodLength;
        if (r < 0.85) return BowlLength.yorker;
        return BowlLength.fullToss;
      case BowlerKind.medium:
        // 50% good, 25% fullToss, 15% yorker, 10% short.
        if (r < 0.50) return BowlLength.goodLength;
        if (r < 0.75) return BowlLength.fullToss;
        if (r < 0.90) return BowlLength.yorker;
        return BowlLength.shortPitch;
      case BowlerKind.swing:
        // Pitch it up so the swing has a chance to bite — mostly fuller.
        if (r < 0.40) return BowlLength.goodLength;
        if (r < 0.80) return BowlLength.fullToss;
        if (r < 0.92) return BowlLength.yorker;
        return BowlLength.shortPitch;
      case BowlerKind.spinner:
        // No bouncers; mostly fuller lengths so spin can grip.
        if (r < 0.55) return BowlLength.goodLength;
        if (r < 0.90) return BowlLength.fullToss;
        return BowlLength.yorker;
    }
  }
}
