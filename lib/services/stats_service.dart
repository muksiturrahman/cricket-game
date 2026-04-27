import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One row of the per-match history. Persisted as JSON in
/// `shared_preferences` so we keep the last `_kHistoryMax` matches across
/// app restarts. Fields chosen for the menu's history list.
class MatchHistoryEntry {
  final int runs;
  final int wickets;
  final int fours;
  final int sixes;
  final bool won;
  final String format; // e.g. "T5", "T10"
  final String difficulty; // e.g. "Normal"
  /// Unix epoch ms for sortability.
  final int timestampMs;

  const MatchHistoryEntry({
    required this.runs,
    required this.wickets,
    required this.fours,
    required this.sixes,
    required this.won,
    required this.format,
    required this.difficulty,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'r': runs,
        'w': wickets,
        '4s': fours,
        '6s': sixes,
        'won': won,
        'fmt': format,
        'diff': difficulty,
        't': timestampMs,
      };

  static MatchHistoryEntry? fromJson(Map<String, dynamic> j) {
    try {
      return MatchHistoryEntry(
        runs: j['r'] as int,
        wickets: j['w'] as int,
        fours: j['4s'] as int,
        sixes: j['6s'] as int,
        won: j['won'] as bool,
        format: j['fmt'] as String,
        difficulty: j['diff'] as String,
        timestampMs: j['t'] as int,
      );
    } catch (_) {
      return null;
    }
  }
}

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
  /// Per-match log, newest first. Capped at `_kHistoryMax`.
  final List<MatchHistoryEntry> recentMatches;

  const GameStats({
    required this.matchesPlayed,
    required this.matchesWon,
    required this.bestScore,
    required this.totalRuns,
    required this.totalFours,
    required this.totalSixes,
    required this.totalWickets,
    required this.tutorialSeen,
    this.recentMatches = const [],
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
    recentMatches: [],
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
    List<MatchHistoryEntry>? recentMatches,
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
        recentMatches: recentMatches ?? this.recentMatches,
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
  static const _kHistory = 'stats.history';
  static const int _kHistoryMax = 12;

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
        recentMatches: _loadHistory(p),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('StatsService.init failed: $e');
    }
    _ready = true;
    notifyListeners();
  }

  List<MatchHistoryEntry> _loadHistory(SharedPreferences p) {
    final raw = p.getString(_kHistory);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => MatchHistoryEntry.fromJson(e as Map<String, dynamic>))
          .whereType<MatchHistoryEntry>()
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('StatsService._loadHistory failed: $e');
      return const [];
    }
  }

  Future<void> recordMatch({
    required int playerRuns,
    required int fours,
    required int sixes,
    required int wickets,
    required bool playerWon,
    String format = 'T?',
    String difficulty = '?',
  }) async {
    final entry = MatchHistoryEntry(
      runs: playerRuns,
      wickets: wickets,
      fours: fours,
      sixes: sixes,
      won: playerWon,
      format: format,
      difficulty: difficulty,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
    final history = [entry, ..._cache.recentMatches].take(_kHistoryMax).toList();
    final updated = _cache.copyWith(
      matchesPlayed: _cache.matchesPlayed + 1,
      matchesWon: _cache.matchesWon + (playerWon ? 1 : 0),
      bestScore:
          playerRuns > _cache.bestScore ? playerRuns : _cache.bestScore,
      totalRuns: _cache.totalRuns + playerRuns,
      totalFours: _cache.totalFours + fours,
      totalSixes: _cache.totalSixes + sixes,
      totalWickets: _cache.totalWickets + wickets,
      recentMatches: history,
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
        p.setString(_kHistory,
            jsonEncode(history.map((e) => e.toJson()).toList())),
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
        p.remove(_kHistory),
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('StatsService.reset failed: $e');
    }
  }
}
