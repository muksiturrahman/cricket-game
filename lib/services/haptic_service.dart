import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around `HapticFeedback`. Mobile-only — `HapticFeedback`
/// silently no-ops on desktop / web, but we still gate by platform so we
/// don't hit the platform channel at all on those targets.
class HapticService {
  HapticService._();
  static final HapticService instance = HapticService._();

  bool enabled = true;

  bool get _onMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  void light() {
    if (!enabled || !_onMobile) return;
    HapticFeedback.lightImpact();
  }

  void medium() {
    if (!enabled || !_onMobile) return;
    HapticFeedback.mediumImpact();
  }

  void heavy() {
    if (!enabled || !_onMobile) return;
    HapticFeedback.heavyImpact();
  }

  /// Quick selection-style click — for UI buttons (POWER toggle, etc.).
  void selection() {
    if (!enabled || !_onMobile) return;
    HapticFeedback.selectionClick();
  }
}
