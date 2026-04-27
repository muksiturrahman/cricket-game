import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_game/game/score_manager.dart';
import 'package:cricket_game/utils/constants.dart';

void main() {
  group('ScoreManager', () {
    late ScoreManager sm;

    setUp(() => sm = ScoreManager());

    test('starts at zero', () {
      expect(sm.runs, 0);
      expect(sm.wickets, 0);
      expect(sm.ballsBowled, 0);
    });

    test('addRuns accumulates', () {
      sm.addRuns(4);
      sm.addRuns(6);
      expect(sm.runs, 10);
    });

    test('addWicket increments', () {
      sm.addWicket();
      expect(sm.wickets, 1);
    });

    test('nextBall increments and completes over at 6', () {
      for (int i = 0; i < 5; i++) {
        expect(sm.nextBall(), false);
      }
      expect(sm.nextBall(), true); // 6th ball → over complete
      expect(sm.oversCompleted, 1);
    });

    test('isInningsOver on max wickets', () {
      for (int i = 0; i < kMaxWickets; i++) {
        sm.addWicket();
      }
      expect(sm.isInningsOver, true);
    });

    test('isInningsOver on max overs', () {
      for (int i = 0; i < kMaxOvers * kBallsPerOver; i++) {
        sm.nextBall();
      }
      expect(sm.isInningsOver, true);
    });

    test('reset clears all fields', () {
      sm.addRuns(50);
      sm.addWicket();
      sm.nextBall();
      sm.reset();
      expect(sm.runs, 0);
      expect(sm.wickets, 0);
      expect(sm.ballsBowled, 0);
    });
  });
}
