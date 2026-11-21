import 'dart:io';

import 'package:live_activities/live_activities.dart';

/// iOS Live Activity for the rest timer (lock screen + Dynamic Island).
///
/// The Dart side only passes data — exercise, next set, rest end — to
/// the native side. The actual layout lives in the ForgeLiveActivity
/// widget extension (Swift, ios/ForgeLiveActivity/), which reads the
/// data from the shared App Group and renders the countdown with
/// Text(timerInterval:). Adding that Xcode target is a manual step on
/// the Mac — see ios/LIVE_ACTIVITY_SETUP.md.
///
/// Android never touches the plugin: the ongoing notification covers
/// it there. Every call is best-effort — if the extension target is
/// not installed yet, or the device is below iOS 16.1, the plugin
/// throws and the call is swallowed here; the notification shade and
/// the in-app timer still work.
class LiveActivityService {
  LiveActivityService._();

  static final _plugin = LiveActivities();

  /// The App Group shared by the Runner app and the widget extension.
  /// The same id must be added as a capability in Xcode for both
  /// targets (see ios/LIVE_ACTIVITY_SETUP.md).
  static const appGroupId = 'group.com.forge.app.forge';

  static const _activityId = 'forge-rest';

  static bool _initialized = false;

  static Future<void> init() async {
    if (!Platform.isIOS || _initialized) return;
    try {
      await _plugin.init(appGroupId: appGroupId);
      _initialized = true;
    } catch (_) {
      // Live Activities unavailable — notifications cover it.
    }
  }

  static Map<String, dynamic> _data({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
  }) =>
      {
        'exerciseName': exerciseName,
        'nextSet': 'Set $nextSetIndex',
        'endsAtMillis': endsAt.millisecondsSinceEpoch,
      };

  /// Starts (or updates, if one is already running) the rest Live
  /// Activity. The extension renders the countdown from endsAt, so
  /// it keeps counting even when the app is backgrounded.
  static Future<void> startRest({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
  }) async {
    if (!Platform.isIOS) return;
    await init();
    try {
      await _plugin.createOrUpdateActivity(
        _activityId,
        _data(
          exerciseName: exerciseName,
          nextSetIndex: nextSetIndex,
          endsAt: endsAt,
        ),
      );
    } catch (_) {}
  }

  /// +15s: the extension re-renders the countdown from the new end.
  static Future<void> updateRest({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
  }) async {
    if (!Platform.isIOS) return;
    try {
      await _plugin.updateActivity(
        _activityId,
        _data(
          exerciseName: exerciseName,
          nextSetIndex: nextSetIndex,
          endsAt: endsAt,
        ),
      );
    } catch (_) {}
  }

  /// Ends the rest Live Activity — on Skip, rest over, finish and
  /// discard.
  static Future<void> endRest() async {
    if (!Platform.isIOS) return;
    try {
      await _plugin.endActivity(_activityId);
    } catch (_) {}
  }
}
