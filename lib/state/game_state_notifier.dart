import 'package:flutter/foundation.dart';

import '../utils/constants.dart';

class ScoreSnapshot {
  final int runs;
  final int wickets;
  final int oversCompleted;
  final int currentBallInOver;

  const ScoreSnapshot({
    required this.runs,
    required this.wickets,
    required this.oversCompleted,
    required this.currentBallInOver,
  });

  static const empty = ScoreSnapshot(
    runs: 0,
    wickets: 0,
    oversCompleted: 0,
    currentBallInOver: 0,
  );

  String get scoreString => '$runs/$wickets';
  String get overString => '$oversCompleted.$currentBallInOver';
}

class GameStateNotifier extends ChangeNotifier {
  GamePhase _phase = GamePhase.mainMenu;
  ScoreSnapshot _finalScore = ScoreSnapshot.empty;
  Innings _innings = Innings.playerBats;
  int? _target;
  ScoreSnapshot? _firstInningsScore;

  GamePhase get phase => _phase;
  ScoreSnapshot get finalScore => _finalScore;
  Innings get innings => _innings;
  int? get target => _target;
  ScoreSnapshot? get firstInningsScore => _firstInningsScore;

  void setPhase(GamePhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    notifyListeners();
  }

  void setFinalScore(ScoreSnapshot snapshot) {
    _finalScore = snapshot;
    notifyListeners();
  }

  /// Update which innings is in progress + the AI target (only set during
  /// `Innings.aiBats`).
  void setInnings(Innings innings, {int? target}) {
    if (_innings == innings && _target == target) return;
    _innings = innings;
    _target = target;
    notifyListeners();
  }

  void setFirstInningsScore(ScoreSnapshot? snapshot) {
    _firstInningsScore = snapshot;
    notifyListeners();
  }
}
