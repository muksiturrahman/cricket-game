import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/score_manager.dart';
import '../state/match_settings.dart';
import '../utils/constants.dart';

/// Frozen snapshot of a match in progress. Saved between deliveries so a
/// crash / app close can be resumed cleanly. Only the *clean* state
/// between deliveries is captured — never mid-flight ball positions etc.
class SavedMatch {
  final MatchFormat format;
  final Difficulty difficulty;
  final bool chase;
  /// Pitch preset chosen at start. Defaults to flat for legacy snapshots.
  final PitchType pitchType;
  /// Captain's field placement chosen at start. Defaults to defensive.
  final FieldPreset fieldPreset;
  /// Day / night setting at start. Defaults to day for legacy snapshots.
  final DayNight timeOfDay;

  /// Live scoreboard at save time.
  final int runs;
  final int wickets;
  final int ballsBowled;
  final int oversCompleted;
  final List<BallOutcome> history;

  final Innings innings;

  /// First-innings totals — only set when `innings == aiBats`. The
  /// fours / sixes are needed at `_finalizeMatch` time to recover the
  /// player's batting stats; without them a mid-chase resume would log
  /// the AI's score as the player's career stats.
  final int? firstInningsRuns;
  final int? firstInningsWickets;
  final int? firstInningsOversCompleted;
  final int? firstInningsCurrentBallInOver;
  final int? firstInningsFours;
  final int? firstInningsSixes;
  final int? target;

  const SavedMatch({
    required this.format,
    required this.difficulty,
    required this.chase,
    this.pitchType = PitchType.flat,
    this.fieldPreset = FieldPreset.defensive,
    this.timeOfDay = DayNight.day,
    required this.runs,
    required this.wickets,
    required this.ballsBowled,
    required this.oversCompleted,
    required this.history,
    required this.innings,
    this.firstInningsRuns,
    this.firstInningsWickets,
    this.firstInningsOversCompleted,
    this.firstInningsCurrentBallInOver,
    this.firstInningsFours,
    this.firstInningsSixes,
    this.target,
  });

  Map<String, dynamic> toJson() => {
        'format': format.name,
        'difficulty': difficulty.name,
        'chase': chase,
        'pitchType': pitchType.name,
        'fieldPreset': fieldPreset.name,
        'timeOfDay': timeOfDay.name,
        'runs': runs,
        'wickets': wickets,
        'ballsBowled': ballsBowled,
        'oversCompleted': oversCompleted,
        'history': history.map((o) => o.name).toList(),
        'innings': innings.name,
        if (firstInningsRuns != null) 'firstInningsRuns': firstInningsRuns,
        if (firstInningsWickets != null)
          'firstInningsWickets': firstInningsWickets,
        if (firstInningsOversCompleted != null)
          'firstInningsOversCompleted': firstInningsOversCompleted,
        if (firstInningsCurrentBallInOver != null)
          'firstInningsCurrentBallInOver': firstInningsCurrentBallInOver,
        if (firstInningsFours != null) 'firstInningsFours': firstInningsFours,
        if (firstInningsSixes != null) 'firstInningsSixes': firstInningsSixes,
        if (target != null) 'target': target,
      };

  static SavedMatch? fromJson(Map<String, dynamic> j) {
    try {
      return SavedMatch(
        format: MatchFormat.values.byName(j['format'] as String),
        difficulty: Difficulty.values.byName(j['difficulty'] as String),
        chase: (j['chase'] as bool?) ?? false,
        pitchType: PitchType.values
            .firstWhere(
              (p) => p.name == (j['pitchType'] as String?),
              orElse: () => PitchType.flat,
            ),
        fieldPreset: FieldPreset.values
            .firstWhere(
              (f) => f.name == (j['fieldPreset'] as String?),
              orElse: () => FieldPreset.defensive,
            ),
        timeOfDay: DayNight.values
            .firstWhere(
              (t) => t.name == (j['timeOfDay'] as String?),
              orElse: () => DayNight.day,
            ),
        runs: (j['runs'] as int?) ?? 0,
        wickets: (j['wickets'] as int?) ?? 0,
        ballsBowled: (j['ballsBowled'] as int?) ?? 0,
        oversCompleted: (j['oversCompleted'] as int?) ?? 0,
        history: (j['history'] as List<dynamic>? ?? const [])
            .map((s) => BallOutcome.values.byName(s as String))
            .toList(),
        innings: Innings.values.byName(j['innings'] as String? ?? 'playerBats'),
        firstInningsRuns: j['firstInningsRuns'] as int?,
        firstInningsWickets: j['firstInningsWickets'] as int?,
        firstInningsOversCompleted: j['firstInningsOversCompleted'] as int?,
        firstInningsCurrentBallInOver:
            j['firstInningsCurrentBallInOver'] as int?,
        firstInningsFours: j['firstInningsFours'] as int?,
        firstInningsSixes: j['firstInningsSixes'] as int?,
        target: j['target'] as int?,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('SavedMatch.fromJson failed: $e');
      return null;
    }
  }

  String get summary {
    final ov =
        '$oversCompleted.${ballsBowled % kBallsPerOver}/${format.overs}';
    final inningsLabel = innings == Innings.aiBats ? 'AI batting' : 'Batting';
    return '$inningsLabel · $runs/$wickets · $ov ov · ${difficulty.label}';
  }
}

/// Persists the in-progress match to `shared_preferences`. Called by
/// `CricketGame` between deliveries; cleared on `_finalizeMatch` /
/// `restartGame` / `quitToMenu`.
class SaveService extends ChangeNotifier {
  SaveService._();
  static final SaveService instance = SaveService._();

  static const _kKey = 'save.match';

  SavedMatch? _cache;
  SavedMatch? get current => _cache;
  bool get hasSave => _cache != null;

  bool _ready = false;
  bool get ready => _ready;

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _cache = SavedMatch.fromJson(decoded);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SaveService.init failed: $e');
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> save(SavedMatch match) async {
    _cache = match;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kKey, jsonEncode(match.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('SaveService.save failed: $e');
    }
  }

  Future<void> clear() async {
    if (_cache == null) return;
    _cache = null;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kKey);
    } catch (e) {
      if (kDebugMode) debugPrint('SaveService.clear failed: $e');
    }
  }
}
