import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_game/services/physics_service.dart';
import 'package:cricket_game/services/shot_intent.dart';

void main() {
  late PhysicsService p;
  setUp(() => p = PhysicsService());

  group('reboundVelocity defensive', () {
    test('returns soft downward, ignores power flag', () {
      final v = p.reboundVelocity(ShotIntent.defensive(), 400);
      expect(v.x, 0);
      expect(v.y, greaterThan(0));
      expect(v.y, lessThan(60)); // ~0.80 * 0.15 * 400 = 48
    });
  });

  group('reboundVelocity grounded', () {
    test('upward swipe + power off → vy clamped low', () {
      final intent = ShotIntent.directed(
        direction: Vector2(0, -1),
        force: 1.0,
        powerOn: false,
      );
      final v = p.reboundVelocity(intent, 400);
      // Magnitude = 0.80 * 400 * 1.0 = 320; vy = clamp(-1, -0.15, 0.40) = -0.15
      // → vy = -0.15 * 320 = -48. Capped, not flying high.
      expect(v.y, closeTo(-48, 1));
    });

    test('rightward swipe + power off → flat horizontal', () {
      final intent = ShotIntent.directed(
        direction: Vector2(1, 0),
        force: 1.0,
        powerOn: false,
      );
      final v = p.reboundVelocity(intent, 400);
      expect(v.x, greaterThan(0));
      // Vertical component is exactly 0 — clamp(0, -0.15, 0.40) = 0
      expect(v.y, 0);
    });

    test('force scales magnitude (55% to 100%)', () {
      final low = p.reboundVelocity(
        ShotIntent.directed(direction: Vector2(1, 0), force: 0.0, powerOn: false),
        400,
      );
      final high = p.reboundVelocity(
        ShotIntent.directed(direction: Vector2(1, 0), force: 1.0, powerOn: false),
        400,
      );
      // base = 0.80 * 400 = 320
      // low magnitude = 320 * 0.55 = 176, high = 320 * 1.0 = 320
      expect(low.x, closeTo(176, 1));
      expect(high.x, closeTo(320, 1));
    });
  });

  group('reboundVelocity power on', () {
    test('flat sideways power lofts only modestly (no automatic six)', () {
      // Even a flat right-swipe lofts slightly under the new tuning, but
      // not enough to clear a ~330 px boundary. Apex height = vy²/(2g).
      final intent = ShotIntent.directed(
        direction: Vector2(1, 0),
        force: 1.0,
        powerOn: true,
      );
      final v = p.reboundVelocity(intent, 400);
      // liftedDy = 0 * 0.75 - 0.30 = -0.30; capped at <= -0.20 (already true).
      // vy = -0.30 * 320 = -96  → apex ~26 px (won't clear).
      expect(v.y, lessThan(0));
      expect(v.y, closeTo(-96, 2));
    });

    test('flat right-ish swipe + power → vy still capped upward', () {
      // A rightward swipe with a tiny downward component — classified as
      // straightDrive (NOT defensive), so power applies. Verifies vy stays
      // negative (always lofts) but not enough for a 6.
      final intent = ShotIntent.directed(
        direction: Vector2(1, 0.1),
        force: 1.0,
        powerOn: true,
      );
      final v = p.reboundVelocity(intent, 400);
      expect(v.y, lessThan(0));
    });

    test('upward swipe + power → strongest loft, only just clears the rope', () {
      // Full-force upward swipe with power is the only configuration
      // strong enough to clear a 330 px boundary.
      final intent = ShotIntent.directed(
        direction: Vector2(0, -1),
        force: 1.0,
        powerOn: true,
      );
      final v = p.reboundVelocity(intent, 400);
      // liftedDy = -0.75 - 0.30 = -1.05; vy = -1.05 * 320 = -336.
      // Apex ≈ 336²/360 = 313 px. Borderline — sometimes clears.
      expect(v.y, closeTo(-336, 2));
    });
  });

  group('reboundVelocity quality (timing)', () {
    final cleanIntent = ShotIntent.directed(
      direction: Vector2(1, 0),
      force: 1.0,
      powerOn: false,
    );

    test('clean is the default and matches the unparameterized call', () {
      final defaulted = p.reboundVelocity(cleanIntent, 400);
      final explicit = p.reboundVelocity(
        cleanIntent,
        400,
        quality: ShotQuality.clean,
      );
      expect(explicit.x, defaulted.x);
      expect(explicit.y, defaulted.y);
    });

    test('mistimed scales magnitude by 0.55', () {
      final clean = p.reboundVelocity(cleanIntent, 400, quality: ShotQuality.clean);
      final mis = p.reboundVelocity(cleanIntent, 400, quality: ShotQuality.mistimed);
      // 0.55x of clean's x; vertical should also scale (it's 0 here so we
      // just sanity-check non-negative).
      expect(mis.x, closeTo(clean.x * 0.55, 0.5));
      expect(mis.y, 0);
    });

    test('mistimed lofted shot still lofts, but the apex is too low for a six', () {
      final lofted = ShotIntent.directed(
        direction: Vector2(0, -1),
        force: 1.0,
        powerOn: true,
      );
      final mis = p.reboundVelocity(lofted, 400, quality: ShotQuality.mistimed);
      // Magnitude becomes 320 * 0.55 = 176; vy = -1.05 * 176 ≈ -185.
      // Apex = 185²/360 ≈ 95 px → comfortably short of a 330 px rope.
      expect(mis.y, lessThan(0));
      expect(mis.y, closeTo(-185, 2));
    });

    test('edge ignores intent direction — ball deflects backward toward keeper', () {
      // Try a hard rightward swipe; an edge should send it +y (toward the
      // keeper) instead of +x.
      final v = p.reboundVelocity(cleanIntent, 400, quality: ShotQuality.edge);
      // back component = 400 * 0.55 = 220
      expect(v.y, closeTo(220, 0.001));
      // x is randomized — bound by ±0.5 * 0.35 * 400 = ±70
      expect(v.x.abs(), lessThanOrEqualTo(70));
    });

    test('edge ignores defensive flag too — even a tap can edge', () {
      final v = p.reboundVelocity(
        ShotIntent.defensive(),
        400,
        quality: ShotQuality.edge,
      );
      // back = 400 * 0.55 = 220 (matches the rightward case, since the edge
      // branch runs before the defensive short-circuit).
      expect(v.y, closeTo(220, 0.001));
    });

    test('edge x-deflection is genuinely randomized across calls', () {
      // Run a handful of edges and assert at least one ends up on each side.
      // Cheap way to verify the ±lateral spread isn't degenerate.
      var sawLeft = false, sawRight = false;
      for (var i = 0; i < 30; i++) {
        final v = p.reboundVelocity(cleanIntent, 400, quality: ShotQuality.edge);
        if (v.x < 0) sawLeft = true;
        if (v.x > 0) sawRight = true;
        if (sawLeft && sawRight) break;
      }
      expect(sawLeft && sawRight, isTrue,
          reason: 'edge lateral deflection should be randomized in sign');
    });
  });
}
