import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/program.dart';
import '../models/record.dart';
import '../models/user_profile.dart';
import '../models/workout.dart';
import '../services/auth_service.dart';
import '../services/day_moves.dart';
import '../services/firestore_service.dart';
import '../services/program_progress.dart';
import '../services/session_store.dart';
import '../services/strength_math.dart';
import '../theme.dart';
import '../widgets/mix_conflict_dialog.dart';
import '../widgets/program_empty_state.dart';
import '../widgets/skeleton.dart';
import '../widgets/side_pill.dart';

/// Meet date for v1. The Program model has no meetPlan field, so the
/// fixed meet date is used for the countdown.
final DateTime _meetDate = DateTime(2027, 1, 16);

/// Today: next uncompleted program day, PRs, meet countdown, streak,
/// and a resume banner for an in-progress session.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  final _firestore = FirestoreService();
  final _auth = AuthService();
  final _sessionStore = SessionStore();

  /// The date this screen is showing. Starts on today; swipe or the
  /// arrows move it, so past and future workouts are one swipe away.
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = _startOfToday();
  }

  String _fmtWeight(double kg, String units) {
    if (units == 'lb') {
      return '${StrengthMath.kgToLb(kg).round()} lb';
    }
    if (kg == kg.roundToDouble()) return '${kg.round()} kg';
    return '${kg.toStringAsFixed(1)} kg';
  }

  // Shared with the Program detail day cards (program_progress.dart)
  // so both screens agree on the estimate.
  int _estimatedMinutes(ProgramDay day) => estimatedMinutesForDay(day);

  /// "Tue, Nov 18" — for move targets and moved-from labels.
  String _fmtDay(DateTime date) => DateFormat('EEE, MMM d').format(date);

  /// "Today · Tue, Nov 17", "Tomorrow · Wed, Nov 18", "Yesterday · …",
  /// or "Thu, Nov 19" — the label above the day view.
  String _dateLabel(DateTime date) {
    final today = _startOfToday();
    final diff = date.difference(today).inDays;
    final shown = _fmtDay(date);
    if (diff == 0) return 'Today · $shown';
    if (diff == 1) return 'Tomorrow · $shown';
    if (diff == -1) return 'Yesterday · $shown';
    return shown;
  }

  /// Moves the shown date by [days], clamped to 90 days either side
  /// of today — the program's whole span, with room to spare.
  void _shiftDate(int days) {
    final today = _startOfToday();
    final next = _selectedDate.add(Duration(days: days));
    final min = today.subtract(const Duration(days: 90));
    final max = today.add(const Duration(days: 90));
    if (next.isBefore(min) || next.isAfter(max)) return;
    setState(() => _selectedDate = next);
  }

  /// The date pager header: back / forward arrows, the date label,
  /// and a "Today" jump that only shows off today.
  Widget _dateNavRow() {
    final today = _startOfToday();
    final isToday = _selectedDate == today;
    final min = today.subtract(const Duration(days: 90));
    final max = today.add(const Duration(days: 90));
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _selectedDate.isAfter(min)
              ? () => _shiftDate(-1)
              : null,
          tooltip: 'Previous day',
        ),
        Expanded(
          child: Text(
            _dateLabel(_selectedDate),
            textAlign: TextAlign.center,
            style: ForgeTheme.titleMediumBoldTabular,
          ),
        ),
        // Disabled (not hidden) on today, so the label stays centred
        // and the row never changes size. Do NOT wrap this in a
        // Visibility with maintainSize — that red-screens the whole
        // tab in debug builds (IndexedStack assert: "Cannot maintain
        // size if animations are not maintained").
        TextButton(
          onPressed: isToday
              ? null
              : () => setState(() => _selectedDate = today),
          child: const Text('Today'),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _selectedDate.isBefore(max)
              ? () => _shiftDate(1)
              : null,
          tooltip: 'Next day',
        ),
      ],
    );
  }

  int _weeksTrained(List<WorkoutSession> workouts) {
    final weeks = <String>{};
    for (final w in workouts) {
      if (w.status != 'completed') continue;
      final start = DateTime(w.date.year, 1, 1);
      final dayOfYear = w.date.difference(start).inDays + 1;
      final week = (dayOfYear - 1) ~/ 7;
      weeks.add('${w.date.year}-W$week');
    }
    return weeks.length;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Today'),
          actions: [
            const SidePill(),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
            ),
          ],
        ),
        body: const Center(
          child: Text('You are not signed in.'),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          const SidePill(),
          StreamBuilder<UserProfile?>(
            stream: _firestore.watchProfile(uid),
            builder: (context, snap) {
              final name = snap.data?.displayName.trim() ?? '';
              final initial = name.isNotEmpty ? name[0].toUpperCase() : null;
              return IconButton(
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: ForgeTheme.accent,
                  child: initial == null
                      ? const Icon(
                          Icons.person,
                          size: 20,
                          color: ForgeTheme.scaffoldBg,
                        )
                      : Text(initial, style: ForgeTheme.avatarInitial),
                ),
                tooltip: 'Settings & profile',
                onPressed: () =>
                    Navigator.of(context).pushNamed('/settings'),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<UserProfile?>(
        stream: _firestore.watchProfile(uid),
        builder: (context, profileSnap) {
          if (profileSnap.connectionState == ConnectionState.waiting) {
            return const TodaySkeleton();
          }
          if (profileSnap.hasError) {
            return const Center(
              child: Text('Could not load your profile. Pull to retry.'),
            );
          }
          final profile = profileSnap.data;
          final units = profile?.units ?? 'kg';
          return StreamBuilder<List<Program>>(
            stream: _firestore.watchPrograms(uid),
            builder: (context, programSnap) {
              if (programSnap.connectionState == ConnectionState.waiting) {
                return const TodaySkeleton();
              }
              if (programSnap.hasError) {
                return const Center(
                  child: Text('Could not load your program. Try again.'),
                );
              }
              return StreamBuilder<List<WorkoutSession>>(
                stream: _firestore.watchWorkouts(uid),
                builder: (context, workoutSnap) {
                  if (workoutSnap.connectionState ==
                      ConnectionState.waiting) {
                    return const TodaySkeleton();
                  }
                  if (workoutSnap.hasError) {
                    return const Center(
                      child: Text('Could not load your workouts.'),
                    );
                  }
                  return StreamBuilder<Map<String, Record>>(
                    stream: _firestore.watchRecords(uid),
                    builder: (context, recordSnap) {
                      if (recordSnap.connectionState ==
                          ConnectionState.waiting) {
                        return const TodaySkeleton();
                      }
                      final programs = programSnap.data ?? [];
                      final workouts = workoutSnap.data ?? [];
                      final records = recordSnap.data ?? {};
                      return _buildBody(
                        context,
                        uid: uid,
                        profile: profile,
                        units: units,
                        programs: programs,
                        workouts: workouts,
                        records: records,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required String uid,
    required UserProfile? profile,
    required String units,
    required List<Program> programs,
    required List<WorkoutSession> workouts,
    required Map<String, Record> records,
  }) {
    final active = programs.where((p) => p.isActive).toList();
    final program = active.isNotEmpty
        ? active.first
        : (programs.isNotEmpty ? programs.first : null);
    final completed = workouts.where((w) => w.status == 'completed').toList();

    // The days for the shown date: the day(s) scheduled on it, plus
    // any day moved onto it. Done days are NOT filtered out — the
    // pager shows what happened on past dates too, with a Completed
    // badge. A date with no day is a "no workout" date, not a reason
    // to jump to another day: the user swipes to the next one.
    List<DaySlot> todaySlots = [];
    if (program != null) {
      todaySlots = daysForDate(program, _selectedDate);
    }

    double pr(String key, String lift) {
      final record = records[key];
      if (record != null) return record.bestWeightKg;
      return profile?.mainLifts[lift] ?? 0;
    }

    final squat = pr('squat', 'squat');
    final bench = pr('bench', 'bench');
    final deadlift = pr('deadlift', 'deadlift');
    final total = squat + bench + deadlift;
    final meetDays = _meetDate.difference(_startOfToday()).inDays;
    final streakWeeks = _weeksTrained(workouts);

    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FutureBuilder<bool>(
              future: _sessionStore.hasActiveSession(),
              builder: (context, snap) {
                if (snap.data != true) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Card(
                    color: ForgeTheme.accent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          Navigator.of(context).pushNamed('/runner'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.play_circle_filled,
                                color: ForgeTheme.scaffoldBg),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Workout in progress — tap to resume',
                                style: ForgeTheme.labelOnAccent,
                              ),
                            ),
                            TextButton(
                              onPressed: _confirmEndSession,
                              style: TextButton.styleFrom(
                                foregroundColor: ForgeTheme.scaffoldBg,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                              ),
                              child: const Text('End'),
                            ),
                            const Icon(Icons.chevron_right,
                                color: ForgeTheme.scaffoldBg),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            _dateNavRow(),
            const SizedBox(height: 12),
            if (program == null)
              _emptyProgramCard(context)
            else
              // Swipe left/right anywhere on the day view to move
              // between dates — the same as the arrows above.
              GestureDetector(
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity;
                  if (v == null) return;
                  if (v < -200) _shiftDate(1);
                  if (v > 200) _shiftDate(-1);
                },
                child: todaySlots.isEmpty
                    ? (hasUncompletedDays(program, completed)
                        ? _noWorkoutCard(
                            context,
                            program: program,
                            completed: completed,
                          )
                        : _allDoneCard(context))
                    : _todayCard(
                        context,
                        program: program,
                        slots: todaySlots,
                        units: units,
                        completed: completed,
                      ),
              ),
            const SizedBox(height: 24),
            ForgeTheme.sectionHeader('Current PRs'),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _prTile('Squat', squat, units,
                      labelColor: ForgeTheme.liftSquat),
                  const SizedBox(width: 8),
                  _prTile('Bench', bench, units,
                      labelColor: ForgeTheme.liftBench),
                  const SizedBox(width: 8),
                  _prTile('Deadlift', deadlift, units,
                      labelColor: ForgeTheme.liftDeadlift),
                  const SizedBox(width: 8),
                  _prTile('Total', total, units, highlight: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined,
                        color: ForgeTheme.muted, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Meet · Jan 16, 2027',
                            style: ForgeTheme.bodyMediumSemibold,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            meetDays > 0
                                ? '$meetDays days to go'
                                : meetDays == 0
                                    ? 'Meet day — good luck!'
                                    : 'Meet day has passed',
                            style: ForgeTheme.bodyMuted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department_outlined,
                        color: ForgeTheme.muted, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$streakWeeks ${streakWeeks == 1 ? 'week' : 'weeks'} trained',
                            style: ForgeTheme.bodyMediumSemibold,
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Weeks with at least one completed workout',
                            style: ForgeTheme.bodyMuted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Ends the in-progress workout from the Today banner, without
  /// saving it. Confirms first — this cannot be undone.
  Future<void> _confirmEndSession() async {
    final end = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End workout?'),
        content: const Text(
          'This ends the workout without saving it and deletes the '
          'in-progress session, including any completed sets. This '
          'cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'End workout',
              style: ForgeTheme.destructiveLabel,
            ),
          ),
        ],
      ),
    );
    if (end != true || !mounted) return;
    await _sessionStore.clear();
    if (mounted) setState(() {});
  }

  Widget _emptyProgramCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ProgramEmptyState(
          onImport: () => Navigator.of(context).pushNamed('/import'),
          onTemplate: () => Navigator.of(context).pushNamed(
            '/program',
            arguments: <String, String>{'action': 'template'},
          ),
          onBlank: () => Navigator.of(context).pushNamed(
            '/program',
            arguments: <String, String>{'action': 'blank'},
          ),
        ),
      ),
    );
  }

  Widget _allDoneCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle_outlined,
                color: ForgeTheme.green, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Program complete',
              textAlign: TextAlign.center,
              style: ForgeTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Every day in this program is done. Add a new week or start a new program.',
              textAlign: TextAlign.center,
              style: ForgeTheme.bodyMuted,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pushNamed('/program'),
              child: const Text('Open program'),
            ),
          ],
        ),
      ),
    );
  }

  /// A date with no workout on it — after a move, or a genuinely
  /// empty day. Start a blank workout, or copy a program day and
  /// train that instead.
  Widget _noWorkoutCard(
    BuildContext context, {
    required Program program,
    required List<WorkoutSession> completed,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'No workout ${_fmtDay(_selectedDate)}',
              style: ForgeTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Nothing scheduled for this day. Start a new workout, '
              'or copy a day from your program.',
              style: ForgeTheme.bodyMuted,
            ),
            const SizedBox(height: 24),
            FutureBuilder<bool>(
              future: _sessionStore.hasActiveSession(),
              builder: (context, sessionSnap) {
                // A workout already in progress owns the screen (the
                // resume banner above) — no second workout starts
                // until it ends.
                if (sessionSnap.data == true) {
                  return const Text(
                    'A workout is already in progress — resume it above.',
                    style: ForgeTheme.bodyMuted,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pushNamed('/runner'),
                      child: const Text('Start a new workout'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showCopyDaySheet(
                        context,
                        program: program,
                        completed: completed,
                      ),
                      icon: const Icon(Icons.content_copy_outlined),
                      label: const Text('Copy a day'),
                      style: OutlinedButton.styleFrom(
                        side:
                            const BorderSide(color: ForgeTheme.divider),
                        foregroundColor: ForgeTheme.text,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// "Copy a day": pick a program day and train its exercises right
  /// now, as a standalone workout. The original day stays where it
  /// is — the copy never counts as the day, and nothing writes back
  /// to the sheet.
  Future<void> _showCopyDaySheet(
    BuildContext context, {
    required Program program,
    required List<WorkoutSession> completed,
  }) async {
    final weeks = [...program.weeks]
      ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
    final days = <({ProgramWeek week, ProgramDay day})>[];
    for (final week in weeks) {
      final sorted = [...week.days]
        ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
      for (final day in sorted) {
        if (isRestDay(day)) continue;
        days.add((week: week, day: day));
      }
    }
    final picked = await showModalBottomSheet<ProgramDay>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Copy a day',
              style: ForgeTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Train this day\'s workout now. The original stays '
              'where it is.',
              style: ForgeTheme.bodyMuted,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in days)
                    ListTile(
                      title: Text(entry.day.title),
                      subtitle: Text(entry.week.title),
                      trailing: completed.any((w) => w.coversDay(
                            program.id,
                            entry.week.id,
                            entry.day.id,
                          ))
                          ? const Icon(
                              Icons.check_circle,
                              color: ForgeTheme.green,
                              size: 20,
                            )
                          : null,
                      onTap: () =>
                          Navigator.of(sheetContext).pop(entry.day),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    Navigator.of(context).pushNamed(
      '/runner',
      arguments: <String, dynamic>{'day': picked, 'copy': true},
    );
  }

  Widget _todayCard(
    BuildContext context, {
    required Program program,
    required List<DaySlot> slots,
    required String units,
    required List<WorkoutSession> completed,
  }) {
    // One slot is the normal day; several means a moved day joined
    // the scheduled one — they run as one long mixed workout.
    final isRest = slots.length == 1 && isRestDay(slots.first.day);
    bool slotDone(DaySlot s) =>
        completed.any((w) => w.coversDay(program.id, s.week.id, s.day.id));
    // The days that still need doing: Start runs those only, so a
    // mixed day that is already done is not run twice. When
    // everything on this date is done, Start becomes "Do again".
    final openSlots = slots.where((s) => !slotDone(s)).toList();
    final allDone = openSlots.isEmpty;
    final totalMinutes = slots.fold<int>(
      0,
      (sum, s) => sum + _estimatedMinutes(s.day),
    );
    // The hero card: today's session + Start. The accent outline marks
    // it as the one thing to do; meet, streak and PRs sit below it in
    // quieter cards.
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ForgeTheme.radius),
        side: const BorderSide(color: ForgeTheme.accent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              slots.length > 1
                  ? '${program.name} · Mixed workout'
                  : '${program.name} · ${slots.first.week.title}',
              style: ForgeTheme.bodyMuted,
            ),
            for (var i = 0; i < slots.length; i++) ...[
              if (i > 0) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 8),
              _daySection(
                context,
                slots[i],
                units,
                done: slotDone(slots[i]),
              ),
            ],
            if (slots.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                '${slots.fold<int>(0, (sum, s) => sum + s.day.exercises.length)} exercises · about $totalMinutes min — one long workout',
                style: ForgeTheme.bodyMuted,
              ),
            ],
            const SizedBox(height: 24),
            if (isRest)
              OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Rest day logged. Recovery is training too.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.spa_outlined),
                label: const Text('Log recovery'),
              )
            else
              FutureBuilder<bool>(
                future: _sessionStore.hasActiveSession(),
                builder: (context, sessionSnap) {
                  // A workout already in progress owns the one orange
                  // fill on this screen (the resume banner above), so the
                  // Start button stays hidden until that workout ends —
                  // and a day cannot be moved mid-workout either.
                  final inProgress = sessionSnap.data == true;
                  // "Do again" starts every day on this date over;
                  // Start runs only the days that still need doing.
                  final startSlots = allDone ? slots : openSlots;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!inProgress)
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(context).pushNamed(
                            '/runner',
                            arguments: <String, dynamic>{
                              'programId': program.id,
                              'dayKeys': [
                                for (final s in startSlots)
                                  dayKey(s.week.id, s.day.id),
                              ],
                            },
                          ),
                          child: Text(
                            allDone
                                ? 'Do again'
                                : startSlots.length > 1
                                    ? 'Start mixed workout'
                                    : 'Start workout',
                          ),
                        ),
                      if (!inProgress) const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _showWorkoutPreview(
                          context,
                          days: [for (final s in slots) s.day],
                          units: units,
                        ),
                        icon: const Icon(Icons.list),
                        label: const Text('View workout'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: ForgeTheme.divider),
                          foregroundColor: ForgeTheme.text,
                        ),
                      ),
                      // A day cannot be moved mid-workout, and a done
                      // day has nowhere to move to — the chooser only
                      // ever sees the days that still need doing.
                      if (!inProgress && !allDone) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _chooseDayToMove(
                            openSlots,
                            program,
                            completed,
                            units,
                          ),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('Move workout'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: ForgeTheme.divider),
                            foregroundColor: ForgeTheme.text,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// One day inside the Today card: title, a "Moved from …" note
  /// when the day was moved here, a Completed badge when it is done,
  /// and its first exercises.
  Widget _daySection(
    BuildContext context,
    DaySlot slot,
    String units, {
    bool done = false,
  }) {
    final day = slot.day;
    final minutes = _estimatedMinutes(day);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          day.title,
          style: ForgeTheme.headlineMedium,
        ),
        if (slot.movedFrom != null) ...[
          const SizedBox(height: 4),
          Text(
            'Moved from ${_fmtDay(slot.movedFrom!)} — goes back once '
            'you finish it.',
            style: ForgeTheme.captionMuted,
          ),
        ],
        if (done) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: ForgeTheme.green,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                'Completed',
                style: ForgeTheme.captionSemibold.copyWith(
                  color: ForgeTheme.green,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          isRestDay(day)
              ? 'Rest day — recover and get ready for the next session.'
              : '${day.exercises.length} ${day.exercises.length == 1 ? 'exercise' : 'exercises'} · about $minutes min',
          style: ForgeTheme.bodyMuted,
        ),
        if (!isRestDay(day)) ...[
          const SizedBox(height: 12),
          ...day.exercises.take(4).map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _exerciseLine(e, units),
                ),
              ),
          if (day.exercises.length > 4)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _showWorkoutPreview(
                  context,
                  days: [day],
                  units: units,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: ForgeTheme.muted,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: Text('+ ${day.exercises.length - 4} more'),
              ),
            ),
        ],
      ],
    );
  }

  /// Read-only full list of the days' exercises. Creates no session.
  Future<void> _showWorkoutPreview(
    BuildContext context, {
    required List<ProgramDay> days,
    required String units,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              days.length > 1
                  ? 'Mixed workout'
                  : days.first.title,
              style: ForgeTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${days.fold<int>(0, (sum, d) => sum + d.exercises.length)} exercises — read only, nothing starts here.',
              style: ForgeTheme.bodyMuted,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final day in days) ...[
                    if (days.length > 1) ...[
                      Text(
                        stripDatePrefix(day.title),
                        style: ForgeTheme.sectionLabel,
                      ),
                      const SizedBox(height: 4),
                    ],
                    for (int i = 0; i < day.exercises.length; i++) ...[
                      if (i > 0) const Divider(height: 16),
                      _exerciseLine(day.exercises[i], units),
                    ],
                    if (day != days.last) const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- moving a day

  /// Which day to move, when several share the card. One day goes
  /// straight to the target sheet.
  Future<void> _chooseDayToMove(
    List<DaySlot> slots,
    Program program,
    List<WorkoutSession> completed,
    String units,
  ) async {
    if (slots.length == 1) {
      await _showMoveSheet(slots.first, program, completed, units);
      return;
    }
    final picked = await showModalBottomSheet<DaySlot>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Which workout do you want to move?',
              style: ForgeTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final slot in slots)
              ListTile(
                title: Text(stripDatePrefix(slot.day.title)),
                subtitle: slot.movedFrom == null
                    ? null
                    : Text('Moved from ${_fmtDay(slot.movedFrom!)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(sheetContext).pop(slot),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _showMoveSheet(picked, program, completed, units);
  }

  /// Moves one day: tomorrow, or another day the user picks. Moves
  /// only go forward.
  Future<void> _showMoveSheet(
    DaySlot slot,
    Program program,
    List<WorkoutSession> completed,
    String units,
  ) async {
    final tomorrow = _startOfToday().add(const Duration(days: 1));
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Move ${stripDatePrefix(slot.day.title)}',
              style: ForgeTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'The workout moves to the new day. It goes back to its '
              'own day once you finish it.',
              style: ForgeTheme.bodyMuted,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(tomorrow),
              child: Text('Tomorrow · ${_fmtDay(tomorrow)}'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () async {
                final day = await showDatePicker(
                  context: sheetContext,
                  initialDate: tomorrow,
                  firstDate: tomorrow,
                  lastDate: _startOfToday().add(const Duration(days: 90)),
                );
                if (day != null && sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(day);
                }
              },
              child: const Text('Choose another day…'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _runMoveFlow(program, slot, picked, completed, units);
  }

  /// Moves [slot]'s day to [target], asking about every workout in
  /// the way: shift it, or mix with it. Each landing is saved as it
  /// happens; cancelling stops the rest of the chain.
  Future<void> _runMoveFlow(
    Program program,
    DaySlot slot,
    DateTime target,
    List<WorkoutSession> completed,
    String units,
  ) async {
    // A stack of moves still to land. A shifted day goes on top, so
    // it lands before the move that displaced it is re-checked.
    final pending = <({DaySlot slot, DateTime target})>[
      (slot: slot, target: target),
    ];
    var current = program;
    var steps = 0;
    while (pending.isNotEmpty) {
      if (++steps > 10) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Too many moves in a row — try mixing instead.'),
          ),
        );
        return;
      }
      final next = pending.removeLast();
      current = await _landMove(
        current,
        next.slot,
        next.target,
        completed,
        pending,
        units,
      );
      if (!mounted) return;
    }
  }

  /// Lands one move: if the target day is free, the move is saved.
  /// If it holds a workout, asks whether to shift that workout or
  /// mix with it. Returns the updated program (unchanged when the
  /// move was cancelled or deferred).
  Future<Program> _landMove(
    Program program,
    DaySlot slot,
    DateTime target,
    List<WorkoutSession> completed,
    List<({DaySlot slot, DateTime target})> pending,
    String units,
  ) async {
    final targetDay = DateTime(target.year, target.month, target.day);
    bool isDone(DaySlot s) => completed.any(
          (w) => w.coversDay(program.id, s.week.id, s.day.id),
        );
    // Occupants: training days on the target date that are not done
    // yet, not counting the day being moved.
    final occupants = daysForDate(program, targetDay)
        .where((s) => s.day.id != slot.day.id && !isDone(s))
        .toList();
    if (occupants.isEmpty) {
      final updated = moveDay(program, slot.week, slot.day, targetDay);
      await _saveMove(updated, slot, targetDay);
      return updated;
    }
    final choice =
        await _showConflictDialog(slot, occupants.first, targetDay);
    if (choice == null || choice == MoveChoice.cancel) return program;
    if (choice == MoveChoice.mix) {
      final updated = moveDay(program, slot.week, slot.day, targetDay);
      await _saveMove(updated, slot, targetDay);
      if (mounted) {
        await _showMixedPreview([slot, ...occupants], targetDay, units);
      }
      return updated;
    }
    // Shift the occupant: pick its new day, land it first, then
    // re-check this move.
    final shiftTarget = await _pickShiftDay(occupants.first, targetDay);
    if (shiftTarget == null || !mounted) return program;
    pending.add((slot: slot, target: targetDay));
    pending.add((slot: occupants.first, target: shiftTarget));
    return program;
  }

  /// "Should we mix?" — the move landed on a day that already has a
  /// workout: shift that workout, or mix the two together.
  Future<MoveChoice?> _showConflictDialog(
    DaySlot moving,
    DaySlot occupant,
    DateTime target,
  ) {
    final movingName = stripDatePrefix(moving.day.title);
    final occupantName = stripDatePrefix(occupant.day.title);
    // Just the "D2" part — the full title is already in the body, and
    // the whole thing on a button wrapped into a mess (Nov 18).
    final occupantShort = occupantName.split('·').first.trim();
    return showDialog<MoveChoice>(
      context: context,
      builder: (dialogContext) => MixConflictDialog(
        movingName: movingName,
        occupantName: occupantName,
        occupantShort: occupantShort,
        targetLabel: _fmtDay(target),
      ),
    );
  }

  /// Picks the new day for a shifted workout. Shifts only go
  /// forward, one day past the day it was displaced from.
  Future<DateTime?> _pickShiftDay(DaySlot occupant, DateTime fromDate) {
    final def = fromDate.add(const Duration(days: 1));
    return showDatePicker(
      context: context,
      helpText: 'Move ${stripDatePrefix(occupant.day.title)} to',
      initialDate: def,
      firstDate: def,
      lastDate: _startOfToday().add(const Duration(days: 90)),
    );
  }

  /// Saves a landed move and says so. The program stream refreshes
  /// Today, so the moved day shows on its new date right away.
  Future<void> _saveMove(
    Program updated,
    DaySlot slot,
    DateTime target,
  ) async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    await _firestore.saveProgram(uid, updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${stripDatePrefix(slot.day.title)} moved to ${_fmtDay(target)}.',
        ),
      ),
    );
  }

  /// Shows what the mix will look like: the moved day first, then
  /// the day it joins, one long list. Read only.
  Future<void> _showMixedPreview(
    List<DaySlot> slots,
    DateTime target,
    String units,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mixed workout · ${_fmtDay(target)}',
              style: ForgeTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'One long workout — the first day runs first, then the '
              'second right after. Supersets work as normal, and each '
              "day's results go back to its own day when you finish. "
              'In the workout, tap the link icon on an exercise to '
              'superset it with one from the other day.',
              style: ForgeTheme.bodyMuted,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final slot in slots) ...[
                    Text(
                      stripDatePrefix(slot.day.title),
                      style: ForgeTheme.sectionLabel,
                    ),
                    const SizedBox(height: 4),
                    for (final e in slot.day.exercises)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _exerciseLine(e, units),
                      ),
                    if (slot != slots.last) const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Looks good'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _repsLabel(ProgramExercise e) {
    final text = e.displayRepsText;
    if (text != null && text.isNotEmpty) return text;
    if (e.repsMin != null && e.repsMax != null) {
      return '${e.repsMin}–${e.repsMax}';
    }
    if (e.repsMin != null) return '${e.repsMin}';
    return '—';
  }

  /// One exercise line: name on the left (ellipsised when long),
  /// sets × reps · weight right-aligned in tabular figures.
  /// Shared by the Today card and the View workout sheet.
  Widget _exerciseLine(ProgramExercise e, String units) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '• ${e.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ForgeTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${e.sets} × ${_repsLabel(e)}'
          '${e.targetWeightKg != null ? ' · ${_fmtWeight(e.targetWeightKg!, units)}' : ''}',
          style: ForgeTheme.bodyMuted.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _prTile(String label, double kg, String units,
      {bool highlight = false, Color? labelColor}) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Text(
                label,
                style: ForgeTheme.captionMuted.copyWith(
                  color: labelColor ?? ForgeTheme.muted,
                  fontWeight: labelColor == null
                      ? FontWeight.normal
                      : FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  kg > 0 ? _fmtWeight(kg, units) : '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: highlight
                        ? ForgeTheme.accent
                        : ForgeTheme.text,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
