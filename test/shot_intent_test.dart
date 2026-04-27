import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_game/services/shot_intent.dart';
import 'package:cricket_game/utils/constants.dart';

void main() {
  group('ShotIntent.defensive', () {
    test('has zero direction, zero force, defensive type', () {
      final i = ShotIntent.defensive();
      expect(i.direction, Vector2.zero());
      expect(i.force, 0);
      expect(i.powerOn, false);
      expect(i.type, ShotType.defensive);
      expect(i.isDefensive, true);
    });
  });

  group('ShotIntent.directed', () {
    test('normalizes the direction vector', () {
      final i = ShotIntent.directed(
        direction: Vector2(8, 0), // not unit length
        force: 0.5,
        powerOn: false,
      );
      expect(i.direction.length, closeTo(1.0, 1e-6));
      expect(i.direction.x, closeTo(1.0, 1e-6));
      expect(i.direction.y, closeTo(0.0, 1e-6));
    });

    test('clamps force into 0..1', () {
      expect(
        ShotIntent.directed(direction: Vector2(1, 0), force: -0.4, powerOn: false)
            .force,
        0.0,
      );
      expect(
        ShotIntent.directed(direction: Vector2(1, 0), force: 7.2, powerOn: true)
            .force,
        1.0,
      );
    });

    test('classifies right-ish swipe as straightDrive', () {
      final i = ShotIntent.directed(
        direction: Vector2(1, 0), // pure right
        force: 1.0,
        powerOn: false,
      );
      expect(i.type, ShotType.straightDrive);
    });

    test('classifies upward swipe (toward bowler) as pullShot', () {
      final i = ShotIntent.directed(
        direction: Vector2(0, -1), // up = toward bowler
        force: 1.0,
        powerOn: true,
      );
      expect(i.type, ShotType.pullShot);
    });

    test('classifies left swipe as coverDrive', () {
      final i = ShotIntent.directed(
        direction: Vector2(-1, 0),
        force: 1.0,
        powerOn: false,
      );
      expect(i.type, ShotType.coverDrive);
    });

    test('classifies downward swipe as defensive', () {
      final i = ShotIntent.directed(
        direction: Vector2(0, 1), // down = back at batsman
        force: 1.0,
        powerOn: false,
      );
      expect(i.type, ShotType.defensive);
    });

    test('zero-length direction degrades to defensive', () {
      final i = ShotIntent.directed(
        direction: Vector2.zero(),
        force: 1.0,
        powerOn: true,
      );
      expect(i.type, ShotType.defensive);
      expect(i.direction.length, 0);
    });
  });
}
