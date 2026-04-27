import 'package:flutter/material.dart';

// ── Game rules ────────────────────────────────────────────────────────────────
const int kMaxOvers = 5;
const int kMaxWickets = 10;
const int kBallsPerOver = 6;

// ── Physics ───────────────────────────────────────────────────────────────────
const double kGravity = 180.0;
/// Default restitution — used for second-and-later bounces. The *first*
/// bounce uses a length-specific value (yorker barely lifts, bouncer rears
/// up) so the player can read the delivery's length from the bounce.
const double kBounceRestitution = 0.50;
/// Length-specific bounce energy. Applied only on the first bounce after
/// launch — subsequent bounces fall back to `kBounceRestitution`.
///   - yorker: pitches at the feet, barely lifts (~10 px)
///   - fullToss: rare bounce (it shouldn't bounce — but if it does, gentle)
///   - goodLength: lifts to bat-height (~110 px)
///   - shortPitch: rears up to head-height (~190 px), inviting hooks/pulls
const double kBounceRestitutionYorker = 0.15;
const double kBounceRestitutionFullToss = 0.25;
const double kBounceRestitutionGoodLength = 0.50;
const double kBounceRestitutionShortPitch = 0.65;
const double kRollDeceleration = 110.0;
const double kBallRadius = 12.0;

// ── Ball speeds (pixels/sec) ──────────────────────────────────────────────────
const double kMinBallSpeed = 280.0;
const double kMaxBallSpeed = 520.0;

// ── AI difficulty thresholds (balls bowled) ────────────────────────────────────
const int kMidInningsThreshold = 18;
const int kLateInningsThreshold = 24;

// ── Timing ────────────────────────────────────────────────────────────────────
const double kBowlerRunUpSec = 1.5;
const double kSettlingDelaySec = 1.2;
const double kSwingWindowSec = 0.30;

// ── Fielders ──────────────────────────────────────────────────────────────────
const double kFielderRadius = 14.0;
/// Catch / pickup hitbox radius. Tightened from 18 → 14 (= body) so catches
/// require precise alignment instead of "near enough" sweeps.
const double kFielderCatchRadius = 14.0;
const double kFielderHighlightSec = 0.6;
/// Running speed when chasing a hit ball or returning home (px/s). Ball is
/// 280-520 px/s, so fielders are roughly half as fast — they must rely on
/// positioning, not pure speed.
const double kFielderSpeed = 230.0;
/// When picking which fielder to assign the chase, look this far ahead along
/// the ball's velocity vector so we pick the one closest to where the ball
/// will be — not where it currently is.
const double kFielderChaseLookaheadSec = 0.6;
/// Offset (px) the backup fielder commits to *past* the primary chaser's
/// target along the ball's velocity vector — covers "if it gets through".
const double kBackupOffsetPx = 90.0;
/// Max distance a fielder can drift from their home spot. Prevents the
/// chasing fielder from running halfway across the field to "catch" a ball
/// that should have been a deep-fielder's territory.
const double kFielderMaxChaseDistance = 70.0;

// ── Running between wickets ──────────────────────────────────────────────────
/// Min seconds between consecutive R presses — simulates physical running time.
const double kRunCooldownSec = 0.55;
/// Realistic ceiling — you almost never run more than 3 on a single ball.
const int kMaxRunsPerBall = 3;
const int kBoundaryFourRuns = 4;
const int kBoundarySixRuns = 6;

// ── Batsman lateral positioning ─────────────────────────────────────────────
/// Max horizontal offset from the striker crease, in pixels. Allows stepping
/// to leg side / off side. Matched roughly to the visible width of the pitch.
const double kBatsmanMaxLateralPx = 90.0;
/// Movement speed when a movement key is held (or per drag-update on touch).
const double kBatsmanMoveSpeedPxPerSec = 280.0;
/// Horizontal offset of the non-striker's crease from screen centre. Pushes
/// the non-striker off to the side of the bowler so they're not directly
/// behind them (visually wrong, and in real cricket dangerous — bowler's
/// follow-through path).
const double kNonStrikerXOffset = 55.0;

// ── Ball settle detection ────────────────────────────────────────────────────
/// Squared velocity threshold below which a hit ball is considered "at rest".
/// Squared so we can compare against `velocity.length2` and skip a sqrt.
const double kBallSettleSpeedSq = 25.0; // ≈ 5 px/s
/// Seconds the ball must stay below the settle threshold before we end the
/// delivery — guards against momentary mid-bounce slowdowns.
const double kBallSettleSec = 0.4;

