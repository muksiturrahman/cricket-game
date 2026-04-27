import '../utils/constants.dart';

/// Per-ball outcome — drives the recent-balls strip in the HUD and the
/// boundary/dot tallies on the game-over screen.
enum BallOutcome { dot, one, two, three, four, six, wicket }

extension BallOutcomeLabel on BallOutcome {
  String get label => switch (this) {
        BallOutcome.dot => '•',
        BallOutcome.one => '1',
        BallOutcome.two => '2',
        BallOutcome.three => '3',
        BallOutcome.four => '4',
        BallOutcome.six => '6',
        BallOutcome.wicket => 'W',
      };

  static BallOutcome fromRunsThisBall(int runs, {required bool wicket}) {
    if (wicket) return BallOutcome.wicket;
    return switch (runs) {
      0 => BallOutcome.dot,
      1 => BallOutcome.one,
      2 => BallOutcome.two,
      3 => BallOutcome.three,
      4 => BallOutcome.four,
      6 => BallOutcome.six,
      _ => runs >= 5 ? BallOutcome.six : BallOutcome.dot,
    };
  }
}

class ScoreManager {
  int runs = 0;
  int wickets = 0;
  int ballsBowled = 0;
  int oversCompleted = 0;

  /// Per-ball outcomes, in order. Used by the HUD recent-balls strip and
  /// by the post-innings stats panel.
  final List<BallOutcome> ballHistory = [];

  /// Mutable so MatchSettings can override per innings.
  int maxOvers = kMaxOvers;
  int maxWickets = kMaxWickets;

  void reset() {
    runs = 0;
    wickets = 0;
    ballsBowled = 0;
    oversCompleted = 0;
    ballHistory.clear();
  }

  void addRuns(int value) => runs += value;

  void addWicket() => wickets++;

  void recordOutcome(BallOutcome outcome) => ballHistory.add(outcome);

  /// Increments ball count. Returns true when an over completes.
  bool nextBall() {
    ballsBowled++;
    if (ballsBowled % kBallsPerOver == 0) {
      oversCompleted++;
      return true;
    }
    return false;
  }

  bool get isInningsOver =>
      wickets >= maxWickets || oversCompleted >= maxOvers;

  int get currentBallInOver => ballsBowled % kBallsPerOver;

  String get overString => '$oversCompleted.$currentBallInOver';

  String get scoreString => '$runs/$wickets';

  /// Run rate per over, computed over completed balls. Returns 0 when no
  /// balls have been bowled yet.
  double get runRate {
    if (ballsBowled == 0) return 0;
    return runs * kBallsPerOver / ballsBowled;
  }

  int get fours => ballHistory.where((o) => o == BallOutcome.four).length;
  int get sixes => ballHistory.where((o) => o == BallOutcome.six).length;
  int get dots => ballHistory.where((o) => o == BallOutcome.dot).length;
}
