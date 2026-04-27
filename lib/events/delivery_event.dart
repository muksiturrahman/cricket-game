import '../game/ai_manager.dart';
import '../game/score_manager.dart';
import '../services/shot_intent.dart';
import '../utils/constants.dart';

sealed class DeliveryEvent {
  const DeliveryEvent();
}

class BallLaunched extends DeliveryEvent {
  final BowlConfig config;
  const BallLaunched(this.config);
}

class BatContact extends DeliveryEvent {
  final ShotIntent intent;
  const BatContact(this.intent);
}

class WicketFallen extends DeliveryEvent {
  const WicketFallen();
}

class BallCaught extends DeliveryEvent {
  final FieldPosition by;
  const BallCaught(this.by);
}

class BallFielded extends DeliveryEvent {
  final FieldPosition by;
  const BallFielded(this.by);
}

class BallDead extends DeliveryEvent {
  const BallDead();
}

/// Player completed a run (pressed R while ball was live).
class RunTaken extends DeliveryEvent {
  final int totalThisBall;
  const RunTaken(this.totalThisBall);
}

/// Ball reached the screen edge after being hit. 6 if it never bounced, else 4.
class BoundaryHit extends DeliveryEvent {
  final int runs;
  const BoundaryHit(this.runs);
}

class ScoreChanged extends DeliveryEvent {
  final String scoreString;
  final String overString;
  final double runRate;
  /// Only set during the AI's chase. HUD renders "TARGET 88 · NEED 12" line.
  final int? target;
  const ScoreChanged({
    required this.scoreString,
    required this.overString,
    this.runRate = 0,
    this.target,
  });
}

/// Fired exactly once at the end of every delivery, carrying the final
/// outcome (dot, 1/2/3, 4, 6, W). HUD uses this to push to the recent-balls
/// strip; ScoreManager already has the same outcome appended to its history.
class BallSettled extends DeliveryEvent {
  final BallOutcome outcome;
  const BallSettled(this.outcome);
}

enum ExtraKind { wide, noBall }

/// Illegal delivery (wide / no-ball). +1 to score; wides re-bowl, no-balls
/// still count as a delivery. HUD shows a "WIDE!" / "NO BALL!" banner.
class ExtraCalled extends DeliveryEvent {
  final ExtraKind kind;
  final int runs;
  const ExtraCalled(this.kind, this.runs);
}

/// Run-out — fielder threw at the stumps while the batsman was sprinting
/// between creases. Wicket falls; only completed runs (the ones the
/// batsman finished before the throw) count.
class RunOutCalled extends DeliveryEvent {
  final int completedRuns;
  final FieldPosition by;
  const RunOutCalled(this.completedRuns, this.by);
}

/// Shot timing wasn't clean — fired by `CricketGame` immediately after
/// `BatContact` when the swing-window progress crossed `kSwingCleanMax`.
/// HUD-only: shows a small "MISTIMED" / "EDGE!" feedback banner.
class ShotQualityCalled extends DeliveryEvent {
  final ShotQuality quality;
  const ShotQualityCalled(this.quality);
}

/// Fielder slid in at the rope and stopped what would have been a 4.
/// HUD-only: flashes a "SAVED!" banner; CricketGame fires it before
/// `_finishDelivery` so the player can see the dive happen.
class BoundarySaved extends DeliveryEvent {
  final FieldPosition by;
  const BoundarySaved(this.by);
}
