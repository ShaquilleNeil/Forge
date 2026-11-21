import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/user_profile.dart';
import 'active_session.dart';
import 'live_activity_service.dart';
import 'session_store.dart';

/// Rest-timer alerts: which system displays are on for this rest.
/// Built from the profile (Settings → Rest timer) by the runner and
/// persisted so the background notification-action handler can read it
/// without Firestore.
class RestNotifyPrefs {
  const RestNotifyPrefs({
    this.notifications = true,
    this.vibrate = true,
    this.sound = true,
  });

  /// Show the countdown in the notification shade (Android) / as a
  /// Live Activity (iOS). Off leaves the in-app timer and haptics.
  final bool notifications;

  /// Buzz when the rest ends.
  final bool vibrate;

  /// Sound when the rest ends.
  final bool sound;

  factory RestNotifyPrefs.fromProfile(UserProfile profile) =>
      RestNotifyPrefs(
        notifications: profile.restNotifications,
        vibrate: profile.restVibrate,
        sound: profile.restSound,
      );

  Map<String, Object?> toJson() => {
        'notifications': notifications,
        'vibrate': vibrate,
        'sound': sound,
      };

  factory RestNotifyPrefs.fromJson(Map<String, dynamic> json) =>
      RestNotifyPrefs(
        notifications: json['notifications'] as bool? ?? true,
        vibrate: json['vibrate'] as bool? ?? true,
        sound: json['sound'] as bool? ?? true,
      );
}

/// Rest-timer notifications (Phase 6).
///
/// Model: the session stores `restEndsAt` (a wall-clock instant, not a
/// ticking counter). Everything — the in-app strip, the mini bar, the
/// notification chronometer, the Live Activity — derives remaining time
/// from restEndsAt − now, so +15s / Skip / backgrounding / app restart
/// all stay in sync.
///
/// Android:
/// * The countdown runs as a FOREGROUND SERVICE (flutter_foreground_task,
///   service id 101, type specialUse) — NOT a plain ongoing notification.
///   Why: on Android 14+ a notification posted with ongoing: true can
///   still be swiped away while the phone is unlocked, so "ongoing"
///   alone does not keep it. The service keeps running when the app is
///   backgrounded or swiped away, and its task handler re-posts the
///   notification every second with the live countdown, so even if the
///   user swipes it away it comes straight back (and while the phone is
///   locked it cannot be swiped at all). Title = the exercise, text =
///   "Rest — next: Set N · M:SS". Buttons +15s and Skip rest run
///   WITHOUT opening the app, through the service's task handler.
/// * Channel "rest_done" (high): the alert at restEndsAt — "Rest over
///   — Set N of <exercise>", sound + vibration [0, 400, 200, 400, 200,
///   600]. It is armed only when the app goes to the background
///   (armDoneAlert) and disarmed when it returns (disarmDoneAlert):
///   in the foreground the runner's own haptics + sound are the alert,
///   so there is never a double alert. The done alert is id 100, a
///   different id from the service's notification, so arming/disarming
///   it never touches the countdown.
/// * Exact alarms: SCHEDULE_EXACT_ALARM on Android 12+. Requested
///   once on the first rest; if denied, the done alert falls back to
///   inexact and Settings says so.
/// * POST_NOTIFICATIONS on Android 13+: the runner asks on the first
///   rest, with a one-line explanation first.
///
/// iOS:
/// * A Live Activity (lock screen + Dynamic Island) via the
///   live_activities plugin — needs the ForgeLiveActivity widget
///   extension target in Xcode (ios/LIVE_ACTIVITY_SETUP.md).
/// * A local notification at restEndsAt, default sound,
///   interruptionLevel timeSensitive. Permission is asked on the first
///   rest timer, not at startup.
class RestNotifyService {
  RestNotifyService._();

  static const int _restId = 100;

  /// The foreground service's notification id. Different from _restId
  /// on purpose: cancelling the done alert (id 100) must never touch
  /// the countdown, and the done alert firing must never replace it —
  /// the service is stopped explicitly when the rest ends.
  static const int _foregroundServiceId = 101;

  /// Notification-action ids for the countdown's +15s / Skip rest
  /// buttons (also read by the foreground task handler).
  static const String plus15ActionId = 'forge_rest_plus15';
  static const String skipActionId = 'forge_rest_skip';

  /// Vibration pattern for the rest-done alert.
  static const List<int> doneVibrationPattern = [0, 400, 200, 400, 200, 600];

  static const String _prefsKey = 'forge_rest_prefs';
  static const String _armedKey = 'forge_rest_done_armed';
  static const String _exactAskedKey = 'forge_exact_alarm_asked';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _tzReady = false;

