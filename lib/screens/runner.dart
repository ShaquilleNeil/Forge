import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import '../models/exercise.dart';
import '../models/program.dart';
import '../models/record.dart';
import '../models/user_profile.dart';
import '../models/workout.dart';
import '../services/active_session.dart';
import '../services/auth_service.dart';
import '../services/day_moves.dart';
import '../services/firestore_service.dart';
import '../services/rest_notify_service.dart';
import '../services/session_store.dart';
import '../services/sheet_import_service.dart';
import '../services/storage_service.dart';
import '../services/strength_math.dart';
import '../theme.dart';
import '../widgets/plate_calculator.dart';
import '../widgets/set_row.dart';
import 'exercise_library.dart';
import 'video_trim.dart';

/// One prescribed exercise plus the program day it came from. A
/// mixed session concatenates two days, so the day tag is what keeps
/// the same exercise in both days apart.
typedef DayExercise = ({String dayId, ProgramExercise exercise});

/// The order the lifter actually does the sets in.
///
/// Standalone exercises run in order; superset partners interleave
/// The pair key for a sheet superset label: the letter only. The
/// sheet labels the two halves "A1" and "A2" — the letter is the
/// pair, the number is the position in it — so both map to "A". A
/// bare "A" maps to itself. Pure, so it is unit-testable.
///
/// Cross-day link badges ("S1", "S2") pass through here too, for
/// the same reason: the two halves share the letter S and differ
/// only in position, so both map to "S". Two DIFFERENT pairs ("S"
/// and "T") stay different — stripping only the trailing digit
/// never merges them.
///
/// Without this, "A1" and "A2" were two different groups, so the
/// halves never paired: no interleave, no scroll to the partner,
/// and a rest after every set instead of after the round (Nov 19).
String supersetPairKey(String group) =>
    group.replaceFirst(RegExp(r'\d+$'), '');

/// round-robin (A1 set 1, A2 set 1, A1 set 2, A2 set 2, …). [groups]
/// is the runner's per-exercise groups (blockKey, name, set indices)
/// in day order — the key is each set's [SessionSet.blockKey], so the
/// same exercise in two mixed days is two groups; [supersetGroupOf]
/// maps blockKey to its superset group, or null when the exercise is
/// not in a superset. Pure, so it is unit-testable — the runner's
/// focus, scroll and "Up next" strip all read their next set from
/// this order.
List<int> supersetExecutionOrder(
  List<(String exerciseId, String name, List<int> indices)> groups,
  Map<String, String?> supersetGroupOf,
) {
  final order = <int>[];
  final placed = <String>{};
  for (final group in groups) {
    if (placed.contains(group.$1)) continue;
    final g = supersetGroupOf[group.$1];
    if (g == null || g.isEmpty) {
      order.addAll(group.$3);
      placed.add(group.$1);
      continue;
    }
    final partners = groups
        .where((gr) => supersetGroupOf[gr.$1] == g && !placed.contains(gr.$1))
        .toList();
    for (final p in partners) {
      placed.add(p.$1);
    }
    if (partners.length == 1) {
      order.addAll(partners.first.$3);
      continue;
    }
    var maxSets = 0;
    for (final p in partners) {
      if (p.$3.length > maxSets) maxSets = p.$3.length;
    }
    for (var s = 0; s < maxSets; s++) {
      for (final p in partners) {
        if (s < p.$3.length) order.add(p.$3[s]);
      }
    }
  }
  return order;
}

/// The sets for a copied day (Today's "Copy a day"): the day's
/// exercises, in order, one set per prescribed set, prefilled by
/// [prefillWeight]. Every set is tagged with the day's id, so the
/// superset groups and target RPEs resolve the same way they do for
/// a program day — but the session itself carries no program link,
/// so the copy never counts as the day and never writes back.
/// Pure, so it is unit-testable.
List<SessionSet> copySetsFor(
  ProgramDay day,
  double Function(ProgramExercise) prefillWeight,
) {
  final sets = <SessionSet>[];
  for (final ex in day.exercises) {
    final reps = ex.repsMin ?? ex.repsMax ?? 5;
    for (var i = 0; i < ex.sets; i++) {
      sets.add(SessionSet(
        exerciseId: ex.exerciseId,
        name: ex.name,
        setIndex: i,
        weightKg: prefillWeight(ex),
        reps: reps,
        dayId: day.id,
      ));
    }
  }
  return sets;
}

/// Whether logging the set at [completedIndex] should start a rest.
///
/// In a superset, no rest starts mid-round: when the next open set in
/// [order] is a superset partner of the completed set in the same
/// round (same setIndex), the lifter goes straight to the partner.
/// Every other case starts a rest — including the last exercise of a
/// round, a standalone set, and a partner whose same-round set is
/// already done or skipped. Pure, so it is unit-testable.
///
/// [supersetGroupOf] is keyed by each set's [SessionSet.blockKey],
/// so the same exercise in two mixed days never shares a superset.
bool shouldStartRestAfterSet({
  required List<int> order,
  required List<SessionSet> sets,
  required Map<String, String?> supersetGroupOf,
  required int completedIndex,
}) {
  final completed = sets[completedIndex];
  final group = supersetGroupOf[completed.blockKey];
  if (group == null || group.isEmpty) return true;
  final pos = order.indexOf(completedIndex);
  if (pos < 0) return true;
  for (var j = pos + 1; j < order.length; j++) {
    final next = sets[order[j]];
    if (next.completed || next.skipped) continue;
    final nextGroup = supersetGroupOf[next.blockKey];
    if (nextGroup == group && next.setIndex == completed.setIndex) {
      return false;
    }
    return true;
  }
  return true;
}

/// Pair letters for cross-day links: S, T, … Z, AA, AB, … — starting
/// at S so they never collide with the sheet's A/B/C pairs. Pure, so
/// it is unit-testable.
String linkPairLetter(int index) {
  if (index < 8) return String.fromCharCode('S'.codeUnitAt(0) + index);
  final n = index - 8;
  return '${String.fromCharCode('A'.codeUnitAt(0) + n ~/ 26)}'
      '${String.fromCharCode('A'.codeUnitAt(0) + n % 26)}';
}

/// Links two exercises (by blockKey — "dayId|exerciseId") as a
/// cross-day superset pair, for a mixed workout. Returns the new
/// links map: blockKey -> badge ("S1", "S2", "T1", ...).
///
/// The pair shares a LETTER; the number is the position in it, in
/// the order you do them: [a] — the exercise whose link icon was
/// tapped — is 1, [b] — the one picked from the sheet — is 2. So
/// bench linked to squat reads "S1" on bench and "S2" on squat: do
/// bench first, then move straight to squat. The same rule as the
/// sheet's A1/A2 (Nov 19).
///
/// An exercise has at most one partner: any pair either side is
/// already in is removed first, so linking an exercise pulls it out
/// of its old pair (and out of its same-day sheet superset — the
/// link wins). Linking an exercise to itself is a no-op. Pure, so
/// it is unit-testable.
Map<String, String> linkCrossDay(
  Map<String, String> links,
  String a,
  String b,
) {
  if (a == b) return Map<String, String>.from(links);
  final next = Map<String, String>.from(links);
  // Free both sides from any old pair: remove by pair LETTER, since
  // the two halves now carry different badges ("S1" / "S2").
  for (final key in [a, b]) {
    final old = next[key];
    if (old != null) {
      final letter = supersetPairKey(old);
      next.removeWhere((_, value) => supersetPairKey(value) == letter);
    }
  }
  final used = next.values.map(supersetPairKey).toSet();
  var i = 0;
  var letter = linkPairLetter(i);
  while (used.contains(letter)) {
    letter = linkPairLetter(++i);
  }
  next[a] = '${letter}1';
  next[b] = '${letter}2';
  return next;
}

/// Removes the cross-day pair the exercise at [blockKey] is in, if
/// any — both sides. The two halves carry different badges ("S1" /
/// "S2"), so the pair is found by its shared letter. Pure, so it is
/// unit-testable.
Map<String, String> unlinkCrossDay(
  Map<String, String> links,
  String blockKey,
) {
  final id = links[blockKey];
  if (id == null) return Map<String, String>.from(links);
  final letter = supersetPairKey(id);
  return Map<String, String>.from(links)
    ..removeWhere((_, value) => supersetPairKey(value) == letter);
}

/// Typed-in numbers: "170" for 170.0, "137.5" for 137.5 — no units,
/// no trailing zeros. Pure, so it is unit-testable.
String formatNumberInput(double value) {
  final s = value.toStringAsFixed(2);
  return s.replaceAll(RegExp(r'\.?0+$'), '');
}

/// Parses a typed weight: digits with an optional decimal, clamped to
/// the 0–500 kg the steppers allow. Null when it is not a number.
double? parseWeightInput(String text) {
  final parsed = double.tryParse(text.trim());
  if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
  return parsed.clamp(0.0, 500.0);
}

/// Parses typed reps: a whole number, clamped to 1–99. Null when it
/// is not a number.
int? parseRepsInput(String text) {
  final parsed = int.tryParse(text.trim());
  if (parsed == null) return null;
  return parsed.clamp(1, 99);
}

/// The workout runner — the heart of Forge. One-handed use: big tap
/// targets, steppers instead of keyboards mid-set.
///
/// Entry: route arguments may carry `programId` / `weekId` / `dayId`
/// (from Today) or a `day` ([ProgramDay]) directly. With no arguments
/// (or no matching day) a picker offers a program day or a free workout.
/// A crashed session is resumed from [SessionStore] on launch.
class RunnerScreen extends StatefulWidget {
  const RunnerScreen({super.key});

  @override
  State<RunnerScreen> createState() => _RunnerScreenState();
}