// ── Boundary rope (the white ellipse on the field) ───────────────────────────
/// Boundary ellipse width as a fraction of screen width.
const double kBoundaryWidthRatio = 0.90;
/// Boundary ellipse height as a fraction of screen height.
const double kBoundaryHeightRatio = 0.80;

// ── Inner ring (30-yard circle) ──────────────────────────────────────────────
const double kInnerRingWidthRatio = 0.55;
const double kInnerRingHeightRatio = 0.50;

// ── Shot timing ──────────────────────────────────────────────────────────────
/// Swing-window progress at contact (0..1) below which the shot is "clean":
/// player swung as the ball arrived. Anything before is perfect / minor early.
const double kSwingCleanMax = 0.55;
/// Above `kSwingCleanMax` and up to this threshold = mistimed: intended
/// direction but ~55% power. Drives die in the field, no boundaries.
const double kSwingMistimedMax = 0.80;
/// Anything above `kSwingMistimedMax` is an edge — player swung well before
/// the ball arrived. Deflects backward toward the keeper, low power.

// ── Wicket-keeper position ───────────────────────────────────────────────────
/// Keeper sits behind the striker's stumps. (x, y) as fractions of screen.
const double kKeeperXRatio = 0.50;
const double kKeeperYRatio = 0.80;

// ── DRS / replay (slow-motion playback on wickets / sixes) ───────────────────
/// Total time the slow-mo replay overlay stays on screen. The settling
/// delay is extended to this when a replay fires so the next ball doesn't
/// come while it's still playing.
const double kReplayDurationSec = 2.6;
/// Playback speed multiplier — 0.40 means 2.5× slower than real time. The
/// captured trajectory is replayed across `kReplayDurationSec`, so a 1s
/// delivery turns into a ~2.6s replay.
const double kReplayPlaybackSpeed = 0.40;
/// Max captured frames in the ring buffer (≈3s at 60fps). Older frames
/// drop off the front so we never show pre-bowl idle time.
const int kReplayMaxFrames = 200;

// ── Throws (run-outs) ────────────────────────────────────────────────────────
/// Constant straight-line throw speed (px/s) used when a fielder rifles the
/// ball at the stumps for a run-out attempt. Faster than running runs (≈580
/// px/s for one pitch length) so close fielders can beat the batsman home.
const double kThrowSpeed = 950.0;
/// Optional pickup delay (s) added before the throw is released — lets the
/// player visually register that the fielder has the ball before it whips
/// toward the stumps. Set to 0 for instant throws.
const double kThrowReactionSec = 0.18;

// ── Ball trail ───────────────────────────────────────────────────────────────
/// How many past ball positions to keep for the motion trail.
const int kBallTrailMaxSamples = 14;
/// Minimum world-distance between trail samples — prevents stacked dots when
/// the ball moves slowly.
const double kBallTrailSampleStep = 6.0;

// ── Colors ───────────────────────────────────────────────────────────────────
const Color kColorGrass = Color(0xFF3A7D44);
const Color kColorPitch = Color(0xFF8B5E3C);
const Color kColorBall = Color(0xFFCC2200);
const Color kColorBoundary = Color(0xFFFFFFFF);
const Color kColorStumps = Color(0xFFF5DEB3);
const Color kColorBails = Color(0xFFE8961A);
const Color kColorBat = Color(0xFF6B3F1A);
const Color kColorSky = Color(0xFF87CEEB);
const Color kColorHudBg = Color(0xBB000000);
const Color kColorHudText = Color(0xFFFFFFFF);
const Color kColorBatsmanKit = Color(0xFF1565C0);
const Color kColorBowlerKit = Color(0xFFFFFFFF);
const Color kColorSkin = Color(0xFFFFDBAC);
const Color kColorFielderKit = Color(0xFFE53935);
const Color kColorFielderHighlight = Color(0xFFFFEB3B);

// ── Enums ─────────────────────────────────────────────────────────────────────
enum ShotType { coverDrive, pullShot, straightDrive, defensive }

enum BallState { waiting, inFlight, afterBounce, dead }

enum GamePhase { mainMenu, playing, paused, gameOver }

enum BowlLine { onStumps, offStump, wide }

enum BowlLength { fullToss, goodLength, yorker, shortPitch }

enum FieldPosition {
  cover,
  midOff,
  midOn,
  squareLeg,
  longOff,
  longOn,
  midwicket,
  /// Wicket-keeper — stationary, behind the striker's stumps. Treated as a
  /// `Fielder` for collision purposes but excluded from the chase picker.
  keeper,
}

/// Which innings is in progress. `playerBats` is always first; `aiBats`
/// is only entered when `MatchSettings.chase` is true. `complete` means the
/// match is over and the game-over overlay is showing.
enum Innings { playerBats, aiBats, complete }
