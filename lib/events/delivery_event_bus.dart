import 'dart:async';

import 'delivery_event.dart';

/// Lightweight broadcast bus for in-game events.
///
/// Async (default) delivery: listeners run in a microtask after `fire()`
/// returns. Microtasks drain before the next frame, so state mutations
/// triggered by an event are visible to the next `update(dt)`.
///
/// **Do not use `sync: true`.** A handler that fires another event (e.g.
/// `BatContact` → `_broadcastScore` → `ScoreChanged`) re-enters the
/// controller and Dart throws "Cannot fire new event."
class DeliveryEventBus {
  final _controller = StreamController<DeliveryEvent>.broadcast();

  Stream<DeliveryEvent> get stream => _controller.stream;

  void fire(DeliveryEvent event) => _controller.add(event);

  void dispose() => _controller.close();
}
