import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Procedural sound effects.
///
/// The game synthesizes its own WAV data (16-bit PCM mono @ 22050 Hz) at
/// first launch and writes each effect to a file in the app's Application
/// Support directory. Playback uses `audioplayers` `DeviceFileSource`.
///
/// Why files and not `BytesSource`: on macOS, audioplayers' `BytesSource`
/// stages bytes in `~/Library/Caches/<bundle>/...`, which the OS can purge
/// at any time. The first play would succeed and every subsequent one
/// would fail with `PathNotFoundException`. Application Support isn't
/// auto-purged, so the file we write at preload is still there on the
/// next play. A small `AudioPlayer` pool is round-robined so effects can
/// overlap (e.g., bat-hit + cheer).
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  /// User toggle — wired to a settings switch in the future. Default on.
  bool enabled = true;

  static const int _sampleRate = 22050;
  static const int _poolSize = 4;

  final Map<String, String> _paths = {};
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  bool _ready = false;

  /// Build all WAVs and prime the player pool. Call once during app boot.
  Future<void> preload() async {
    if (_ready) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final sfxDir = Directory('${dir.path}/sfx');
      if (!await sfxDir.exists()) {
        await sfxDir.create(recursive: true);
      }

      Future<void> bake(String key, List<double> samples) async {
        final file = File('${sfxDir.path}/$key.wav');
        await file.writeAsBytes(_pack(samples), flush: true);
        _paths[key] = file.path;
      }

      await bake('bat_hit', _synthBatHit());
      await bake('bounce', _synthBounce());
      await bake('wicket', _synthWicket());
      await bake('catch', _synthCatch());
      await bake('cheer_four', _synthCheer(amount: 0.65, dur: 0.7));
      await bake('cheer_six', _synthCheer(amount: 1.0, dur: 1.2));
      await bake('run', _synthRun());

      for (var i = 0; i < _poolSize; i++) {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        _pool.add(p);
      }
      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService.preload failed: $e');
    }
  }

  Future<void> _play(String key, {double volume = 0.7}) async {
    if (!enabled || !_ready) return;
    final path = _paths[key];
    if (path == null || _pool.isEmpty) return;
    try {
      final p = _pool[_next];
      _next = (_next + 1) % _pool.length;
      await p.stop();
      await p.setVolume(volume);
      await p.play(DeviceFileSource(path));
    } catch (e) {
      if (kDebugMode) debugPrint('SoundService._play($key) failed: $e');
    }
  }

  // ── Public API (called from CricketGame) ───────────────────────────────
  Future<void> batHit() => _play('bat_hit', volume: 0.9);
  Future<void> bounce() => _play('bounce', volume: 0.45);
  Future<void> wicket() => _play('wicket', volume: 0.95);
  Future<void> caught() => _play('catch', volume: 0.85);
  Future<void> cheerFour() => _play('cheer_four', volume: 0.75);
  Future<void> cheerSix() => _play('cheer_six', volume: 0.9);
  Future<void> run() => _play('run', volume: 0.6);

  Future<void> dispose() async {
    for (final p in _pool) {
      await p.dispose();
    }
    _pool.clear();
  }

  // ── Synthesis ──────────────────────────────────────────────────────────
  // Each generator returns a list of float samples in [-1, 1] at 22050 Hz.
  // Envelopes are exponential decays unless noted; no anti-aliasing.

  List<double> _synthBatHit() {
    // Sharp wood-on-leather thwack: bright noise transient + low resonance.
    const dur = 0.18;
    final n = (_sampleRate * dur).round();
    final out = List<double>.filled(n, 0);
    final rng = math.Random(1);
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      final env = math.exp(-t * 28);
      final noise = (rng.nextDouble() * 2 - 1);
      // Wood resonance — quick fundamental + 2nd partial
      final res = math.sin(2 * math.pi * 320 * t) * 0.5 +
          math.sin(2 * math.pi * 640 * t) * 0.25;
      out[i] = (noise * 0.55 + res * 0.45) * env * 0.85;
    }
    return out;
  }

  List<double> _synthBounce() {
    // Soft pitch-falling thump.
    const dur = 0.22;
    final n = (_sampleRate * dur).round();
    final out = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      final env = math.exp(-t * 22);
      // Frequency descends from 130 Hz to ~70 Hz.
      final freq = 130 - 60 * t / dur;
      out[i] = math.sin(2 * math.pi * freq * t) * env * 0.55;
    }
    return out;
  }

  List<double> _synthWicket() {
    // Stumps clatter: filtered noise burst + descending pitch tail.
    const dur = 0.55;
    final n = (_sampleRate * dur).round();
    final out = List<double>.filled(n, 0);
    final rng = math.Random(2);
    // Very short low-pass-ish filter (running average) state
    var lpA = 0.0;
    var lpB = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      // Two stacked envelopes — sharp clatter then a longer rumble.
      final eClatter = math.exp(-t * 18);
      final eRumble = math.exp(-t * 5) * 0.55;
      final raw = (rng.nextDouble() * 2 - 1);
      // Cheap 2-pole lowpass to take the harshness off the clatter
      lpA = lpA * 0.6 + raw * 0.4;
      lpB = lpB * 0.7 + lpA * 0.3;
      // Descending tone for the wood
      final tone = math.sin(2 * math.pi * (220 - 80 * t / dur) * t);
      out[i] = (lpB * 0.7 * eClatter + tone * 0.5 * eRumble) * 0.85;
    }
    return out;
  }

  List<double> _synthCatch() {
    // Sharp hand-slap — short noise burst, slightly band-passed.
    const dur = 0.16;
    final n = (_sampleRate * dur).round();
    final out = List<double>.filled(n, 0);
    final rng = math.Random(3);
    var lp = 0.0;
    var prev = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      final env = math.exp(-t * 35);
      final raw = (rng.nextDouble() * 2 - 1);
      // Band-pass-ish: lowpass then high-pass-by-difference.
      lp = lp * 0.65 + raw * 0.35;
      final hp = lp - prev;
      prev = lp;
      out[i] = hp * env * 0.9;
    }
    return out;
  }

  List<double> _synthCheer({required double amount, required double dur}) {
    // Crowd roar — pink-ish noise pad with slow attack and slow release.
    final n = (_sampleRate * dur).round();
    final out = List<double>.filled(n, 0);
    final rng = math.Random(4);
    // Layered noise with running averages = roughly pink.
    var lp1 = 0.0, lp2 = 0.0, lp3 = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      final tt = t / dur;
      // Attack 12% of duration, release the remainder.
      final env = tt < 0.12
          ? (tt / 0.12)
          : math.pow((1 - tt) / 0.88, 1.4).toDouble();
      final raw = (rng.nextDouble() * 2 - 1);
      lp1 = lp1 * 0.85 + raw * 0.15;
      lp2 = lp2 * 0.92 + lp1 * 0.08;
      lp3 = lp3 * 0.97 + lp2 * 0.03;
      // Mix layers — adds the "thickness" of a crowd.
      final crowd = (lp1 * 0.4 + lp2 * 0.4 + lp3 * 0.6);
      out[i] = crowd * env * amount * 0.9;
    }
    return out;
  }

  List<double> _synthRun() {
    // Quick two-tone rising whistle — implies "yes, run!".
    const dur = 0.16;
    final n = (_sampleRate * dur).round();
    final out = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      final tt = t / dur;
      final env = math.exp(-t * 9) * (1 - math.exp(-t * 60));
      // Glide from 600 Hz to 1200 Hz.
      final freq = 600 + 600 * tt;
      out[i] = math.sin(2 * math.pi * freq * t) * env * 0.5;
    }
    return out;
  }

  // ── WAV packing ────────────────────────────────────────────────────────
  /// Wrap a float sample buffer in a minimal RIFF/WAVE 16-bit-PCM container.
  Uint8List _pack(List<double> samples) {
    final n = samples.length;
    final dataSize = n * 2; // 16-bit = 2 bytes per sample
    final fileSize = 36 + dataSize;
    final bytes = ByteData(44 + dataSize);
    var off = 0;

    void writeStr(String s) {
      for (final c in s.codeUnits) {
        bytes.setUint8(off++, c);
      }
    }

    void writeU32(int v) {
      bytes.setUint32(off, v, Endian.little);
      off += 4;
    }

    void writeU16(int v) {
      bytes.setUint16(off, v, Endian.little);
      off += 2;
    }

    writeStr('RIFF');
    writeU32(fileSize);
    writeStr('WAVE');
    writeStr('fmt ');
    writeU32(16); // subchunk1 size
    writeU16(1); // PCM
    writeU16(1); // mono
    writeU32(_sampleRate);
    writeU32(_sampleRate * 2); // byte rate
    writeU16(2); // block align
    writeU16(16); // bits per sample
    writeStr('data');
    writeU32(dataSize);

    for (var i = 0; i < n; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      bytes.setInt16(off, (clamped * 32767).round(), Endian.little);
      off += 2;
    }
    return bytes.buffer.asUint8List();
  }
}