  /// True while the rest-done alert is armed (app backgrounded).
  /// Mirrored to SharedPreferences so the background isolate and the
  /// runner's sync see the same value.
  static bool _doneArmed = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // iOS permission is asked on the first rest timer, not at
          // startup — see _ensureIosPermission.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      await _initTimezone();
    } catch (_) {
      // Notifications unavailable — the in-app timer still works.
    }
  }

  /// Configures the foreground service (Android only in effect; the
  /// iOS options are inert). Called once from main(), before any rest
  /// starts. The service itself is started per rest from startRest.
  static void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rest_timer',
        channelName: 'Rest timer',
        channelDescription: 'Rest countdown while you lift',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Tick every second: the handler re-posts the notification
        // with the live countdown, so a swipe-away lasts < 1s.
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowAutoRestart: true,
      ),
    );
  }

  static Future<void> _initTimezone() async {
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
      _tzReady = true;
    } catch (_) {
      _tzReady = false;
    }
  }

  // ------------------------------------------------------------ pure bits

  /// "M:SS" — the runner clock.
  static String format(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Ongoing notification text: "Rest — next: Set N".
  static String restBody(int nextSetIndex) =>
      'Rest — next: Set $nextSetIndex';

  /// Foreground-service notification text: the rest body plus the live
  /// countdown, e.g. "Rest — next: Set 2 · 2:34". The service's task
  /// handler rebuilds this every second from the stored restEndsAt.
  static String serviceText(int nextSetIndex, int remainingSec) =>
      '${restBody(nextSetIndex)} · ${format(remainingSec < 0 ? 0 : remainingSec)}';

  /// Rest-done title: "Rest over — Set N of <exercise>".
  static String doneTitle(String exerciseName, int nextSetIndex) =>
      'Rest over — Set $nextSetIndex of $exerciseName';

  /// Rest-done body.
  static String doneBody() => 'Your rest is over. Next set.';

  // ------------------------------------------------------------ prefs

  static Future<void> savePrefs(RestNotifyPrefs prefs) async {
    try {
      final store = await SharedPreferences.getInstance();
      await store.setString(_prefsKey, jsonEncode(prefs.toJson()));
    } catch (_) {}
  }

  static Future<RestNotifyPrefs> readPrefs() async {
    try {
      final store = await SharedPreferences.getInstance();
      final raw = store.getString(_prefsKey);
      if (raw == null) return const RestNotifyPrefs();
      return RestNotifyPrefs.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const RestNotifyPrefs();
    }
  }

  /// True while the done alert is armed (persisted — readable from the
  /// background isolate and the runner's sync).
  static Future<bool> isDoneArmed() async {
    try {
      final store = await SharedPreferences.getInstance();
      return store.getBool(_armedKey) ?? false;
    } catch (_) {
      return _doneArmed;
    }
  }

  static Future<void> _setDoneArmed(bool value) async {
    _doneArmed = value;
    try {
      final store = await SharedPreferences.getInstance();
      await store.setBool(_armedKey, value);
    } catch (_) {}
  }

  // ------------------------------------------------------------ exact alarms

  /// Whether exact alarms are currently allowed (Android 12+; always
  /// true below 12, where no permission exists).
  static Future<bool> canScheduleExact() async {
    if (!Platform.isAndroid) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks for the exact-alarm permission (Android 12+ opens the
  /// Alarms & reminders settings page). Returns whether it is allowed
  /// afterwards. Called at most once per install from startRest;
  /// Settings offers it again.
  static Future<bool> requestExactAlarms() async {
    if (!Platform.isAndroid) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestExactAlarmsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _ensureExactAlarms() async {
    if (!Platform.isAndroid) return false;
    if (await canScheduleExact()) return true;
    try {
      final store = await SharedPreferences.getInstance();
      if (store.getBool(_exactAskedKey) ?? false) return false;
      await store.setBool(_exactAskedKey, true);
    } catch (_) {}
    return requestExactAlarms();
  }

  // ------------------------------------------------------------ rest lifecycle

  /// Starts the rest displays: the ongoing countdown notification
  /// (Android), the Live Activity (iOS), and — on iOS — the permission
  /// prompt on the first rest. The done alert is NOT armed here; the
  /// runner arms it when the app goes to the background.
  static Future<void> startRest({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
    required RestNotifyPrefs prefs,
  }) async {
    await init();
    await savePrefs(prefs);
    if (!prefs.notifications) return;
    if (Platform.isIOS) {
      await _ensureIosPermission();
      await LiveActivityService.startRest(
        exerciseName: exerciseName,
        nextSetIndex: nextSetIndex,
        endsAt: endsAt,
      );
      return;
    }
    if (Platform.isAndroid) {
      if (!await _androidNotificationsAllowed()) return;
      await _ensureExactAlarms();
      await _startForegroundService(
        exerciseName: exerciseName,
        nextSetIndex: nextSetIndex,
        endsAt: endsAt,
      );
    }
  }

  /// +15s from the in-app button or the notification action: re-show
  /// the ongoing countdown with the new end, re-arm the done alert
  /// if it was armed, and update the Live Activity.
  static Future<void> extendRest({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
    required RestNotifyPrefs prefs,
  }) async {
    await applyRestUpdate(
      exerciseName: exerciseName,
      nextSetIndex: nextSetIndex,
      endsAt: endsAt,
      prefs: prefs,
    );
  }

  /// Re-applies the rest displays after a +15s (in-app or from the
  /// notification action in the background isolate).
  static Future<void> applyRestUpdate({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
    required RestNotifyPrefs prefs,
  }) async {
    await init();
    await savePrefs(prefs);
    if (!prefs.notifications) return;
    if (Platform.isIOS) {
      await LiveActivityService.updateRest(
        exerciseName: exerciseName,
        nextSetIndex: nextSetIndex,
        endsAt: endsAt,
      );
      if (await isDoneArmed()) {
        await _scheduleDone(
          exerciseName: exerciseName,
          nextSetIndex: nextSetIndex,
          endsAt: endsAt,
          prefs: prefs,
        );
      }
      return;
    }
    if (Platform.isAndroid) {
      if (!await _androidNotificationsAllowed()) return;
      await _updateForegroundService(
        exerciseName: exerciseName,
        nextSetIndex: nextSetIndex,
        endsAt: endsAt,
      );
      if (await isDoneArmed()) {
        await _scheduleDone(
          exerciseName: exerciseName,
          nextSetIndex: nextSetIndex,
          endsAt: endsAt,
          prefs: prefs,
        );
      }
    }
  }

  /// Arms the rest-done alert at restEndsAt. Called when the app goes
  /// to the background mid-rest; in the foreground the runner's own
  /// haptics + sound are the alert, so this is never armed there.
  static Future<void> armDoneAlert({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
    required RestNotifyPrefs prefs,
  }) async {
    await init();
    if (!prefs.notifications) return;
    if (endsAt.isBefore(DateTime.now())) return;
    await _scheduleDone(
      exerciseName: exerciseName,
      nextSetIndex: nextSetIndex,
      endsAt: endsAt,
      prefs: prefs,
    );
    await _setDoneArmed(true);
  }

  /// Disarms the rest-done alert (app returned to the foreground).
  /// Cancelling id 100 touches only the done alert — the countdown is
  /// the foreground service's own notification (id 101) and keeps
  /// running untouched.
  static Future<void> disarmDoneAlert({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
    required RestNotifyPrefs prefs,
  }) async {
    if (!await isDoneArmed()) return;
    await _setDoneArmed(false);
    try {
      await _plugin.cancel(_restId);
    } catch (_) {}
  }

  /// Cancels every rest display: the countdown service, any armed
  /// done alert, and the Live Activity. Called on Skip, finish and
  /// discard.
  static Future<void> cancelRest() async {
    await _setDoneArmed(false);
    try {
      await _plugin.cancel(_restId);
    } catch (_) {}
    await _stopForegroundService();
    await LiveActivityService.endRest();
  }

  // ------------------------------------------------------------ internals

  static Future<bool> _androidNotificationsAllowed() async {
    try {
      return (await Permission.notification.status).isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _ensureIosPermission() async {
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, sound: true);
    } catch (_) {}
  }

  // ------------------------------------------------------------ foreground service

  /// The countdown's buttons, shared by start and update.
  static const List<NotificationButton> _countdownButtons = [
    NotificationButton(id: plus15ActionId, text: '+15s'),
    NotificationButton(id: skipActionId, text: 'Skip rest'),
  ];

  /// Starts the rest countdown as a foreground service (or updates it
  /// if one is already running, e.g. the previous rest's service has
  /// not stopped yet). Silent failure leaves the in-app timer and the
  /// done alert as the cover.
  static Future<void> _startForegroundService({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
  }) async {
    try {
      final text = serviceText(
        nextSetIndex,
        endsAt.difference(DateTime.now()).inSeconds,
      );
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: exerciseName,
          notificationText: text,
          notificationButtons: _countdownButtons,
        );
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: _foregroundServiceId,
        serviceTypes: const [ForegroundServiceTypes.specialUse],
        notificationTitle: exerciseName,
        notificationText: text,
        notificationButtons: _countdownButtons,
        callback: startRestForegroundTask,
      );
    } catch (_) {
      // Service could not start — the in-app timer still works.
    }
  }

  /// Re-posts the countdown with a new end (+15s, in-app or from the
  /// notification). Starts the service if it is not running.
  static Future<void> _updateForegroundService({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
  }) async {
    try {
      final text = serviceText(
        nextSetIndex,
        endsAt.difference(DateTime.now()).inSeconds,
      );
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: exerciseName,
          notificationText: text,
          notificationButtons: _countdownButtons,
        );
      } else {
        await _startForegroundService(
          exerciseName: exerciseName,
          nextSetIndex: nextSetIndex,
          endsAt: endsAt,
        );
      }
    } catch (_) {}
  }

  /// Stops the countdown service (rest over, skipped, finished or
  /// discarded). A no-op when it is not running.
  static Future<void> _stopForegroundService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  /// Schedules the rest-done alert at endsAt on the rest_done channel.
  /// It reuses id 100, so when it fires it replaces (cancels) the
  /// ongoing countdown. Returns false when it could not be scheduled
  /// (timezone not ready) — the in-app timer still covers it.
  static Future<bool> _scheduleDone({
    required String exerciseName,
    required int nextSetIndex,
    required DateTime endsAt,
    required RestNotifyPrefs prefs,
  }) async {
    if (!_tzReady) return false;
    try {
      final exact = Platform.isAndroid ? await canScheduleExact() : true;
      await _plugin.zonedSchedule(
        _restId,
        doneTitle(exerciseName, nextSetIndex),
        doneBody(),
        tz.TZDateTime.from(endsAt, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            'rest_done',
            'Rest done',
            channelDescription: 'Buzzes when your rest is over',
            importance: Importance.high,
            priority: Priority.high,
            playSound: prefs.sound,
            enableVibration: prefs.vibrate,
            vibrationPattern:
                Int64List.fromList(doneVibrationPattern),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: prefs.sound,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Entry point for the foreground service's background isolate: hands
/// the countdown over to [RestForegroundTaskHandler]. Must stay a
/// top-level function.
@pragma('vm:entry-point')
void startRestForegroundTask() {
  FlutterForegroundTask.setTaskHandler(RestForegroundTaskHandler());
}

/// The foreground service's task: keeps the rest countdown posted
/// while the service runs.
///
/// * Every second it re-reads the stored session and re-posts the
///   notification with the live countdown — so if the user swipes the
///   notification away (Android 14+ allows that while unlocked) it
///   comes back within a second, and while the phone is locked it
///   cannot be swiped at all.
/// * +15s / Skip rest on the notification update the stored session
///   directly, without opening the app; the runner picks the change
///   up on its next sync.
/// * When the rest is over (or gone — finished, discarded, skipped
///   from the app) the service stops itself. The rest-done alert is a
///   separate scheduled notification and is untouched by this.
class RestForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // First tick comes from onRepeatEvent; nothing to do here.
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_tick());
  }

  Future<void> _tick() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await RestNotifyService.init();
      final session = await SessionStore().restore();
      final endsAt = session?.restEndsAt;
      if (session == null || endsAt == null) {
        await FlutterForegroundTask.stopService();
        return;
      }
      final remaining = endsAt.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        await FlutterForegroundTask.stopService();
        return;
      }
      final next = nextOpenSet(session);
      await FlutterForegroundTask.updateService(
        notificationTitle: next?.name ?? session.title,
        notificationText: RestNotifyService.serviceText(
          (next?.setIndex ?? 0) + 1,
          remaining,
        ),
      );
    } catch (_) {
      // Never crash the service isolate; the in-app timer and the
      // scheduled done alert still cover the rest.
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    unawaited(_onButton(id));
  }

  Future<void> _onButton(String id) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await RestNotifyService.init();
      final store = SessionStore();
      final session = await store.restore();
      if (session == null || session.restEndsAt == null) {
        await RestNotifyService.cancelRest();
        return;
      }
      final prefs = await RestNotifyService.readPrefs();
      if (id == RestNotifyService.plus15ActionId) {
        final endsAt = session.restEndsAt!.add(const Duration(seconds: 15));
        final total = (session.restTotalSec ?? 0) + 15;
        await store.save(
          session.copyWith(restEndsAt: endsAt, restTotalSec: total),
        );
        final next = nextOpenSet(session);
        await RestNotifyService.applyRestUpdate(
          exerciseName: next?.name ?? session.title,
          nextSetIndex: (next?.setIndex ?? 0) + 1,
          endsAt: endsAt,
          prefs: prefs,
        );
      } else if (id == RestNotifyService.skipActionId) {
        await store.save(session.copyWith(clearRest: true));
        await RestNotifyService.cancelRest();
      }
    } catch (_) {
      // Never crash the service isolate; the in-app timer is the
      // authority when the user returns to the app.
    }
  }

  @override
  void onNotificationDismissed() {
    // The user swiped the countdown away (Android 14+ allows it while
    // unlocked). The service is still running, so put it straight
    // back; the 1s tick re-posts it too.
    unawaited(_tick());
  }

  @override
  Future<void> onNotificationPressed() async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
