import 'package:flutter/foundation.dart';

import '../models/workout.dart';
import 'session_store.dart';

/// The live in-progress workout, shared between the app shell (mini
/// workout bar + center nav icon) and the screens.
///
/// The runner persists the session to [SessionStore] on every change, so
/// this is just a thin poller over that store: the shell refreshes it
/// once a second and the listeners rebuild (elapsed time and rest
/// countdown are computed from the wall clock, so they stay correct
/// even when the runner is closed or the app was backgrounded).
class ActiveSession {
  static final ValueNotifier<WorkoutSession?> current =
      ValueNotifier<WorkoutSession?>(null);

  static final _store = SessionStore();

  static Future<void> refresh() async {
    final session = await _store.restore();
    current.value = session;
  }
}

/// The next set still to do in [session], in flat order, or null when
/// every set is done or skipped.
SessionSet? nextOpenSet(WorkoutSession session) {
  for (final set in session.sets) {
    if (!set.completed && !set.skipped) return set;
  }
  return null;
}

/// Elapsed wall-clock time since the session started, as `MM:SS` or
/// `H:MM:SS` once it passes an hour.
String formatElapsed(DateTime startedAt, DateTime now) {
  final elapsed = now.difference(startedAt);
  final totalSeconds = elapsed.inSeconds.clamp(0, 359999);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final mmss =
      '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  if (hours == 0) return mmss;
  return '$hours:$mmss';
}

/// Remaining rest as `M:SS`, or null when [restEndsAt] is null or past.
/// Overtime returns `0:00` (the caller shows the amber state).
String? formatRestRemaining(DateTime? restEndsAt, DateTime now) {
  if (restEndsAt == null) return null;
  final remaining = restEndsAt.difference(now).inSeconds;
  if (remaining <= 0) return '0:00';
  final minutes = remaining ~/ 60;
  final seconds = remaining % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
