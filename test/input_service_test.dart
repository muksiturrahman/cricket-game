import 'package:flutter_test/flutter_test.dart';

import 'package:cricket_game/services/input_service.dart';
import 'package:cricket_game/utils/constants.dart';

void main() {
  late InputService input;
  setUp(() => input = InputService());

  group('swipeToIntent', () {
    test('tiny swipe → defensive (force = 0)', () {
      final i = input.swipeToIntent(
        const Offset(100, 100),
        const Offset(105, 100), // 5 px — below 16 px threshold
        powerOn: false,
      );
      expect(i.isDefensive, true);
      expect(i.force, 0);
    });

    test('zero swipe (tap) → defensive', () {
      final i = input.swipeToIntent(
        const Offset(100, 100),
        const Offset(100, 100),
        powerOn: true,
      );
      expect(i.isDefensive, true);
    });

    test('20 px swipe → directed shot, partial force', () {
      final i = input.swipeToIntent(
        const Offset(0, 0),
        const Offset(20, 0), // exactly above 16 px threshold
        powerOn: false,
      );
      expect(i.isDefensive, false);
      // 20 / 140 ≈ 0.14
      expect(i.force, closeTo(20 / 140, 0.02));
      expect(i.direction.x, closeTo(1.0, 1e-6));
      expect(i.direction.y, closeTo(0, 1e-6));
    });

    test('long swipe clamps force at 1.0', () {
      final i = input.swipeToIntent(
        const Offset(0, 0),
        const Offset(500, 0),
        powerOn: false,
      );
      expect(i.force, 1.0);
    });

    test('right-and-down swipe yields right-down direction', () {
      final i = input.swipeToIntent(
        const Offset(0, 0),
        const Offset(60, 60),
        powerOn: false,
      );
      expect(i.direction.x, closeTo(0.7071, 1e-3));
      expect(i.direction.y, closeTo(0.7071, 1e-3));
    });

    test('powerOn flag is passed through verbatim', () {
      final off = input.swipeToIntent(
        const Offset(0, 0),
        const Offset(50, 0),
        powerOn: false,
      );
      final on = input.swipeToIntent(
        const Offset(0, 0),
        const Offset(50, 0),
        powerOn: true,
      );
      expect(off.powerOn, false);
      expect(on.powerOn, true);
    });

    test('upward swipe → pullShot category', () {
      final i = input.swipeToIntent(
        const Offset(0, 100),
        const Offset(0, 0), // dy = -100 (toward top of screen)
        powerOn: false,
      );
      expect(i.type, ShotType.pullShot);
    });
  });
}