class _RunnerScreenState extends State<RunnerScreen>
    with WidgetsBindingObserver {
  final _firestore = FirestoreService();
  final _auth = AuthService();
  final _importer = SheetImportService();
  final _store = SessionStore();
  final _storage = StorageService();
  final _picker = ImagePicker();

  UserProfile? _profile;
  List<WorkoutSession> _pastWorkouts = [];
  Map<String, Record> _records = {};
  Map<String, double> _lastWeight = {};
  List<Program> _programs = [];

  WorkoutSession? _session;
  /// The program-day prescription for this session, as day-tagged
  /// exercises: one entry per prescribed exercise, in day order. A
  /// mixed session concatenates two days; the day tag is what keeps
  /// targets, superset groups and badges per day. Null for free
  /// workouts.
  List<DayExercise>? _dayExercises;
  DateTime? _startTime;

  bool _loading = true;
  bool _showPicker = false;
  String? _error;

  bool _finishing = false;
  String _uploadLabel = '';
  double _uploadProgress = 0;

  Timer? _ticker;
  int _elapsedSec = 0;

  /// Workout-timer pause: the elapsed clock stops while paused, and
  /// paused seconds are excluded from the recorded duration at finish.
  /// The rest timer is independent and keeps its own pause.
  bool _timerPaused = false;
  int _pausedTotalSec = 0;
  DateTime? _pauseStartedAt;

  // Rest timer.
  int _restRemainingSec = 0;
  // The rest this countdown started with — the draining bar's full
  // length. +15s extends it too, so the bar never jumps.
  int _restTotalSec = 0;
  bool _restActive = false;
  bool _restDone = false;
  // When the rest hit 0:00. The "Go" strip stays green for a minute,
  // then turns amber — the lifter is overtime.
  DateTime? _restDoneAt;
  // The 0:10 light haptic fires once per rest.
  bool _warnedAt10 = false;
  // Whether the rest-done alert is armed (app backgrounded). Mirrors
  // RestNotifyService's persisted flag, including arms done by the
  // background notification-action handler.
  bool _doneArmed = false;
  // Last time the runner re-read the stored session for rest changes
  // made outside the app (the notification's +15s / Skip actions).
  DateTime? _lastRestSyncAt;

  /// "exerciseId:setIndex" -> measured video length in seconds.
  final Map<String, double> _videoDurations = {};

  /// Exercise ids selected in the free-workout picker.
  final Set<String> _freeSelected = {};

  /// Exercise card keys, for scrolling the next incomplete card into view.
  final Map<String, GlobalKey> _exerciseCardKeys = {};

  /// The runner list's controller: the scroll to the next set is
  /// driven off the card's measured position (Nov 19) — the
  /// framework's ensureVisible never moved the list on the phone,
  /// with the order and the target both proven right.
  final ScrollController _scrollController = ScrollController();

  /// The runner list itself, for measuring the viewport's top edge
  /// when scrolling to a card.
  final GlobalKey _listKey = GlobalKey();

  static const _speeds = ['Fast', 'Normal', 'Slow', 'Grind'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ModalRoute is only readable after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _init();
      // Open on the first card that still has an open set.
      _advanceFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _ticker?.cancel();
    unawaited(RestNotifyService.cancelRest());
    super.dispose();
  }

  /// Backgrounding arms the rest-done alert; returning to the app
  /// disarms it (the runner's own haptics + sound are the alert in
  /// the foreground, so there is never a double alert) and re-syncs
  /// the rest from the stored session.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = _session;
    if (session == null || session.restEndsAt == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      if (!_restActive) return;
      _doneArmed = true;
      unawaited(RestNotifyService.armDoneAlert(
        exerciseName: _restExerciseName(),
        nextSetIndex: _restNextSetIndex(),
        endsAt: session.restEndsAt!,
        prefs: _restPrefs(),
      ));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resumeFromBackground());
    }
  }

  /// On return to the foreground: pick up any rest change made from
  /// the notification (+15s / Skip while the app was away), then
  /// disarm the done alert if a rest is still running.
  Future<void> _resumeFromBackground() async {
    await _syncRestFromStore();
    final session = _session;
    if (session == null || session.restEndsAt == null || !_restActive) {
      return;
    }
    _doneArmed = false;
    await RestNotifyService.disarmDoneAlert(
      exerciseName: _restExerciseName(),
      nextSetIndex: _restNextSetIndex(),
      endsAt: session.restEndsAt!,
      prefs: _restPrefs(),
    );
  }

  // ---------------------------------------------------------------- init

  Future<void> _init() async {
    // Read route arguments before any await (context use after async
    // gaps needs a mounted guard; this keeps it synchronous).
    final args = ModalRoute.of(context)?.settings.arguments;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'You need to sign in to start a workout.';
      });
      return;
    }
    try {
      final results = await Future.wait([
        _firestore.getProfile(uid),
        _firestore.getWorkouts(uid, limit: 50),
        _firestore.getRecords(uid),
        _firestore.getPrograms(uid),
      ]);
      _profile = results[0] as UserProfile?;
      _pastWorkouts = results[1] as List<WorkoutSession>;
      _records = results[2] as Map<String, Record>;
      _programs = results[3] as List<Program>;
      _computeLastWeights();

      // 1. Crash-safe resume wins over everything else.
      final restored = await _store.restore();
      if (restored != null &&
          restored.status == 'inProgress' &&
          restored.sets.isNotEmpty) {
        _session = restored;
        _startTime = restored.date;
        _elapsedSec =
            DateTime.now().difference(restored.date).inSeconds.clamp(0, 1 << 31);
        _resetTimerPause();
        await _rehydrateDay(restored);
        _startTicker();
        await _resumeRestFromSession(restored);
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resumed your saved workout.')),
        );
        return;
      }

      // 2. Program days from route arguments (read at the top of _init).
      // `dayKeys` (from Today) starts one or more days as a single
      // session — a mixed session when a moved day joins the day
      // scheduled on the date. `day` / programId+weekId+dayId start
      // one day, the pre-moves path.
      if (args is Map) {
        final dayKeys = args['dayKeys'];
        if (dayKeys is List && dayKeys.isNotEmpty) {
          final programId = args['programId'] as String?;
          final slots = <({ProgramWeek week, ProgramDay day})>[];
          for (final key in dayKeys) {
            final parsed = parseDayKey(key.toString());
            if (parsed == null) continue;
            final found = _findDayWithWeek(
              programId,
              parsed.weekId,
              parsed.dayId,
            );
            if (found != null) slots.add(found);
          }
          if (slots.isNotEmpty) {
            _startFromDays(slots, programId: programId);
            setState(() => _loading = false);
            return;
          }
        }
        // A copied day (from Today's "Copy a day") starts the day's
        // exercises as a standalone workout: no program link, so the
        // original day stays scheduled and uncompleted and nothing
        // writes back to the sheet.
        if (args['copy'] == true) {
          final copyDay = args['day'] as ProgramDay?;
          if (copyDay != null) {
            _startCopy(copyDay);
            setState(() => _loading = false);
            return;
          }
        }
        final day = args['day'] as ProgramDay?;
        final programId = args['programId'] as String?;
        final weekId = args['weekId'] as String?;
        final dayId = args['dayId'] as String?;
        final found = day ?? _findDay(programId, weekId, dayId);
        if (found != null) {
          _startFromDay(
            found,
            programId: programId,
            weekId: weekId,
            dayId: dayId ?? found.id,
          );
          setState(() => _loading = false);
          return;
        }
      }

      // 3. No day given — show the picker.
      setState(() {
        _loading = false;
        _showPicker = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your workout. $e';
      });
    }
  }

  ProgramDay? _findDay(String? programId, String? weekId, String? dayId) {
    return _findDayWithWeek(programId, weekId, dayId)?.day;
  }

  /// The week + day for a program/day/week id triple. Null when any
  /// id is missing or the day is not in the loaded programs.
  ({ProgramWeek week, ProgramDay day})? _findDayWithWeek(
    String? programId,
    String? weekId,
    String? dayId,
  ) {
    if (dayId == null) return null;
    for (final program in _programs) {
      if (programId != null && program.id != programId) continue;
      for (final week in program.weeks) {
        if (weekId != null && week.id != weekId) continue;
        for (final day in week.days) {
          if (day.id == dayId) return (week: week, day: day);
        }
      }
    }
    return null;
  }

  /// After a crash-resume, recover the program-day prescription (for
  /// superset badges / targets) from the ids stored on the session —
  /// every day the session covers, primary plus mixed-in.
  Future<void> _rehydrateDay(WorkoutSession session) async {
    final pairs = <DayExercise>[];
    for (final key in session.coveredDayKeys) {
      final parsed = parseDayKey(key);
      if (parsed == null) continue;
      final found = _findDayWithWeek(
        session.programId,
        parsed.weekId,
        parsed.dayId,
      );
      if (found == null) continue;
      for (final ex in found.day.exercises) {
        pairs.add((dayId: found.day.id, exercise: ex));
      }
    }
    if (pairs.isNotEmpty) _dayExercises = pairs;
  }

  void _computeLastWeights() {
    final sorted = List<WorkoutSession>.from(_pastWorkouts)
      ..sort((a, b) => b.date.compareTo(a.date));
    _lastWeight = {};
    for (final session in sorted) {
      for (final set in session.sets) {
        if (!set.completed) continue;
        _lastWeight.putIfAbsent(set.exerciseId, () => set.weightKg);
      }
    }
  }

  // ------------------------------------------------------- session build

  /// Target RPE for a set, from its own program day's prescription —
  /// the set's day tag is what picks the right day when the same
  /// exercise appears in two mixed days. Null for free workouts /
  /// exercises without a target. Sets saved before moves existed
  /// carry no day tag and fall back to the exercise alone.
  double? _targetRpeFor(SessionSet set) {
    final pairs = _dayExercises ?? const <DayExercise>[];
    for (final pair in pairs) {
      if (pair.dayId == set.dayId &&
          pair.exercise.exerciseId == set.exerciseId) {
        return double.tryParse(pair.exercise.targetRpe ?? '');
      }
    }
    for (final pair in pairs) {
      if (pair.exercise.exerciseId == set.exerciseId) {
        return double.tryParse(pair.exercise.targetRpe ?? '');
      }
    }
    return null;
  }

  double _prefillWeight(ProgramExercise ex) {
    if (ex.targetWeightKg != null) {
      return StrengthMath.roundToIncrement(ex.targetWeightKg!, 2.5);
    }
    if (ex.percentOf1rm != null) {
      final oneRm = _profile?.mainLifts[ex.exerciseId];
      if (oneRm != null) {
        // Accept both 0.52 and 52 style values.
        final pct = ex.percentOf1rm! > 1.5
            ? ex.percentOf1rm! / 100
            : ex.percentOf1rm!;
        return StrengthMath.roundToIncrement(oneRm * pct, 2.5);
      }
    }
    return _lastWeight[ex.exerciseId] ?? 0;
  }

  void _startFromDay(
    ProgramDay day, {
    String? programId,
    String? weekId,
    String? dayId,
  }) {
    final found = _findDayWithWeek(programId, weekId, dayId ?? day.id);
    if (found != null) {
      _startFromDays([found], programId: programId);
      return;
    }
    // A day passed directly, not in the loaded programs: start it
    // standalone, with the week id the caller gave.
    _startFromDays(
      [(week: ProgramWeek(id: weekId ?? '', title: ''), day: day)],
      programId: programId,
    );
  }

  /// Starts a session from one or more program days, in order. A
  /// mixed session passes the moved-in day(s) first, then the day
  /// scheduled on the date — the scheduled (host) day is primary,
  /// the moved-in days ride in [WorkoutSession.mixedDayKeys]. Every
  /// set is tagged with the day it came from, so the sheet
  /// write-back routes each day's sets to its own rows.
  void _startFromDays(
    List<({ProgramWeek week, ProgramDay day})> days, {
    String? programId,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || days.isEmpty) return;
    final sets = <SessionSet>[];
    final pairs = <DayExercise>[];
    for (final slot in days) {
      for (final ex in slot.day.exercises) {
        pairs.add((dayId: slot.day.id, exercise: ex));
        final reps = ex.repsMin ?? ex.repsMax ?? 5;
        final weight = _prefillWeight(ex);
        for (var i = 0; i < ex.sets; i++) {
          sets.add(SessionSet(
            exerciseId: ex.exerciseId,
            name: ex.name,
            setIndex: i,
            weightKg: weight,
            reps: reps,
            dayId: slot.day.id,
          ));
        }
      }
    }
    final host = days.last;
    _session = WorkoutSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userId: uid,
      date: DateTime.now(),
      programId: programId,
      weekId: host.week.id,
      dayId: host.day.id,
      title: days.map((s) => stripDatePrefix(s.day.title)).join(' + '),
      status: 'inProgress',
      sets: sets,
      mixedDayKeys: [
        for (final slot in days.sublist(0, days.length - 1))
          dayKey(slot.week.id, slot.day.id),
      ],
    );
    _dayExercises = pairs;
    _startTime = DateTime.now();
    _elapsedSec = 0;
    _resetTimerPause();
    _startTicker();
    unawaited(_store.save(_session!));
  }

  /// Starts a copied day as a standalone workout: the day's
  /// exercises, prefilled, with no program link — the original day
  /// stays scheduled and uncompleted, and nothing writes back to
  /// the sheet. The title says "(copy)" so the session is obvious
  /// in History.
  void _startCopy(ProgramDay day) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _session = WorkoutSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userId: uid,
      date: DateTime.now(),
      title: '${stripDatePrefix(day.title)} (copy)',
      status: 'inProgress',
      sets: copySetsFor(day, _prefillWeight),
    );
    _dayExercises = [
      for (final ex in day.exercises) (dayId: day.id, exercise: ex),
    ];
    _startTime = DateTime.now();
    _elapsedSec = 0;
    _resetTimerPause();
    _startTicker();
    unawaited(_store.save(_session!));
  }

  void _startFreeWorkout(List<Exercise> exercises) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || exercises.isEmpty) return;
    final sets = <SessionSet>[];
    for (final ex in exercises) {
      final weight = _lastWeight[ex.id] ?? 0;
      for (var i = 0; i < 3; i++) {
        sets.add(SessionSet(
          exerciseId: ex.id,
          name: ex.name,
          setIndex: i,
          weightKg: weight,
          reps: 5,
        ));
      }
    }
    _session = WorkoutSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      userId: uid,
      date: DateTime.now(),
      title: 'Free workout',
      status: 'inProgress',
      sets: sets,
    );
    _dayExercises = null;
    _startTime = DateTime.now();
    _elapsedSec = 0;
    _resetTimerPause();
    _startTicker();
    unawaited(_store.save(_session!));
    setState(() => _showPicker = false);
  }

  void _addExercises(List<Exercise> exercises) {
    final session = _session;
    if (session == null || exercises.isEmpty) return;
    final sets = List<SessionSet>.from(session.sets);
    for (final ex in exercises) {
      if (sets.any((s) => s.exerciseId == ex.id)) continue;
      final weight = _lastWeight[ex.id] ?? 0;
      for (var i = 0; i < 3; i++) {
        sets.add(SessionSet(
          exerciseId: ex.id,
          name: ex.name,
          setIndex: i,
          weightKg: weight,
          reps: 5,
        ));
      }
    }
    _session = session.copyWith(sets: sets);
    unawaited(_store.save(_session!));
    setState(() {});
  }

  // ------------------------------------------------------------- ticker

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // The notification's +15s / Skip actions update the stored
      // session without opening the app — pick them up every few
      // seconds so the strip, the bar and the Live Activity agree.
      final now = DateTime.now();
      if (_lastRestSyncAt == null ||
          now.difference(_lastRestSyncAt!).inSeconds >= 5) {
        _lastRestSyncAt = now;
        unawaited(_syncRestFromStore());
      }
      setState(() {
        if (!_timerPaused) _elapsedSec++;
        if (!_restActive) return;
        final endsAt = _session?.restEndsAt;
        if (endsAt == null) {
          _restActive = false;
          return;
        }
        // The rest is a wall-clock instant, not a counter: remaining
        // is always endsAt − now, so +15s from the notification, a
        // backgrounded app and an app restart all stay in sync.
        final remaining = endsAt.difference(DateTime.now()).inSeconds;
        if (remaining == 10 && !_warnedAt10) {
          _warnedAt10 = true;
          unawaited(HapticFeedback.lightImpact());
        }
        if (remaining <= 2 && _doneArmed) {
          // Belt and braces: a done alert armed by the background
          // handler (the user tapped +15s in the shade while the app
          // was open) must not fire — the in-app alert is the only
          // one in the foreground.
          _doneArmed = false;
          unawaited(RestNotifyService.disarmDoneAlert(
            exerciseName: _restExerciseName(),
            nextSetIndex: _restNextSetIndex(),
            endsAt: endsAt,
            prefs: _restPrefs(),
          ));
        }
        if (remaining <= 0) {
          _restOver();
        } else {
          _restRemainingSec = remaining;
        }
      });
    });
  }

  /// The rest hit 0:00 in the foreground: the in-app alert only —
  /// heavy haptics + an optional short sound — and the system
  /// displays go away. No system notification is shown, so there is
  /// never a double alert.
  void _restOver() {
    _restActive = false;
    _restDone = true;
    _restDoneAt = DateTime.now();
    _warnedAt10 = false;
    _doneArmed = false;
    final prefs = _restPrefs();
    if (prefs.vibrate) {
      unawaited(_restDoneHaptics());
    }
    if (prefs.sound) {
      unawaited(_restDoneSound());
    }
    unawaited(RestNotifyService.cancelRest());
    // The rest is over — clear it from the persisted session so the
    // mini bar stops showing a countdown and a restart does not
    // resume a finished rest.
    final session = _session;
    if (session != null && session.restEndsAt != null) {
      _session = session.copyWith(clearRest: true);
      unawaited(_store.save(_session!));
    }
  }

  /// Heavy haptic pattern for the rest-done alert.
  Future<void> _restDoneHaptics() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await HapticFeedback.heavyImpact();
  }

  /// Short alert sound for the rest-done alert (best effort — the
  /// platform may not play it).
  Future<void> _restDoneSound() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  /// Pauses or resumes the workout timer. Paused seconds are tracked
  /// so the recorded duration at finish excludes them.
  void _toggleTimerPause() {
    setState(() {
      if (_timerPaused) {
        if (_pauseStartedAt != null) {
          _pausedTotalSec +=
              DateTime.now().difference(_pauseStartedAt!).inSeconds;
        }
        _pauseStartedAt = null;
        _timerPaused = false;
      } else {
        _timerPaused = true;
        _pauseStartedAt = DateTime.now();
      }
    });
  }

  int _pausedSeconds() {
    var total = _pausedTotalSec;
    if (_timerPaused && _pauseStartedAt != null) {
      total += DateTime.now().difference(_pauseStartedAt!).inSeconds;
    }
    return total;
  }

  void _resetTimerPause() {
    _timerPaused = false;
    _pausedTotalSec = 0;
    _pauseStartedAt = null;
  }

  void _startRestFor(SessionSet set) {
    // A superset set rests on the superset timer (after the round).
    // Otherwise mains are the three built-in lifts — but imported
    // programs use variations ("Squat, beltless", "Comp bench"), whose
    // ids never match the built-ins, so the name is checked too. An
    // unknown exercise defaults to accessory rest.
    //
    // The lookup is by blockKey, not exerciseId: the group map is
    // keyed by blockKey, so looking it up by exerciseId missed every
    // program superset and the superset timer never fired (Nov 19).
    final supersetGroup = _supersetGroupOf[set.blockKey];
    final int seconds;
    if (supersetGroup != null && supersetGroup.isNotEmpty) {
      seconds = _profile?.restSupersetSec ?? 180;
    } else {
      final builtIn = BuiltInExercises.all.firstWhere(
        (e) => e.id == set.exerciseId,
        orElse: () => const Exercise(id: '', name: ''),
      );
      final isMain = builtIn.id.isNotEmpty
          ? builtIn.isMain
          : Exercise.nameIsMain(set.name);
      // Rest defaults live on the profile (editable in Settings):
      // 3:00 for mains, 1:30 for accessories.
      seconds = isMain
          ? (_profile?.restMainSec ?? 180)
          : (_profile?.restAccessorySec ?? 90);
    }
    // The rest is a wall-clock instant stored on the session — the
    // strip, the mini bar, the notification chronometer and the Live
    // Activity all derive remaining time from it, so it survives
    // backgrounding, screen lock and app restart.
    final endsAt = DateTime.now().add(Duration(seconds: seconds));
    final session = _session;
    if (session != null) {
      _session = session.copyWith(restEndsAt: endsAt, restTotalSec: seconds);
      unawaited(_store.save(_session!));
    }
    setState(() {
      _restRemainingSec = seconds;
      _restTotalSec = seconds;
      _restActive = true;
      _restDone = false;
      _restDoneAt = null;
      _warnedAt10 = false;
    });
    // Android 13+ asks for the notification permission the first
    // time a rest starts, with a one-line explanation first.
    unawaited(_startRestDisplays(endsAt));
  }

  /// Asks for the notification permission (Android) and starts the
  /// rest displays: the ongoing countdown notification / Live
  /// Activity. The done alert is armed only when the app goes to the
  /// background.
  Future<void> _startRestDisplays(DateTime endsAt) async {
    if (Platform.isAndroid) {
      await _ensureRestPermission();
    }
    await RestNotifyService.startRest(
      exerciseName: _restExerciseName(),
      nextSetIndex: _restNextSetIndex(),
      endsAt: endsAt,
      prefs: _restPrefs(),
    );
  }

  /// One-line explanation, then the system prompt — only when the
  /// permission is still undecided. A denial just means no system
  /// displays; the in-app timer and haptics still work.
  Future<void> _ensureRestPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted || status.isPermanentlyDenied) return;
    if (!mounted) return;
    final allow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rest notifications'),
        content: const Text(
          'Forge shows your rest countdown in the notification shade '
          'and buzzes when it\'s over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (allow == true) {
      await Permission.notification.request();
    }
  }

  /// Rest-timer alert toggles from the profile (Settings → Rest timer).
  /// No profile yet (fresh sign-in) means all three on.
  RestNotifyPrefs _restPrefs() {
    final profile = _profile;
    if (profile == null) return const RestNotifyPrefs();
    return RestNotifyPrefs.fromProfile(profile);
  }

  /// The exercise the current rest belongs to: the next open set's
  /// exercise, or the session title when every set is logged.
  String _restExerciseName() {
    final session = _session;
    if (session == null) return '';
    return nextOpenSet(session)?.name ?? session.title;
  }

  /// The next set number (1-based) the rest is counting down to.
  int _restNextSetIndex() {
    final session = _session;
    if (session == null) return 1;
    return (nextOpenSet(session)?.setIndex ?? 0) + 1;
  }

  /// Re-reads the stored session and adopts any rest change made
  /// outside the app — the notification's +15s / Skip actions, or a
  /// rest that ended while the app was away.
  Future<void> _syncRestFromStore() async {
    if (!mounted) return;
    final stored = await _store.restore();
    final session = _session;
    if (stored == null || session == null || stored.id != session.id) {
      return;
    }
    final storedEndsAt = stored.restEndsAt;
    final currentEndsAt = session.restEndsAt;
    // Same instant (within a second — the ISO round-trip can lose
    // sub-second precision) and same total: nothing changed.
    final sameEnd = storedEndsAt == null && currentEndsAt == null ||
        storedEndsAt != null &&
            currentEndsAt != null &&
            storedEndsAt.difference(currentEndsAt).inSeconds.abs() < 1;
    if (sameEnd && stored.restTotalSec == session.restTotalSec) {
      return;
    }
    if (storedEndsAt == null) {
      // Skipped from the notification (or cleared elsewhere).
      _clearRest();
      return;
    }
    final remaining = storedEndsAt.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _restOver();
      return;
    }
    _session = session.copyWith(
      restEndsAt: storedEndsAt,
      restTotalSec: stored.restTotalSec,
    );
    if (!mounted) return;
    setState(() {
      _restRemainingSec = remaining;
      _restTotalSec = stored.restTotalSec ?? remaining;
      _restActive = true;
      _restDone = false;
      _restDoneAt = null;
      _warnedAt10 = remaining <= 10;
    });
    unawaited(RestNotifyService.extendRest(
      exerciseName: _restExerciseName(),
      nextSetIndex: _restNextSetIndex(),
      endsAt: storedEndsAt,
      prefs: _restPrefs(),
    ));
  }

  /// After a crash-safe restore (or a fresh app start mid-rest): pick
  /// the rest up from the persisted restEndsAt. A rest already in the
  /// past shows the "Go" strip; a live one resumes its countdown and
  /// its system displays.
  Future<void> _resumeRestFromSession(WorkoutSession restored) async {
    final endsAt = restored.restEndsAt;
    if (endsAt == null || !mounted) return;
    final remaining = endsAt.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      setState(() {
        _restActive = false;
        _restDone = true;
        _restDoneAt = endsAt;
      });
      return;
    }
    setState(() {
      _restRemainingSec = remaining;
      _restTotalSec = restored.restTotalSec ?? remaining;
      _restActive = true;
      _restDone = false;
      _restDoneAt = null;
      _warnedAt10 = remaining <= 10;
    });
    // The notification / Live Activity may have been dismissed while
    // the app was away — re-show them from the stored end.
    unawaited(RestNotifyService.startRest(
      exerciseName: _restExerciseName(),
      nextSetIndex: _restNextSetIndex(),
      endsAt: endsAt,
      prefs: _restPrefs(),
    ));
  }

  void _clearRest() {
    final session = _session;
    if (session != null && session.restEndsAt != null) {
      _session = session.copyWith(clearRest: true);
      unawaited(_store.save(_session!));
    }
    unawaited(RestNotifyService.cancelRest());
    setState(() {
      _restActive = false;
      _restDone = false;
      _restRemainingSec = 0;
      _restTotalSec = 0;
      _restDoneAt = null;
      _warnedAt10 = false;
      _doneArmed = false;
    });
  }

  // ---------------------------------------------------------- set edits

  void _updateSet(int index, SessionSet Function(SessionSet) change) {
    final session = _session;
    if (session == null) return;
    final sets = List<SessionSet>.from(session.sets);
    sets[index] = change(sets[index]);
    _session = session.copyWith(sets: sets);
    unawaited(_store.save(_session!));
    setState(() {});
  }

  void _completeSet(int index) {
    final session = _session;
    if (session == null) return;
    final set = session.sets[index];
    if (set.completed) return;
    // TEMP (Nov 19): diagnose the scroll that never moves on the
    // phone. Remove once the cause is found.
    debugPrint('SCROLL: _completeSet index=$index (${set.name})');
    // Light haptic with the check animation — the set is logged.
    unawaited(HapticFeedback.lightImpact());
    _updateSet(index, (s) => s.copyWith(completed: true, skipped: false));
    // A superset rests after the round, not between the two exercises:
    // no timer when the partner's same-round set is still open.
    if (shouldStartRestAfterSet(
      order: _executionOrder,
      sets: session.sets,
      supersetGroupOf: _supersetGroupOf,
      completedIndex: index,
    )) {
      _startRestFor(set);
    }
    _advanceFocus();
  }

  void _skipSet(int index) {
    final session = _session;
    if (session == null) return;
    final set = session.sets[index];
    if (set.completed || set.skipped) return;
    _updateSet(index, (s) => s.copyWith(skipped: true));
    _advanceFocus();
  }

  /// After Done/Skip, move focus to the next card with an open set.
  void _advanceFocus() {
    // TEMP (Nov 19): diagnose the scroll that never moves on the
    // phone. Remove once the cause is found.
    debugPrint('SCROLL: _advanceFocus scheduled');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToFirstIncomplete();
    });
  }

  /// Scrolls the exercise card holding the first open set in
  /// execution order into view — after a superset set, that is the
  /// partner's card, not the same card again. The scroll is driven
  /// off the card's measured position through the list's controller:
  /// the card top lands 10% down the viewport, the same landing
  /// spot ensureVisible used — but ensureVisible never moved the
  /// list on the phone even with the order and the target both
  /// proven right (Nov 19), so the reveal math is bypassed
  /// entirely. A missing card context still scrolls nowhere, and
  /// says nothing — the only silent failure left is a card that
  /// was never built.
  void _scrollToFirstIncomplete() {
    // TEMP (Nov 19): diagnose the scroll that never moves on the
    // phone. Remove once the cause is found.
    debugPrint('SCROLL: _scrollToFirstIncomplete called');
    final session = _session;
    if (session == null) {
      debugPrint('SCROLL: no session');
      return;
    }
    if (!_scrollController.hasClients) {
      debugPrint('SCROLL: controller has no clients');
      return;
    }
    for (final i in _executionOrder) {
      final set = session.sets[i];
      if (set.completed || set.skipped) continue;
      debugPrint(
        'SCROLL: first open set is ${set.name} blockKey=${set.blockKey}',
      );
      final context = _exerciseCardKeys[set.blockKey]?.currentContext;
      final box = context?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) {
        debugPrint(
          'SCROLL: card box null or detached (context null: ${context == null})',
        );
        return;
      }
      final position = _scrollController.position;
      final viewportBox =
          _listKey.currentContext?.findRenderObject() as RenderBox?;
      if (viewportBox == null || !viewportBox.attached) {
        debugPrint('SCROLL: viewport box null or detached');
        return;
      }
      final cardTop = box.localToGlobal(Offset.zero).dy;
      final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
      final target = (position.pixels +
              (cardTop - viewportTop) -
              position.viewportDimension * 0.1)
          .clamp(0.0, position.maxScrollExtent);
      debugPrint(
        'SCROLL: pixels=${position.pixels} cardTop=$cardTop '
        'viewportTop=$viewportTop viewportDim=${position.viewportDimension} '
        'maxExtent=${position.maxScrollExtent} target=$target',
      );
      if ((target - position.pixels).abs() < 1) {
        debugPrint('SCROLL: already there, skipping');
        return;
      }
      debugPrint('SCROLL: animating to $target');
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ),
      );
      return;
    }
    debugPrint('SCROLL: no open set found');
  }

  /// Set indices in the order the lifter actually does them: the
  /// day's superset partners interleaved, everything else in order.
  /// Without a program day (free workout) there are no supersets, so
  /// this is the flat order.
  List<int> get _executionOrder =>
      supersetExecutionOrder(_exerciseGroups, _supersetGroupOf);

  /// supersetGroup per blockKey for the current day(s) (empty when
  /// this is a free workout). The key is each set's blockKey and the
  /// value is the group namespaced by its day, so the same letter in
  /// two mixed days ("A" on day 2 and "A" on day 3) never pairs
  /// across days — unless the lifter linked the two exercises
  /// across days in this run: a cross-day link id wins over the
  /// sheet group, so the linked pair alternates even though the
  /// exercises come from different days.
  Map<String, String?> get _supersetGroupOf {
    final groupOf = <String, String?>{};
    if (_dayExercises != null) {
      final links = _session?.crossDaySupersets ?? const {};
      for (final pair in _dayExercises!) {
        final key = SessionSet.blockKeyFor(
          pair.dayId,
          pair.exercise.exerciseId,
        );
        final link = links[key];
        if (link != null && link.isNotEmpty) {
          // The badge is "S1" / "S2": the pair shares the letter,
          // the number is the position in it — pair by the letter
          // (Nov 19).
          groupOf[key] = supersetPairKey(link);
          continue;
        }
        final group = pair.exercise.supersetGroup;
        groupOf[key] = group == null || group.isEmpty
            ? null
            // The sheet labels the halves "A1" and "A2": the letter
            // is the pair, the number is the position in it. Pair by
            // the letter, or the two halves never meet (Nov 19).
            : '${pair.dayId}|${supersetPairKey(group)}';
      }
    }
    return groupOf;
  }

  // ------------------------------------------------------ set-row state

  /// The one set the lifter is on: the first open set (neither
  /// completed nor skipped) in execution order — superset partners
  /// alternate, so after A1 set 1 the current set is A2 set 1.
  /// Only this row gets the orange border.
  int? get _currentSetIndex {
    final session = _session;
    if (session == null) return null;
    for (final i in _executionOrder) {
      final set = session.sets[i];
      if (!set.completed && !set.skipped) return i;
    }
    return null;
  }

  SetRowState _setRowState(int index, int? currentIndex) {
    final set = _session!.sets[index];
    if (set.completed) return SetRowState.done;
    if (set.skipped) return SetRowState.skipped;
    if (index == currentIndex) return SetRowState.current;
    return SetRowState.pending;
  }

  /// Last session's result for this set ("117.5 × 4"), from logged
  /// Forge workouts. Null when this set was never logged before.
  ///
  /// TODO: sheet-logged history (the imported sheet's Actual RPE /
  /// Bar speed / Status columns F–H) is not imported into Forge, so
  /// sets logged only in the sheet before Forge won't appear here.
  String? _previousLabel(SessionSet set) {
    final previous = _previousSet(set.exerciseId, set.setIndex);
    if (previous == null) return null;
    return '${_fmtWeight(previous.weightKg)} × ${previous.reps}';
  }

  SessionSet? _previousSet(String exerciseId, int setIndex) {
    final sorted = List<WorkoutSession>.from(_pastWorkouts)
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final session in sorted) {
      for (final set in session.sets) {
        if (set.exerciseId == exerciseId &&
            set.setIndex == setIndex &&
            set.completed) {
          return set;
        }
      }
    }
    return null;
  }

  /// Copy the previous performance into this set's weight + reps.
  void _applyPrevious(int index) {
    final session = _session;
    if (session == null) return;
    final set = session.sets[index];
    final previous = _previousSet(set.exerciseId, set.setIndex);
    if (previous == null) return;
    _updateSet(
      index,
      (s) => s.copyWith(weightKg: previous.weightKg, reps: previous.reps),
    );
  }

  /// The plate icon hides for bodyweight sets and machine-based
  /// exercises — there's nothing to load on a machine.
  ///
  /// TODO: Exercise has no machine/equipment flag in the data layer,
  /// so this is a local list for now (Leg Press is the only machine
  /// in the built-in library). When Exercise gains an equipment
  /// field, use that here instead.
  static const _machineExerciseIds = {'legpress'};

  bool _showPlatesFor(SessionSet set) {
    if (set.weightKg <= 0) return false;
    return !_machineExerciseIds.contains(set.exerciseId);
  }

  // ------------------------------------------------------- app-bar title

  /// Workout name for the app bar, line 1. Imported day titles carry
  /// a date prefix ("Mon Oct 19 · D1") — it moves to line 2.
  String get _workoutName {
    final title = _session?.title ?? 'Workout';
    final parts = title.split(' · ');
    if (parts.length > 1 && _looksLikeWeekday(parts.first)) {
      return parts.sublist(1).join(' · ');
    }
    return title;
  }

  /// Date for the app bar, line 2 ("Mon Nov 16").
  String get _workoutDate {
    final date = _session?.date ?? DateTime.now();
    return DateFormat('EEE MMM d').format(date);
  }

  bool _looksLikeWeekday(String s) =>
      RegExp(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b').hasMatch(s);

  // ------------------------------------------------------------- video

  String _videoKey(SessionSet set) => '${set.blockKey}:${set.setIndex}';

  /// Removes a set's video: the uploaded file is deleted from Storage
  /// when one exists, then the clip is cleared from the set. A video
  /// that was only attached locally (not uploaded yet) just clears.
  Future<void> _removeVideo(int index) async {
    final session = _session;
    if (session == null) return;
    final set = session.sets[index];
    if (set.videoPath == null && set.videoUrl == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove video?'),
        content: const Text(
          'This clip will be deleted and cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (set.videoUrl != null) {
      final uid = _auth.currentUid;
      if (uid == null) return;
      try {
        // Same setId the finish flow uploads under.
        await _storage.deleteSetVideo(
          uid,
          '${session.id}_${set.exerciseId}_${set.setIndex}',
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not remove the video. $e')),
          );
        }
        return;
      }
    }
    _videoDurations.remove(_videoKey(set));
    _updateSet(index, (s) => s.copyWith(clearVideo: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video removed.')),
      );
    }
  }

  Future<void> _attachVideo(int index) async {
    final session = _session;
    if (session == null) return;
    final set = session.sets[index];
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Attach video'),
        content: const Text(
          'Record a new clip or pick one from your gallery. '
          'Clips are up to 5 minutes — you can trim them down '
          'before attaching.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(ImageSource.camera),
            child: const Text('Record'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(ImageSource.gallery),
            child: const Text('Gallery'),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;
    final picked = await _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: StorageService.maxVideoSeconds),
    );
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      final durationSec = controller.value.duration.inSeconds.toDouble();
      if (!mounted) return;
      // Trim step: the editor caps the kept cut at the 5-minute limit,
      // so a gallery clip of any length can be cut down to fit.
      // Cancelling (back) abandons the attach.
      final trimmed = await Navigator.of(context).push<TrimResult>(
        MaterialPageRoute(
          builder: (_) => VideoTrimScreen(
            videoPath: picked.path,
            durationSec: durationSec,
          ),
        ),
      );
      if (trimmed == null || !mounted) return;
      if (trimmed.durationSec > StorageService.maxVideoSeconds) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Video is ${trimmed.durationSec.toStringAsFixed(0)} s — max is '
              '${StorageService.maxVideoSeconds} s.',
            ),
          ),
        );
        return;
      }
      _videoDurations[_videoKey(set)] = trimmed.durationSec;
      _updateSet(index, (s) => s.copyWith(videoPath: trimmed.path));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              trimmed.trimmed
                  ? 'Video trimmed to ${trimmed.durationSec.toStringAsFixed(0)} s — it uploads when you finish.'
                  : 'Video attached — it uploads when you finish.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach that video. $e')),
        );
      }
    } finally {
      await controller.dispose();
    }
  }

  // ------------------------------------------------------ finish / drop

  Future<void> _finishWorkout() async {
    final session = _session;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (session == null || uid == null) return;
    final doneCount = session.sets.where((s) => s.completed).length;
    if (doneCount == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete at least one set before finishing.'),
        ),
      );
      return;
    }
    final open =
        session.sets.where((s) => !s.completed && !s.skipped).length;
    if (open > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Finish workout?'),
          content: Text(
            '$open set${open == 1 ? '' : 's'} not logged. '
            'Finish anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep going'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Finish anyway'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    setState(() {
      _finishing = true;
      _uploadLabel = 'Saving your workout…';
      _uploadProgress = 0;
    });
    try {
      var sets = List<SessionSet>.from(session.sets);
      final toUpload = <int>[];
      for (var i = 0; i < sets.length; i++) {
        if (sets[i].videoPath != null && sets[i].videoUrl == null) {
          toUpload.add(i);
        }
      }
      for (var n = 0; n < toUpload.length; n++) {
        final i = toUpload[n];
        setState(() {
          _uploadLabel = 'Uploading video ${n + 1} of ${toUpload.length}…';
          _uploadProgress =
              toUpload.length == 1 ? 0.5 : n / toUpload.length;
        });
        final url = await _storage.uploadSetVideo(
          uid: uid,
          setId: '${session.id}_${sets[i].exerciseId}_${sets[i].setIndex}',
          file: File(sets[i].videoPath!),
          durationSec: _videoDurations[_videoKey(sets[i])] ?? 0,
        );
        sets[i] = sets[i].copyWith(videoUrl: url);
      }
      final volume = sets
          .where((s) => s.completed)
          .fold(0.0, (sum, s) => sum + s.volumeKg);
      final finished = session.copyWith(
        sets: sets,
        status: 'completed',
        totalVolumeKg: volume,
        durationSec: (DateTime.now()
                .difference(_startTime ?? session.date)
                .inSeconds -
            _pausedSeconds())
            .clamp(0, 1 << 31),
      );
      await _firestore.saveWorkout(uid, finished);
      await _store.clear();
      // The move is spent: the days this session covered go back to
      // their own slots, marked done by this session. Best effort —
      // a failure here must never block finishing.
      unawaited(_consumeCoveredMoves(uid, finished));
      // The workout is done — the rest countdown, its alert and the
      // Live Activity all go away with it.
      unawaited(RestNotifyService.cancelRest());

      // PR check: main lifts only — best set of this session vs records.
      final newPrs = <String>[];
      for (final exercise in BuiltInExercises.all.where((e) => e.isMain)) {
        final best = _bestCompletedSet(sets, exercise.id);
        if (best == null || best.weightKg <= 0) continue;
        final old = _records[exercise.id];
        final newE1rm = StrengthMath.e1rm(best.weightKg, best.reps);
        if (old == null ||
            best.weightKg > old.bestWeightKg ||
            newE1rm > old.bestE1rmKg) {
          await _firestore.saveRecord(
            uid,
            Record(
              exerciseId: exercise.id,
              bestWeightKg: old == null
                  ? best.weightKg
                  : (best.weightKg > old.bestWeightKg
                      ? best.weightKg
                      : old.bestWeightKg),
              bestE1rmKg: old == null
                  ? newE1rm
                  : (newE1rm > old.bestE1rmKg ? newE1rm : old.bestE1rmKg),
              date: DateTime.now(),
              setId: '${session.id}:${best.setIndex}',
              videoUrl: best.videoUrl,
            ),
          );
          newPrs.add(
            '${exercise.name} — ${_fmtWeight(best.weightKg)} × ${best.reps}',
          );
        }
      }

      // Sheet write-back (best effort — never blocks finishing).
      final writeBackNote = await _maybeWriteBackToSheet(uid, finished);

      if (!mounted) return;
      setState(() => _finishing = false);
      _ticker?.cancel();
      // A new PR gets a medium buzz with the dialog.
      if (newPrs.isNotEmpty) {
        unawaited(HapticFeedback.mediumImpact());
      }
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Workout complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Volume: ${_fmtWeight(volume)}  ·  '
                'Time: ${_fmtClock(finished.durationSec)}',
              ),
              if (writeBackNote == 'written') ...[
                const SizedBox(height: 8),
                const Text(
                  'Written back to your spreadsheet.',
                  style: ForgeTheme.bodyMuted,
                ),
              ],
              if (writeBackNote == 'failed') ...[
                const SizedBox(height: 8),
                const Text(
                  'Could not write back to your spreadsheet — your workout is saved in Forge.',
                  style: ForgeTheme.warningText,
                ),
              ],
              if (newPrs.isNotEmpty) ...[
                const SizedBox(height: 16),
                // Scale + glow in on the PR card — 200ms easeOutCubic.
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.9, end: 1.0),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: ForgeTheme.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ForgeTheme.green),
                      boxShadow: [
                        BoxShadow(
                          color:
                              ForgeTheme.green.withValues(alpha: 0.3),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.emoji_events,
                              color: ForgeTheme.green,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'New PR!',
                              style: ForgeTheme.titleLargeSuccess,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final pr in newPrs)
                          Text(
                            pr,
                            style: ForgeTheme.bodyMedium,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _finishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not finish the workout. $e')),
      );
    }
  }

  SessionSet? _bestCompletedSet(List<SessionSet> sets, String exerciseId) {
    SessionSet? best;
    for (final set in sets) {
      if (set.exerciseId != exerciseId || !set.completed) continue;
      if (best == null || set.weightKg > best.weightKg) best = set;
    }
    return best;
  }

  /// Deletes the move records for every day a finished session
  /// covered, so each day goes back to its own slot, marked done by
  /// that session. A moved day that was never finished keeps its
  /// move — it stays on its new date until it is done or moved again.
  /// Best effort; never throws.
  Future<void> _consumeCoveredMoves(
    String uid,
    WorkoutSession finished,
  ) async {
    try {
      final programId = finished.programId;
      if (programId == null) return;
      final index = _programs.indexWhere((p) => p.id == programId);
      if (index < 0) return;
      final program = _programs[index];
      final updated = consumeMoves(program, finished.coveredDayKeys);
      if (identical(updated, program)) return;
      _programs[index] = updated;
      await _firestore.saveProgram(uid, updated);
    } catch (_) {
      // Finishing already succeeded; a stale move record is fixed
      // the next time the day is opened.
    }
  }

  /// Best-effort sheet write-back. Returns 'written', 'failed',
  /// 'skipped', or null when the setting is off. Never throws — a
  /// failed write-back must never block finishing a workout.
  Future<String?> _maybeWriteBackToSheet(
    String uid,
    WorkoutSession finished,
  ) async {
    try {
      final profile = await _firestore.getProfile(uid);
      if (profile == null || !profile.writeBackToSheet) return null;
      if (finished.programId == null) return 'skipped';
      final programs = await _firestore.getPrograms(uid);
      Program? program;
      for (final p in programs) {
        if (p.id == finished.programId) program = p;
      }
      final spreadsheetId = program?.sourceSpreadsheetId;
      if (program == null ||
          spreadsheetId == null ||
          spreadsheetId.isEmpty) {
        return 'skipped';
      }
      final client = await _auth.authenticatedGoogleWriteClient();
      if (client == null) return 'failed';
      final fetched =
          await _importer.fetchSpreadsheet(client, spreadsheetId);
      // Formulas visible for the tabs write-back touches: a formula
      // that evaluates to "" looks empty in the normal read, and
      // writing over it would delete it. Best effort — if this read
      // fails, the planner falls back to the normal read, where a
      // formula still shows its computed value.
      Map<String, List<List<String>>>? formulaTabs;
      String? weekTitle;
      for (final w in program.weeks) {
        if (w.id == finished.weekId) weekTitle = w.title;
      }
      String? progressTitle;
      for (final t in fetched.tabs.keys) {
        if (t.toLowerCase().contains('progress')) progressTitle = t;
      }
      final formulaTabTitles = [
        if (weekTitle != null) weekTitle,
        if (progressTitle != null) progressTitle,
      ];
      if (formulaTabTitles.isNotEmpty) {
        try {
          formulaTabs = await _importer.fetchTabFormulas(
            client,
            spreadsheetId,
            formulaTabTitles,
          );
        } catch (_) {
          formulaTabs = null;
        }
      }
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        formulaTabs: formulaTabs,
        program: program,
        session: finished,
      );
      if (plan.updates.isEmpty) return 'skipped';
      await _importer.writeBack(
        client: client,
        spreadsheetId: spreadsheetId,
        plan: plan,
      );
      return 'written';
    } catch (_) {
      return 'failed';
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard workout?'),
        content: const Text(
          'This discards the workout without saving it and deletes '
          'the in-progress session, including any completed sets. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Discard',
              style: ForgeTheme.destructiveLabel,
            ),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    await _store.clear();
    // Discarding ends the workout — the rest displays go with it.
    unawaited(RestNotifyService.cancelRest());
    _ticker?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------ formatting

  String _fmtNum(double v) {
    final s = v.toStringAsFixed(2);
    return s.replaceAll(RegExp(r'\.?0+$'), '');
  }

  String _fmtWeight(double kg) {
    if (kg <= 0) return 'BW';
    if (_profile?.units == 'lb') {
      return '${StrengthMath.kgToLb(kg).round()} lb';
    }
    return '${_fmtNum(kg)} kg';
  }

  String _fmtClock(int totalSec) {
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------ superset info

  /// Badge like "A1" for an exercise in a superset, else null.
  /// [blockKey] is the exercise group's key (day + exercise). A
  /// cross-day link shows its badge ("S1" on the first exercise,
  /// "S2" on the second) — the shared letter is what says they are
  /// paired. A sheet superset shows
  /// the label from the sheet ("A1", "A2") as stored, not a
  /// re-derived letter: re-deriving turned the "A2" half into "B1"
  /// (Nov 19).
  String? _supersetBadge(String blockKey) {
    final link = _session?.crossDaySupersets[blockKey];
    if (link != null && link.isNotEmpty) return link;
    if (_dayExercises == null) return null;
    for (final pair in _dayExercises!) {
      final group = pair.exercise.supersetGroup;
      if (group == null || group.isEmpty) continue;
      if (SessionSet.blockKeyFor(pair.dayId, pair.exercise.exerciseId) ==
          blockKey) {
        return group;
      }
    }
    return null;
  }

  /// Saves new cross-day links on the session (crash-safe) and
  /// rebuilds: the order, badges and rest all derive from the links,
  /// so the workout picks the change up at once.
  void _setCrossDayLinks(Map<String, String> links) {
    final session = _session;
    if (session == null) return;
    setState(() {
      _session = session.copyWith(crossDaySupersets: links);
    });
    unawaited(_store.save(_session!));
  }

  /// The name of the exercise linked to [blockKey], if any. The two
  /// halves carry different badges ("S1" / "S2"), so the partner is
  /// found by the pair's shared letter, not the badge itself.
  String? _linkedPartnerName(WorkoutSession session, String blockKey) {
    final link = session.crossDaySupersets[blockKey];
    if (link == null) return null;
    final letter = supersetPairKey(link);
    final partnerKey = session.crossDaySupersets.entries
        .firstWhere(
          (e) => supersetPairKey(e.value) == letter && e.key != blockKey,
          orElse: () => const MapEntry('', ''),
        )
        .key;
    if (partnerKey.isEmpty) return null;
    return session.sets
        .firstWhere((s) => s.blockKey == partnerKey)
        .name;
  }

  /// Picks the cross-day superset partner for the exercise at
  /// [blockKey]: a sheet of the other day's exercises. Linking
  /// pulls both out of any same-day sheet superset; unlinking puts
  /// them back. Only offered in a mixed workout.
  Future<void> _showLinkSheet(String blockKey) async {
    final session = _session;
    final pairs = _dayExercises;
    if (session == null || pairs == null) return;
    final firstSet = session.sets.firstWhere((s) => s.blockKey == blockKey);
    final dayId = firstSet.dayId;
    final name = firstSet.name;
    final currentLink = session.crossDaySupersets[blockKey];
    final partnerName = _linkedPartnerName(session, blockKey);
    // Candidates: exercises from the other day(s), in day order.
    final candidates = <({String blockKey, String name})>[];
    for (final pair in pairs) {
      if (pair.dayId == dayId) continue;
      final key =
          SessionSet.blockKeyFor(pair.dayId, pair.exercise.exerciseId);
      if (candidates.any((c) => c.blockKey == key)) continue;
      candidates.add((blockKey: key, name: pair.exercise.name));
    }
    if (candidates.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentLink != null
                  ? '$name is linked as $currentLink'
                  : 'Superset $name with…',
              style: ForgeTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick an exercise from the other day. The two will '
              'alternate set by set, and rest after each round. '
              'Linking pulls both out of any same-day superset from '
              'the sheet.',
              style: ForgeTheme.bodyMuted,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (currentLink != null && partnerName != null)
                    ListTile(
                      leading: const Icon(
                        Icons.link_off,
                        color: ForgeTheme.red,
                      ),
                      title: Text('Unlink from $partnerName'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setCrossDayLinks(
                          unlinkCrossDay(
                            session.crossDaySupersets,
                            blockKey,
                          ),
                        );
                      },
                    ),
                  for (final c in candidates)
                    ListTile(
                      title: Text(c.name),
                      subtitle: _linkedPartnerName(session, c.blockKey) ==
                              null
                          ? null
                          : Text(
                              'Supersetted with '
                              '${_linkedPartnerName(session, c.blockKey)}'
                              ' — linking will move it',
                            ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _setCrossDayLinks(
                          linkCrossDay(
                            session.crossDaySupersets,
                            blockKey,
                            c.blockKey,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ordered exercise groups: blockKey -> global set indices. The
  /// key is each set's blockKey, so the same exercise in two mixed
  /// days is two groups, in day order.
  List<(String exerciseId, String name, List<int> indices)>
      get _exerciseGroups {
    final order = <String>[];
    final byId = <String, List<int>>{};
    final names = <String, String>{};
    final sets = _session?.sets ?? [];
    for (var i = 0; i < sets.length; i++) {
      final set = sets[i];
      final key = set.blockKey;
      if (!byId.containsKey(key)) {
        order.add(key);
        byId[key] = [];
        names[key] = set.name;
      }
      byId[key]!.add(i);
    }
    return [
      for (final id in order) (id, names[id]!, byId[id]!),
    ];
  }

  String? get _nextExercisePreview {
    final session = _session;
    if (session == null) return null;
    for (final i in _executionOrder) {
      final set = session.sets[i];
      if (set.completed || set.skipped) continue;
      return 'Up next: ${set.name} · ${_fmtWeight(set.weightKg)} × ${set.reps}';
    }
    return null;
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _session == null
            ? const Text('Workout')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _workoutName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ForgeTheme.titleLarge,
                  ),
                  Text(
                    _workoutDate,
                    maxLines: 1,
                    style: ForgeTheme.captionMuted,
                  ),
                ],
              ),
        actions: [
          if (_session != null) ...[
            IconButton(
              icon: Icon(_timerPaused ? Icons.play_arrow : Icons.pause),
              tooltip: _timerPaused ? 'Resume timer' : 'Pause timer',
              onPressed: _toggleTimerPause,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'calculator') {
                  _showPlateSheet(null);
                } else if (value == 'discard') {
                  _confirmDiscard();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'calculator',
                  child: Text('Weight calculator'),
                ),
                PopupMenuItem(
                  value: 'discard',
                  child: Text('Discard workout'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _showPicker || _session == null
                  ? _buildPicker()
                  : _buildSession(),
      bottomNavigationBar:
          _session == null || _showPicker ? null : _buildBottomBar(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: ForgeTheme.bodyMuted,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _init();
              },
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- picker

  Widget _buildPicker() {
    final activeFirst = List<Program>.from(_programs)
      ..sort((a, b) => (b.isActive ? 1 : 0) - (a.isActive ? 1 : 0));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        const Text(
          'Start a workout',
          style: ForgeTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        const Text(
          'Program day',
          style: ForgeTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (activeFirst.isEmpty)
          const Text(
            'No program yet — start a free workout below.',
            style: ForgeTheme.bodyMuted,
          )
        else
          for (final program in activeFirst)
            for (final week in program.weeks)
              for (final day in week.days)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: ForgeTheme.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    title: Text(
                      day.title,
                      style: ForgeTheme.bodyMediumSemibold,
                    ),
                    subtitle: Text(
                      '${program.name} · ${week.title} · '
                      '${day.exercises.length} exercises',
                      style:
                          ForgeTheme.bodyMuted,
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: ForgeTheme.accent,
                    ),
                    onTap: () {
                      _startFromDay(
                        day,
                        programId: program.id,
                        weekId: week.id,
                        dayId: day.id,
                      );
                      setState(() => _showPicker = false);
                    },
                  ),
                ),
        const SizedBox(height: 24),
        const Text(
          'Free workout',
          style: ForgeTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        const Text(
          'Pick exercises — 3 sets of 5 to start. Tap to add or remove.',
          style: ForgeTheme.bodyMuted,
        ),
        const SizedBox(height: 8),
        for (final exercise in BuiltInExercises.all)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: ForgeTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: _freeSelected.contains(exercise.id)
                  ? Border.all(color: ForgeTheme.accent)
                  : null,
            ),
            child: ListTile(
              title: Text(
                exercise.name,
                style: ForgeTheme.titleMedium,
              ),
              trailing: Icon(
                _freeSelected.contains(exercise.id)
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: _freeSelected.contains(exercise.id)
                    ? ForgeTheme.accent
                    : ForgeTheme.muted,
              ),
              onTap: () {
                setState(() {
                  if (_freeSelected.contains(exercise.id)) {
                    _freeSelected.remove(exercise.id);
                  } else {
                    _freeSelected.add(exercise.id);
                  }
                });
              },
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _freeSelected.isEmpty
                ? null
                : () => _startFreeWorkout(
                      BuiltInExercises.all
                          .where((e) => _freeSelected.contains(e.id))
                          .toList(),
                    ),
            child: const Text('Start free workout'),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- session

  Widget _buildSession() {
    final session = _session!;
    final done =
        session.sets.where((s) => s.completed).length;
    final total = session.sets.length;
    return Stack(
      children: [
        Column(
          children: [
            // Pinned header: elapsed + sets with a thin progress bar.
            // Volume lives in the finish summary now, not up here.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _timerPaused
                            ? Icons.pause
                            : Icons.timer_outlined,
                        size: 16,
                        color: ForgeTheme.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _fmtClock(_elapsedSec),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _timerPaused
                              ? ForgeTheme.muted
                              : ForgeTheme.text,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$done/$total sets',
                        style: ForgeTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(ForgeTheme.radiusSm),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : done / total,
                      minHeight: 4,
                      backgroundColor: ForgeTheme.divider,
                      color: ForgeTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: _listKey,
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  for (final group in _exerciseGroups)
                    _buildExerciseCard(group),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _showAddExerciseSheet(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add exercise'),
                  ),
                  if (_dayExercises != null &&
                      _dayExercises!.length >= 2) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showPairSupersetSheet(),
                      icon: const Icon(Icons.group_work),
                      label: const Text('Pair as superset'),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
        if (_finishing)
          Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: Center(
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: ForgeTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _uploadLabel,
                      textAlign: TextAlign.center,
                      style: ForgeTheme.bodyMedium,
                    ),
                    if (_uploadProgress > 0) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: _uploadProgress),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExerciseCard(
    (String exerciseId, String name, List<int> indices) group,
  ) {
    final session = _session!;
    final badge = _supersetBadge(group.$1);
    // Cross-day linking only exists in a mixed workout (two days in
    // one session); a single day already has its sheet supersets.
    final isMixed = session.coveredDayKeys.length > 1;
    final linkId = session.crossDaySupersets[group.$1];
    final done =
        group.$3.where((i) => session.sets[i].completed).length;
    // Next open set in this exercise (the header button completes
    // sets in order); -1 when the exercise is fully done/skipped.
    final nextOpen = group.$3.firstWhere(
      (i) => !session.sets[i].completed && !session.sets[i].skipped,
      orElse: () => -1,
    );
    // The header check is a state indicator: gray outline while any
    // set is still open, filled green once every set is resolved
    // (completed or skipped).
    final allResolved = group.$3.every(
      (i) => session.sets[i].completed || session.sets[i].skipped,
    );
    final currentIndex = _currentSetIndex;
    return Container(
      key: _exerciseCardKeys.putIfAbsent(group.$1, () => GlobalKey()),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ForgeTheme.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius:
                      BorderRadius.circular(ForgeTheme.radiusChip),
                  onTap: () => ExerciseLibraryScreen.open(
                    context,
                    // group.$1 is the blockKey (day + exercise); the
                    // library wants the plain exercise id, from the
                    // group's first set.
                    exerciseId: session.sets[group.$3.first].exerciseId,
                    exerciseName: group.$2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          group.$2,
                          style: ForgeTheme.titleLargeBold,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_outward,
                        size: 16,
                        color: ForgeTheme.muted,
                      ),
                    ],
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ForgeTheme.accentTint,
                    border: Border.all(color: ForgeTheme.accent),
                    borderRadius: BorderRadius.circular(ForgeTheme.radiusChip),
                  ),
                  child: Text(
                    badge,
                    style: ForgeTheme.badgeLabelAccent,
                  ),
                ),
              if (isMixed)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    icon: Icon(
                      linkId != null ? Icons.link : Icons.add_link,
                      color: linkId != null
                          ? ForgeTheme.accent
                          : ForgeTheme.muted,
                      size: 24,
                    ),
                    tooltip: linkId != null
                        ? 'Linked as $linkId — tap to change'
                        : 'Superset with an exercise from the other day',
                    onPressed: () => _showLinkSheet(group.$1),
                    padding: EdgeInsets.zero,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                '$done/${group.$3.length}',
                style: ForgeTheme.bodyMuted,
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton(
                  icon: Icon(
                    allResolved
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: allResolved
                        ? ForgeTheme.green
                        : ForgeTheme.muted,
                    size: 30,
                  ),
                  tooltip: nextOpen < 0
                      ? 'All sets logged'
                      : 'Complete set '
                          '${session.sets[nextOpen].setIndex + 1}',
                  onPressed:
                      nextOpen < 0 ? null : () => _completeSet(nextOpen),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (badge != null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Superset — alternate with its pair, rest after each round.',
                style: ForgeTheme.captionMuted,
              ),
            ),
          const SizedBox(height: 10),
          const SetRowHeader(),
          const SizedBox(height: 4),
          for (final index in group.$3)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SetRow(
                key: ValueKey('set-$index'),
                setNumber: session.sets[index].setIndex + 1,
                state: _setRowState(index, currentIndex),
                weightLabel: _fmtWeight(session.sets[index].weightKg),
                reps: session.sets[index].reps,
                previousLabel: _previousLabel(session.sets[index]),
                hasVideo: session.sets[index].videoPath != null ||
                    session.sets[index].videoUrl != null,
                showPlates: _showPlatesFor(session.sets[index]),
                onComplete: () => _completeSet(index),
                onSkip: () => _skipSet(index),
                onWeightTap: () => _showSetEditor(index),
                onRepsTap: () => _showSetEditor(index),
                onPreviousTap: () => _applyPrevious(index),
                onPlatesTap: () => _showPlateSheet(index),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: const BoxDecoration(
          color: ForgeTheme.surface,
          border: Border(top: BorderSide(color: ForgeTheme.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBottomStrip(),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _finishing ? null : _finishWorkout,
              child: const Text('Finish workout'),
            ),
          ],
        ),
      ),
    );
  }

  /// The strip above the Finish button. While resting it is the rest
  /// countdown (+15s / Skip rest); otherwise it previews the next
  /// set, or the "rest done" message right after the timer hits 0.
  Widget _buildBottomStrip() {
    if (_restActive) {
      final total = _restTotalSec > 0 ? _restTotalSec : _restRemainingSec;
      final progress =
          total > 0 ? _restRemainingSec / total : 0.0;
      return Container(
        decoration: BoxDecoration(
          color: ForgeTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(ForgeTheme.radius),
          border: Border.all(color: ForgeTheme.accent),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.timer,
                        color: ForgeTheme.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Rest ${_fmtClock(_restRemainingSec)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ForgeTheme.text,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final session = _session;
                        if (session == null) return;
                        // Extend the stored instant — the strip, the
                        // bar, the notification and the Live Activity
                        // all derive from it.
                        final endsAt = (session.restEndsAt ?? DateTime.now())
                            .add(const Duration(seconds: 15));
                        final total =
                            (session.restTotalSec ?? _restTotalSec) + 15;
                        _session = session.copyWith(
                          restEndsAt: endsAt,
                          restTotalSec: total,
                        );
                        unawaited(_store.save(_session!));
                        setState(() {
                          _restRemainingSec =
                              endsAt.difference(DateTime.now()).inSeconds;
                          _restTotalSec = total;
                        });
                        unawaited(RestNotifyService.extendRest(
                          exerciseName: _restExerciseName(),
                          nextSetIndex: _restNextSetIndex(),
                          endsAt: endsAt,
                          prefs: _restPrefs(),
                        ));
                      },
                      style: TextButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('+15s'),
                    ),
                    TextButton(
                      onPressed: _clearRest,
                      style: TextButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Skip rest'),
                    ),
                  ],
                ),
              ),
            ),
            // Draining bar — the rest visibly runs out in accent.
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(ForgeTheme.radius),
              ),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: ForgeTheme.divider,
                color: ForgeTheme.accent,
              ),
            ),
          ],
        ),
      );
    }
    if (_restDone) {
      // Green "Go" for the first minute after the rest ends, then
      // amber — the lifter is overtime.
      final overtimeSec = _restDoneAt == null
          ? 0
          : DateTime.now().difference(_restDoneAt!).inSeconds;
      final overtime = overtimeSec >= 60;
      final color = overtime ? ForgeTheme.warning : ForgeTheme.green;
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(ForgeTheme.radius),
          border: Border.all(color: color),
        ),
        child: Row(
          children: [
            Icon(
              overtime ? Icons.warning_amber : Icons.check_circle,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                overtime
                    ? 'Go — ${_fmtClock(overtimeSec)} over'
                    : 'Go — rest over',
                style: ForgeTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: ForgeTheme.muted,
              tooltip: 'Dismiss',
              onPressed: _clearRest,
            ),
          ],
        ),
      );
    }
    final preview = _nextExercisePreview;
    return Text(
      preview ?? 'All sets logged — nice work.',
      textAlign: TextAlign.center,
      style: ForgeTheme.bodyMuted,
    );
  }

  // --------------------------------------------------------------- sheets

  Future<void> _showSetEditor(int index) async {
    final session = _session;
    if (session == null) return;
    // Target RPE for this set's exercise (program days only; free
    // workouts have no target). An RPE above it shows in warning amber.
    final targetRpe = _targetRpeFor(session.sets[index]);
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      isScrollControlled: true,
      builder: (context) => _SetEditorSheet(
        index: index,
        getSet: () => _session!.sets[index],
        targetRpe: targetRpe,
        speeds: _speeds,
        updateSet: _updateSet,
        showPlateSheet: _showPlateSheet,
        attachVideo: _attachVideo,
        removeVideo: _removeVideo,
      ),
    );
  }

  /// Heaviest set in this session — the standalone calculator opens on it.
  double get _heaviestSetWeight {
    var max = 0.0;
    for (final set in _session?.sets ?? <SessionSet>[]) {
      if (set.weightKg > max) max = set.weightKg;
    }
    return max;
  }

  /// Weight calculator. With a set index it edits that set's weight;
  /// with null it opens standalone (from the AppBar) on the heaviest
  /// set in this workout, with no set to write back to.
  Future<void> _showPlateSheet(int? index) async {
    final session = _session;
    if (session == null) return;
    final profile = _profile;
    var sheetWeight =
        index == null ? _heaviestSetWeight : session.sets[index].weightKg;
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final set = index == null ? null : _session!.sets[index];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Weight calculator',
                  style: ForgeTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  set == null
                      ? 'One side of the bar'
                      : '${set.name} — Set ${set.setIndex + 1} · One side of the bar',
                  style: ForgeTheme.bodyMuted,
                ),
                const SizedBox(height: 16),
                PlateCalculator(
                  targetKg: sheetWeight,
                  barWeightKg: profile?.barWeightKg ?? 20.0,
                  plateSet: profile?.plateSet ?? 'calibrated',
                  units: profile?.units ?? 'kg',
                  stepKg: 2.5,
                  onTargetChanged: (v) =>
                      setSheetState(() => sheetWeight = v),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (set != null) {
                        _updateSet(
                          index!,
                          (s) => s.copyWith(weightKg: sheetWeight),
                        );
                      }
                      Navigator.of(sheetContext).pop();
                    },
                    child: Text(set == null ? 'Done' : 'Set this weight'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAddExerciseSheet() async {
    final selected = <String>{};
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add exercise',
                style: ForgeTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: BuiltInExercises.all.map((exercise) {
                    final alreadyHere = _session!.sets
                        .any((s) => s.exerciseId == exercise.id);
                    final picked = selected.contains(exercise.id);
                    return ListTile(
                      title: Text(
                        exercise.name,
                        style: ForgeTheme.titleMedium,
                      ),
                      subtitle: alreadyHere
                          ? const Text(
                              'Already in this workout',
                              style: ForgeTheme.bodyMuted,
                            )
                          : null,
                      trailing: Icon(
                        picked
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: picked
                            ? ForgeTheme.accent
                            : ForgeTheme.muted,
                      ),
                      onTap: alreadyHere
                          ? null
                          : () => setSheetState(() {
                                if (picked) {
                                  selected.remove(exercise.id);
                                } else {
                                  selected.add(exercise.id);
                                }
                              }),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () {
                          _addExercises(
                            BuiltInExercises.all
                                .where((e) => selected.contains(e.id))
                                .toList(),
                          );
                          Navigator.of(sheetContext).pop();
                        },
                  child: const Text('Add to workout'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPairSupersetSheet() async {
    final dayExercises = _dayExercises;
    if (dayExercises == null || dayExercises.length < 2) return;
    // Day sections, in first-seen order — a mixed session lists each
    // day's exercises under its own heading.
    final dayOrder = <String>[];
    for (final pair in dayExercises) {
      if (!dayOrder.contains(pair.dayId)) dayOrder.add(pair.dayId);
    }
    final selected = <String>{}; // blockKeys
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Pair as superset',
                style: ForgeTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'Pick two exercises to alternate. Supersets pair '
                'exercises from the same day.',
                style: ForgeTheme.bodyMuted,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final dayId in dayOrder) ...[
                      if (dayOrder.length > 1)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            _dayTitle(dayId),
                            style: ForgeTheme.sectionLabel,
                          ),
                        ),
                      for (final pair in dayExercises.where(
                        (p) => p.dayId == dayId,
                      ))
                        _pairSheetTile(
                          pair,
                          selected,
                          setSheetState,
                          sheetContext,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected.length == 2
                      ? () {
                          final pair = selected.toList();
                          _pairSuperset(pair[0], pair[1]);
                          Navigator.of(sheetContext).pop();
                        }
                      : null,
                  child: const Text('Pair as superset'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One row of the pair-superset sheet. Tapping a second exercise
  /// from another day than the first pick is refused — a superset
  /// alternates two exercises from one day's workout.
  Widget _pairSheetTile(
    DayExercise pair,
    Set<String> selected,
    StateSetter setSheetState,
    BuildContext sheetContext,
  ) {
    final key =
        SessionSet.blockKeyFor(pair.dayId, pair.exercise.exerciseId);
    final badge = _supersetBadge(key);
    final picked = selected.contains(key);
    return ListTile(
      title: Text(
        pair.exercise.name,
        style: ForgeTheme.titleMedium,
      ),
      subtitle: badge == null
          ? null
          : Text(
              'Superset $badge',
              style: ForgeTheme.bodyMuted,
            ),
      trailing: Icon(
        picked ? Icons.check_circle : Icons.circle_outlined,
        color: picked ? ForgeTheme.accent : ForgeTheme.muted,
      ),
      onTap: () => setSheetState(() {
        if (picked) {
          selected.remove(key);
          return;
        }
        if (selected.length >= 2) return;
        if (selected.isNotEmpty &&
            selected.first.split('|').first != pair.dayId) {
          ScaffoldMessenger.of(sheetContext).showSnackBar(
            const SnackBar(
              content: Text(
                'Supersets pair exercises from the same day.',
              ),
            ),
          );
          return;
        }
        selected.add(key);
      }),
    );
  }

  /// A day's display title, for the pair-superset sheet's sections.
  String _dayTitle(String dayId) {
    for (final program in _programs) {
      for (final week in program.weeks) {
        for (final day in week.days) {
          if (day.id == dayId) return stripDatePrefix(day.title);
        }
      }
    }
    return 'Workout';
  }

  /// Gives two exercises the same supersetGroup so the existing
  /// badge rendering applies. Persists to the program so the pairing
  /// sticks for future weeks of the same day. Both exercises must be
  /// from the same day — the sheet enforces this.
  Future<void> _pairSuperset(String firstKey, String secondKey) async {
    final session = _session;
    final dayExercises = _dayExercises;
    if (session == null || dayExercises == null) return;
    DayExercise? find(String key) {
      for (final pair in dayExercises) {
        if (SessionSet.blockKeyFor(
              pair.dayId,
              pair.exercise.exerciseId,
            ) ==
            key) {
          return pair;
        }
      }
      return null;
    }

    final first = find(firstKey);
    final second = find(secondKey);
    if (first == null || second == null) return;
    if (first.dayId != second.dayId) return;
    final dayId = first.dayId;
    final firstGroup = first.exercise.supersetGroup;
    final secondGroup = second.exercise.supersetGroup;
    // Already paired together — nothing to do.
    if (firstGroup != null && firstGroup == secondGroup) return;
    // Fresh group id in the import format ("A1", "B1", ...), unique
    // within this day.
    final used = dayExercises
        .where((p) => p.dayId == dayId && p.exercise.supersetGroup != null)
        .map((p) => p.exercise.supersetGroup!.toUpperCase())
        .toSet();
    var code = 'A'.codeUnitAt(0);
    while (code <= 'Z'.codeUnitAt(0) &&
        used.contains('${String.fromCharCode(code)}1')) {
      code++;
    }
    final group = code <= 'Z'.codeUnitAt(0)
        ? '${String.fromCharCode(code)}1'
        : 'P${DateTime.now().millisecondsSinceEpoch}';
    final updated = dayExercises.map((p) {
      if (p.dayId == dayId &&
          (p.exercise.exerciseId == first.exercise.exerciseId ||
              p.exercise.exerciseId == second.exercise.exerciseId)) {
        return (
          dayId: p.dayId,
          exercise: p.exercise.copyWith(supersetGroup: group),
        );
      }
      return p;
    }).toList();
    _dayExercises = updated;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && session.programId != null) {
      final programIndex =
          _programs.indexWhere((p) => p.id == session.programId);
      if (programIndex >= 0) {
        final program = _programs[programIndex];
        // The paired day may live in another week than the session's
        // primary day (a moved day), so it is found by day id.
        final weeks = program.weeks.map((w) {
          return w.copyWith(
            days: w.days.map((d) {
              if (d.id != dayId) return d;
              return d.copyWith(
                exercises: updated
                    .where((p) => p.dayId == dayId)
                    .map((p) => p.exercise)
                    .toList(),
              );
            }).toList(),
          );
        }).toList();
        final saved = program.copyWith(weeks: weeks);
        _programs[programIndex] = saved;
        unawaited(_firestore.saveProgram(uid, saved));
      }
    }
    if (mounted) setState(() {});
  }
}

/// The set editor sheet: weight/reps steppers + type-in fields, RPE,
/// bar speed, plates, video. Owns its controllers and focus nodes
/// (the old _showSetEditor created them in the caller and disposed
/// them in a finally after the sheet await — the sheet rebuilds
/// during its exit animation, so it rebuilt against disposed
/// controllers and crashed). Behaviour is unchanged: steppers, commit
/// on focus loss, RPE chips, bar speed, attach/remove video, plate
/// calculator, Done commits both fields.
class _SetEditorSheet extends StatefulWidget {
  const _SetEditorSheet({
    required this.index,
    required this.getSet,
    required this.targetRpe,
    required this.speeds,
    required this.updateSet,
    required this.showPlateSheet,
    required this.attachVideo,
    required this.removeVideo,
  });

  final int index;
  final SessionSet Function() getSet;
  final double? targetRpe;
  final List<String> speeds;
  final void Function(int index, SessionSet Function(SessionSet) change)
      updateSet;
  final Future<void> Function(int index) showPlateSheet;
  final Future<void> Function(int index) attachVideo;
  final Future<void> Function(int index) removeVideo;

  @override
  State<_SetEditorSheet> createState() => _SetEditorSheetState();
}

class _SetEditorSheetState extends State<_SetEditorSheet> {
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  late final FocusNode _weightFocus;
  late final FocusNode _repsFocus;

  @override
  void initState() {
    super.initState();
    // Type-in fields: the steppers stay for fine-tuning, but the
    // number itself is editable — no more tapping + from 0 to 170.
    // The fields are controller-driven, so a commit (or a revert on
    // bad input) shows at once with no sheet redraw needed.
    _weightController = TextEditingController(
      text: formatNumberInput(widget.getSet().weightKg),
    );
    _repsController = TextEditingController(
      text: '${widget.getSet().reps}',
    );
    _weightFocus = FocusNode();
    _repsFocus = FocusNode();
    // Commit (or revert) when the field loses focus, so a typed value
    // is never lost to a tap elsewhere in the sheet.
    _weightFocus.addListener(() {
      if (!_weightFocus.hasFocus) _commitWeight();
    });
    _repsFocus.addListener(() {
      if (!_repsFocus.hasFocus) _commitReps();
    });
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _weightFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  void _commitWeight() {
    final parsed = parseWeightInput(_weightController.text);
    if (parsed == null) {
      _weightController.text =
          formatNumberInput(widget.getSet().weightKg);
      return;
    }
    widget.updateSet(widget.index, (s) => s.copyWith(weightKg: parsed));
  }

  void _commitReps() {
    final parsed = parseRepsInput(_repsController.text);
    if (parsed == null) {
      _repsController.text = '${widget.getSet().reps}';
      return;
    }
    widget.updateSet(widget.index, (s) => s.copyWith(reps: parsed));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        32 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${set.name} — Set ${set.setIndex + 1}',
            style: ForgeTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: ForgeTheme.accent,
                iconSize: 36,
                tooltip: 'Lighter',
                onPressed: set.weightKg <= 0
                    ? null
                    : () {
                        widget.updateSet(
                          widget.index,
                          (s) => s.copyWith(
                            weightKg: (s.weightKg - 2.5)
                                .clamp(0.0, 500.0),
                          ),
                        );
                        _weightController.text = formatNumberInput(
                          widget.getSet().weightKg,
                        );
                        setState(() {});
                      },
              ),
              SizedBox(
                width: 180,
                child: Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: ForgeTheme.card,
                    borderRadius: BorderRadius.circular(
                        ForgeTheme.radius),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _weightController,
                  focusNode: _weightFocus,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  style: ForgeTheme.hero,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    suffixText: 'kg',
                    suffixStyle: ForgeTheme.bodyMuted
                        .copyWith(fontSize: 16),
                  ),
                    onSubmitted: (_) {
                      _commitWeight();
                      _weightFocus.unfocus();
                      setState(() {});
                    },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: ForgeTheme.accent,
                iconSize: 36,
                tooltip: 'Heavier',
                onPressed: () {
                  widget.updateSet(
                    widget.index,
                    (s) => s.copyWith(
                      weightKg:
                          (s.weightKg + 2.5).clamp(0.0, 500.0),
                    ),
                  );
                  _weightController.text = formatNumberInput(
                    widget.getSet().weightKg,
                  );
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: ForgeTheme.accent,
                iconSize: 36,
                tooltip: 'Fewer reps',
                onPressed: set.reps <= 1
                    ? null
                    : () {
                        widget.updateSet(
                          widget.index,
                          (s) => s.copyWith(reps: s.reps - 1),
                        );
                        _repsController.text =
                            '${widget.getSet().reps}';
                        setState(() {});
                      },
              ),
              SizedBox(
                width: 130,
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: ForgeTheme.card,
                    borderRadius: BorderRadius.circular(
                        ForgeTheme.radius),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _repsController,
                  focusNode: _repsFocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  style: ForgeTheme.numeric,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    suffixText: 'reps',
                    suffixStyle: ForgeTheme.bodyMuted
                        .copyWith(fontSize: 16),
                  ),
                    onSubmitted: (_) {
                      _commitReps();
                      _repsFocus.unfocus();
                      setState(() {});
                    },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: ForgeTheme.accent,
                iconSize: 36,
                tooltip: 'More reps',
                onPressed: () {
                  widget.updateSet(
                    widget.index,
                    (s) => s.copyWith(reps: s.reps + 1),
                  );
                  _repsController.text =
                      '${widget.getSet().reps}';
                  setState(() {});
                },
              ),
            ],
          ),
        // RPE + bar speed used to live under each completed
        // set row; the rows are single-line now, so they moved
        // here into the editor.
        if (set.completed) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'RPE',
                style: ForgeTheme.bodyMuted,
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: ForgeTheme.accent,
                iconSize: 28,
                tooltip: 'Lower RPE',
                onPressed: () {
                  final current = set.rpe ?? 8.0;
                  if (current > 6) {
                    widget.updateSet(
                      widget.index,
                      (s) => s.copyWith(
                        rpe: (current - 0.5).clamp(6.0, 10.0),
                      ),
                    );
                    setState(() {});
                  }
                },
              ),
              SizedBox(
                width: 44,
                child: Text(
                  set.rpe == null
                      ? '—'
                      : set.rpe!.toStringAsFixed(1),
                  textAlign: TextAlign.center,
                  style: widget.targetRpe != null &&
                          set.rpe != null &&
                          set.rpe! > widget.targetRpe
                      ? ForgeTheme.titleMediumWarning
                      : ForgeTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: ForgeTheme.accent,
                iconSize: 28,
                tooltip: 'Raise RPE',
                onPressed: () {
                  final current = set.rpe ?? 8.0;
                  if (current < 10) {
                    widget.updateSet(
                      widget.index,
                      (s) => s.copyWith(
                        rpe: (current + 0.5).clamp(6.0, 10.0),
                      ),
                    );
                    setState(() {});
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            children: widget.speeds.map((speed) {
              final selected = set.barSpeed == speed;
              return ChoiceChip(
                label: Text(speed),
                selected: selected,
                onSelected: (_) {
                  widget.updateSet(
                    widget.index,
                    (s) => s.copyWith(
                      barSpeed: selected ? null : speed,
                    ),
                  );
                  setState(() {});
                },
                selectedColor: ForgeTheme.accentTint,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: selected
                      ? ForgeTheme.accent
                      : ForgeTheme.text,
                ),
                backgroundColor: ForgeTheme.card,
                side: BorderSide(
                  color: selected
                      ? ForgeTheme.accent
                      : ForgeTheme.divider,
                ),
                materialTapTargetSize:
                    MaterialTapTargetSize.padded,
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await widget.showPlateSheet(widget.index);
              setState(() {});
            },
            icon: const Icon(Icons.layers, size: 18),
            label: const Text('Plates'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await widget.attachVideo(widget.index);
              setState(() {});
            },
            icon: Icon(
              set.videoPath != null || set.videoUrl != null
                  ? Icons.videocam
                  : Icons.videocam_outlined,
              size: 18,
            ),
            label: Text(
              set.videoPath != null || set.videoUrl != null
                  ? 'Video attached'
                  : 'Attach video',
            ),
          ),
        ),
        if (set.videoPath != null || set.videoUrl != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () async {
                await widget.removeVideo(widget.index);
                setState(() {});
              },
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove video'),
              style: TextButton.styleFrom(
                foregroundColor: ForgeTheme.muted,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              // A typed value that was never submitted still
              // counts — commit both fields before closing.
              _commitWeight();
              _commitReps();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ),
      ],
    ),
  );
  }
}
