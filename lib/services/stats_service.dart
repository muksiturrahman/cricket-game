import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Aggregate stats persisted across runs.
class GameStats {
  final int matchesPlayed;
  final int matchesWon;
  final int bestScore;
  final int totalRuns;
  final int totalFours;
  final int totalSixes;
  final int totalWickets;
  final bool tutorialSeen;

  const GameStats({
    required this.matchesPlayed,
    required this.matchesWon,
    required this.bestScore,
    required this.totalRuns,
    required this.totalFours,
    required this.totalSixes,
    required this.totalWickets,
    required this.tutorialSeen,
  });

  static const empty = GameStats(
    matchesPlayed: 0,
    matchesWon: 0,
    bestScore: 0,
    totalRuns: 0,
    totalFours: 0,
    totalSixes: 0,
    totalWickets: 0,
    tutorialSeen: false,
  );

  GameStats copyWith({
    int? matchesPlayed,
    int? matchesWon,
    int? bestScore,
    int? totalRuns,
    int? totalFours,
    int? totalSixes,
    int? totalWickets,
    bool? tutorialSeen,
  }) =>
      GameStats(
        matchesPlayed: matchesPlayed ?? this.matchesPlayed,
        matchesWon: matchesWon ?? this.matchesWon,
        bestScore: bestScore ?? this.bestScore,
        totalRuns: totalRuns ?? this.totalRuns,
        totalFours: totalFours ?? this.totalFours,
        totalSixes: totalSixes ?? this.totalSixes,
        totalWickets: totalWickets ?? this.totalWickets,
        tutorialSeen: tutorialSeen ?? this.tutorialSeen,
      );
}

/// Persisted aggregate stats — best score, total runs, matches won, etc.
/// Backed by `shared_preferences`. Reads are synchronous-after-init via the
/// in-memory cache; writes fire-and-forget but await the SharedPreferences
/// instance.
class StatsService extends ChangeNotifier {
  StatsService._();
  static final StatsService instance = StatsService._();

  static const _kMatchesPlayed = 'stats.matchesPlayed';
  static const _kMatchesWon = 'stats.matchesWon';
  static const _kBestScore = 'stats.bestScore';
  static const _kTotalRuns = 'stats.totalRuns';
  static const _kTotalFours = 'stats.totalFours';
  static const _kTotalSixes = 'stats.totalSixes';
  static const _kTotalWickets = 'stats.totalWickets';
  static const _kTutorialSeen = 'stats.tutorialSeen';

  GameStats _cache = GameStats.empty;
  GameStats get current => _cache;

  /// True after `init()` has finished. Widgets should treat the cache as
  /// authoritative immediately; we just don't notify listeners until init
  /// is done so the first paint is consistent.
  bool _ready = false;
  bool get ready => _ready;

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _cache = GameStats(
        matchesPlayed: p.getInt(_kMatchesPlayed) ?? 0,
        matchesWon: p.getInt(_kMatchesWon) ?? 0,
        bestScore: p.getInt(_kBestScore) ?? 0,
        totalRuns: p.getInt(_kTotalRuns) ?? 0,
        totalFours: p.getInt(_kTotalFours) ?? 0,
        totalSixes: p.getInt(_kTotalSixes) ?? 0,
        totalWickets: p.getInt(_kTotalWickets) ?? 0,
        tutorialSeen: p.getBool(_kTutorialSeen) ?? false,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('StatsService.init failed: $e');
    }
    _ready = true;
    notifyListeners();
  }

  Future<void> recordMatch({
    required int playerRuns,
    required int fours,
    required int sixes,
    required int wickets,
    required bool playerWon,
  }) async {
    final updated = _cache.copyWith(
      matchesPlayed: _cache.matchesPlayed + 1,
      matchesWon: _cache.matchesWon + (playerWon ? 1 : 0),
      bestScore:
          playerRuns > _cache.bestScore ? playerRuns : _cache.bestScore,
      totalRuns: _cache.totalRuns + playerRuns,
      totalFours: _cache.totalFours + fours,
      totalSixes: _cache.totalSixes + sixes,
      totalWickets: _cache.totalWickets + wickets,
    );
    _cache = updated;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await Future.wait([
        p.setInt(_kMatchesPlayed, updated.matchesPlayed),
        p.setInt(_kMatchesWon, updated.matchesWon),
        p.setInt(_kBestScore, updated.bestScore),
        p.setInt(_kTotalRuns, updated.totalRuns),
        p.setInt(_kTotalFours, updated.totalFours),
        p.setInt(_kTotalSixes, updated.totalSixes),
        p.setInt(_kTotalWickets, updated.totalWickets),
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('StatsService.recordMatch failed: $e');
    }
  }

  Future<void> markTutorialSeen() async {
    if (_cache.tutorialSeen) return;
    _cache = _cache.copyWith(tutorialSeen: true);
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kTutorialSeen, true);
    } catch (e) {
      if (kDebugMode) debugPrint('StatsService.markTutorialSeen failed: $e');
    }
  }

  /// Wipe all persisted stats. Surfaced for "reset stats" UX.
  Future<void> reset() async {
    _cache = GameStats.empty;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await Future.wait([
        p.remove(_kMatchesPlayed),
        p.remove(_kMatchesWon),
        p.remove(_kBestScore),
        p.remove(_kTotalRuns),
        p.remove(_kTotalFours),
        p.remove(_kTotalSixes),
        p.remove(_kTotalWickets),
        p.remove(_kTutorialSeen),
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('StatsService.reset failed: $e');
    }
  }
}
