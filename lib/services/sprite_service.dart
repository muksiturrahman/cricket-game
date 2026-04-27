import 'dart:async';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Loads optional sprite assets used by the on-pitch components.
///
/// The game ships with canvas-drawn placeholders for batsman / bowler /
/// fielder / ball — drop a matching PNG into `assets/images/` and the
/// component will switch to the sprite automatically (it falls back to
/// canvas drawing if the file isn't bundled).
///
/// **Required setup if you want to use sprites:**
///   1. Drop the files below into `assets/images/`
///   2. Add `- assets/images/` under `flutter.assets:` in `pubspec.yaml`
///   3. `flutter pub get`
///
/// **Required asset list:**
///   batsman.png   — 96 × 160 idle frame, anchor at feet
///   bowler.png    — 96 × 160 idle frame
///   fielder.png   — 56 × 56 (centre-aligned)
///   ball.png      — 32 × 32 with seam visible
///
/// Loaded once at start; missing files are silently noted via `_missing`.
class SpriteService extends ChangeNotifier {
  SpriteService._();
  static final SpriteService instance = SpriteService._();

  final Map<String, Sprite> _cache = {};
  final Set<String> _missing = {};
  bool _ready = false;
  bool get ready => _ready;

  static const _assets = <String>[
    'batsman.png',
    'bowler.png',
    'fielder.png',
    'ball.png',
  ];

  /// Best-effort preload. We probe via `rootBundle.load` first so missing
  /// assets don't trigger Flame's noisy uncaught-exception path.
  Future<void> init() async {
    for (final name in _assets) {
      final path = 'assets/images/$name';
      try {
        await rootBundle.load(path);
      } catch (_) {
        _missing.add(name);
        continue;
      }
      try {
        _cache[name] = await Sprite.load(name);
      } catch (e) {
        _missing.add(name);
        if (kDebugMode) {
          debugPrint('SpriteService: $name probe ok but load failed: $e');
        }
      }
    }
    _ready = true;
    notifyListeners();
  }

  /// Returns the cached sprite, or null if the asset wasn't bundled. Game
  /// components fall back to their canvas placeholder when null.
  Sprite? get(String name) => _cache[name];

  bool isMissing(String name) => _missing.contains(name);

  /// For tests / "reset" UX: drop everything cached and re-init.
  Future<void> reload() async {
    _cache.clear();
    _missing.clear();
    Flame.images.clearCache();
    await init();
  }
}
