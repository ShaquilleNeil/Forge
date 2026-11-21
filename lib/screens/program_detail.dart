import 'package:flutter/material.dart';

import '../models/exercise.dart';
import '../models/program.dart';
import '../models/user_profile.dart';
import '../models/workout.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/program_progress.dart';
import '../services/sheet_import_service.dart';
import '../services/strength_math.dart';
import '../theme.dart';
import '../widgets/program_day_card.dart';
import '../widgets/text_field_dialog.dart';

String _newId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

/// One program on its own page: summary, week chips, day cards.
/// Reached by tapping a program card on the Program list. Rename,
/// set-as-active and delete live in the overflow menu here, not on
/// the list. [isCoach] opens a coaching program from the coach side:
/// same editor, but the program lives in the coach's own list, it is
/// never active, and the training-only pieces (today detection,
/// progress against finished sessions) are hidden.
class ProgramDetailScreen extends StatefulWidget {
  const ProgramDetailScreen({
    super.key,
    required this.programId,
    this.isCoach = false,
  });

  final String programId;
  final bool isCoach;

  @override
  State<ProgramDetailScreen> createState() => _ProgramDetailScreenState();
}

class _ProgramDetailScreenState extends State<ProgramDetailScreen> {
  final _firestore = FirestoreService();
  final _auth = AuthService();
  final _importer = SheetImportService();

  int _selectedWeekIndex = 0;
  final Set<String> _expandedDays = {};
  UserProfile? _profile;

  /// "<program id>|<stored modifiedTime>" the sheet-change check last
  /// ran for — the check runs once per program + timestamp, so opening
  /// the program again does not re-prompt for the same sheet state.
  String? _sheetCheckedKey;

  /// The today-week chip has been scrolled into view (once; browsing
  /// to another week does not re-scroll).
  bool _scrolledToTodayWeek = false;

  /// Whether the week containing today was auto-selected (once;
  /// after that the user's own week choice wins).
  bool _autoWeekDone = false;

  /// One key per week chip, so the chip containing today can be
  /// scrolled into view on open.
  final Map<int, GlobalKey> _weekChipKeys = {};

  /// The week + day dated today, if the program has one. Null when no
  /// day carries today's date.
  ({int weekIndex, String dayId})? _todayWeekAndDay(Program program) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weeks = [...program.weeks]
      ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
    for (var i = 0; i < weeks.length; i++) {
      final days = [...weeks[i].days]
        ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
      for (final day in days) {
        final date = ProgramDay.parseDate(day.title, program.createdAt.year);
        if (date != null && date == today) {
          return (weekIndex: i, dayId: day.id);
        }
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    final profile = await _firestore.getProfile(uid);
    if (mounted) setState(() => _profile = profile);
  }

  String get _units => _profile?.units ?? 'kg';

  Future<bool> _save(Program program) async {
    final uid = _auth.currentUid;
    if (uid == null) return false;
    try {
      if (widget.isCoach) {
        await _firestore.saveCoachProgram(uid, program);
      } else {
        await _firestore.saveProgram(uid, program);
      }
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
      return false;
    }
  }

  // ---------- Two-way sheet sync ----------

  /// Sheet -> app: checks whether the linked sheet changed since the
  /// app last knew about it, and offers a one-tap update. Silent when
  /// nothing changed, when read access is not granted, or when the
  /// check itself fails — a failed check never blocks opening the
  /// program. A program imported before this feature has no stored
  /// timestamp, so the first check baselines it silently instead of
  /// prompting. "Not now" remembers the dismissal: it stores the
  /// sheet's current timestamp, so the prompt only returns when the
  /// sheet changes again.
  Future<void> _checkSheetChanged(Program program) async {
    final uid = _auth.currentUid;
    final spreadsheetId = program.sourceSpreadsheetId;
    if (uid == null || spreadsheetId == null || spreadsheetId.isEmpty) {
      return;
    }
    try {
      final client = await _auth.authenticatedGoogleClientSilent();
      if (client == null) return;
      final current = await _importer.fetchSpreadsheetModifiedTime(
        client,
        spreadsheetId,
      );
      if (current == null) return;
      final stored = program.sourceModifiedTime;
      if (stored == null) {
        await _save(
          program.copyWith(sourceModifiedTime: current.toIso8601String()),
        );
        return;
      }
      if (!SheetImportService.sheetChanged(stored, current)) return;
      if (!mounted) return;
      final update = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber,
                  color: ForgeTheme.warning, size: 22),
              SizedBox(width: 8),
              Text('Sheet changed'),
            ],
          ),
          content: Text(
            'Your spreadsheet changed since the last import. Update '
            '"${program.name}" from the sheet? Anything you added or '
            'changed in the app that isn\'t in the sheet (like a new '
            'week or day) will be replaced'
            '${widget.isCoach ? '.' : ' — but moved days stay where you put them.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Update program'),
            ),
          ],
        ),
      );
      if (update == true) {
        final result = await _importer.importToFirestore(
          uid: uid,
          spreadsheetId: spreadsheetId,
          client: client,
          coach: widget.isCoach,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${result.programName} updated from the sheet.'),
          ),
        );
      } else if (update == false) {
        await _save(
          program.copyWith(sourceModifiedTime: current.toIso8601String()),
        );
      }
    } catch (_) {
      // Silent — see the doc comment above.
    }
  }

  /// App -> sheet: after a target weight is changed in the app, write
  /// the new weight into the sheet's column B for that exercise — the
  /// same row the results write-back finds. Only when write-back is on
  /// and the program came from a sheet. A formula in B is never
  /// touched; anything else (blank or typed) is overwritten, because
  /// the app is now the source of the new number. Silent on failure:
  /// the app edit is already saved; the sheet just stays behind.
  Future<void> _maybeWriteWeightToSheet(
    Program program,
    ProgramWeek week,
    ProgramDay day,
    ProgramExercise exercise,
  ) async {
    final uid = _auth.currentUid;
    final spreadsheetId = program.sourceSpreadsheetId;
    final weightKg = exercise.targetWeightKg;
    if (uid == null ||
        spreadsheetId == null ||
        spreadsheetId.isEmpty) {
      return;
    }
    if (weightKg == null || weightKg <= 0) return;
    try {
      final profile = await _firestore.getProfile(uid);
      if (profile == null || !profile.writeBackToSheet) return;
      final client = await _auth.authenticatedGoogleWriteClient();
      if (client == null) return;
      final fetched =
          await _importer.fetchSpreadsheet(client, spreadsheetId);
      // The formula-visible read is required, not best-effort: only it
      // can tell a formula in B (=...) from a typed number, and a
      // formula must never be overwritten.
      final formulaTabs = await _importer.fetchTabFormulas(
        client,
        spreadsheetId,
        [week.title],
      );
      final update = SheetImportService.buildWeightWrite(
        fetched: fetched,
        formulaTabs: formulaTabs,
        week: week,
        day: day,
        exerciseName: exercise.name,
        weightKg: weightKg,
      );
      if (update == null) return;
      await _importer.writeBack(
        client: client,
        spreadsheetId: spreadsheetId,
        plan: WriteBackPlan(updates: [update]),
      );
      // The sheet just changed (by us) — refresh the stored timestamp
      // so opening Programs does not prompt about our own write.
      final modified = await _importer.fetchSpreadsheetModifiedTime(
        client,
        spreadsheetId,
      );
      if (modified != null) {
        await _save(
          program.copyWith(sourceModifiedTime: modified.toIso8601String()),
        );
      }
    } catch (_) {
      // Silent — see the doc comment above.
    }
  }

  // ---------- Program-level actions ----------

  Future<void> _setActive(Program program) async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    try {
      await _firestore.setActiveProgram(uid, program.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${program.name} is now your active program.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not set the active program.')),
      );
    }
  }

  Future<void> _renameProgram(Program program) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => TextFieldDialog(
        title: const Text('Rename program'),
        labelText: 'Program name',
        initialValue: program.name,
        actions: (context, text) => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(text().trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == program.name) return;
    // copyWith, not a fresh Program: the rebuild used to drop the
    // sent-by stamp (and the sent record), so renaming a program a
    // coach sent made the client's "Sent by you" card vanish.
    await _save(program.copyWith(name: name));
  }

  Future<void> _deleteProgram(Program program) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete program?'),
        content: Text(
          'Delete "${program.name}" and all its weeks and days? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ForgeTheme.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final uid = _auth.currentUid;
    if (uid == null) return;
    try {
      if (widget.isCoach) {
        await _firestore.deleteCoachProgram(uid, program.id);
      } else {
        await _firestore.deleteProgram(uid, program.id);
      }
      if (!mounted) return;
      // The program is gone — back to the list.
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete the program.')),
      );
    }
  }

  // ---------- Week / day actions ----------

  Future<void> _addWeek(Program program) async {
    final index = program.weeks.length;
    final updated = program.copyWith(weeks: [
      ...program.weeks,
      ProgramWeek(
        id: _newId('week'),
        title: 'Week ${index + 1}',
        weekIndex: index,
      ),
    ]);
    setState(() => _selectedWeekIndex = index);
    await _save(updated);
  }

  Future<void> _addDay(Program program, int weekIndex) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => TextFieldDialog(
        title: const Text('Add a day'),
        labelText: 'Day title',
        initialValue: 'Day ${program.weeks[weekIndex].days.length + 1}',
        actions: (context, text) => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(text().trim()),
            child: const Text('Add day'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    final week = program.weeks[weekIndex];
    final weeks = [...program.weeks];
    weeks[weekIndex] = ProgramWeek(
      id: week.id,
      title: week.title,
      weekIndex: week.weekIndex,
      days: [
        ...week.days,
        ProgramDay(
          id: _newId('day'),
          title: title,
          dayIndex: week.days.length,
        ),
      ],
    );
    await _save(_withWeeks(program, weeks));
  }

  Future<void> _removeDay(Program program, int weekIndex, int dayIndex) async {
    final day = program.weeks[weekIndex].days[dayIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove day?'),
        content: Text('Remove "${day.title}" and its exercises?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ForgeTheme.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final week = program.weeks[weekIndex];
    final days = [...week.days]..removeAt(dayIndex);
    final weeks = [...program.weeks];
    weeks[weekIndex] = ProgramWeek(
      id: week.id,
      title: week.title,
      weekIndex: week.weekIndex,
      days: days,
    );
    await _save(_withWeeks(program, weeks));
  }

  Program _withWeeks(Program program, List<ProgramWeek> weeks) =>
      // copyWith keeps every field the explicit rebuild used to drop
      // (meet plan, sheet link, sent-by stamp, sent record, moves).
      program.copyWith(weeks: weeks);

  // ---------- Exercise actions ----------

  Program _withExercise(
    Program program,
    int weekIndex,
    int dayIndex,
    List<ProgramExercise> exercises,
  ) {
    final week = program.weeks[weekIndex];
    final day = week.days[dayIndex];
    final days = [...week.days];
    days[dayIndex] = ProgramDay(
      id: day.id,
      title: day.title,
      dayIndex: day.dayIndex,
      exercises: exercises,
    );
    final weeks = [...program.weeks];
    weeks[weekIndex] = ProgramWeek(
      id: week.id,
      title: week.title,
      weekIndex: week.weekIndex,
      days: days,
    );
    return _withWeeks(program, weeks);
  }

  Future<void> _addExercise(Program program, int weekIndex, int dayIndex) async {
    final added = await showDialog<ProgramExercise>(
      context: context,
      builder: (context) => _AddExerciseDialog(units: _units),
    );
    if (added == null) return;
    final day = program.weeks[weekIndex].days[dayIndex];
    await _save(_withExercise(
      program,
      weekIndex,
      dayIndex,
      [...day.exercises, added],
    ));
  }

  Future<void> _editExerciseWeight(
    Program program,
    int weekIndex,
    int dayIndex,
    int exIndex,
  ) async {
    final day = program.weeks[weekIndex].days[dayIndex];
    final exercise = day.exercises[exIndex];
    final current = exercise.targetWeightKg == null
        ? ''
        : _units == 'lb'
            ? StrengthMath.kgToLb(exercise.targetWeightKg!).round().toString()
            : _trimNumber(exercise.targetWeightKg!);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => TextFieldDialog(
        title: Text('Target weight — ${exercise.name}'),
        labelText: 'Weight in $_units',
        hintText: 'Leave empty for no fixed weight',
        initialValue: current,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        actions: (context, text) => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(text().trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    double? weightKg;
    if (value.isNotEmpty) {
      final entered = double.tryParse(value);
      if (entered == null || entered < 0) return;
      weightKg =
          _units == 'lb' ? StrengthMath.lbToKg(entered) : entered;
    }
    final updated = ProgramExercise(
      exerciseId: exercise.exerciseId,
      name: exercise.name,
      sets: exercise.sets,
      repsMin: exercise.repsMin,
      repsMax: exercise.repsMax,
      repsText: exercise.repsText,
      targetWeightKg: weightKg,
      percentOf1rm: exercise.percentOf1rm,
      targetRpe: exercise.targetRpe,
      notes: exercise.notes,
      supersetGroup: exercise.supersetGroup,
    );
    final exercises = [...day.exercises];
    exercises[exIndex] = updated;
    final saved = _withExercise(program, weekIndex, dayIndex, exercises);
    final ok = await _save(saved);
    // App -> sheet: the new target weight goes back to the sheet's
    // column B for this exercise (only when write-back is on, and only
    // when the app save itself succeeded).
    if (ok && weightKg != null && weightKg > 0) {
      final week = program.weeks[weekIndex];
      await _maybeWriteWeightToSheet(saved, week, day, updated);
    }
  }

  Future<void> _removeExercise(
    Program program,
    int weekIndex,
    int dayIndex,
    int exIndex,
  ) async {
    final day = program.weeks[weekIndex].days[dayIndex];
    final exercises = [...day.exercises]..removeAt(exIndex);
    await _save(_withExercise(program, weekIndex, dayIndex, exercises));
  }

  String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Program')),
        body: const Center(child: Text('You are not signed in.')),
      );
    }
    return StreamBuilder<List<Program>>(
      stream: widget.isCoach
          ? _firestore.watchCoachPrograms(uid)
          : _firestore.watchPrograms(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Program')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Program')),
            body: const Center(
              child: Text('Could not load this program. Try again.'),
            ),
          );
        }
        final programs = snapshot.data ?? [];
        Program? program;
        for (final p in programs) {
          if (p.id == widget.programId) program = p;
        }
        if (program == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Program')),
            body: const Center(
              child: Text('This program was deleted.'),
            ),
          );
        }
        // A coaching program has no finished sessions of its own:
        // progress against workouts is a training concept, so the
        // detail gets an empty session list and hides the progress UI.
        if (widget.isCoach) return _buildDetail(context, program, const []);
        return StreamBuilder<List<WorkoutSession>>(
          stream: _firestore.watchWorkouts(uid),
          builder: (context, workoutsSnapshot) {
            final sessions = workoutsSnapshot.data ?? [];
            return _buildDetail(context, program!, sessions);
          },
        );
      },
    );
  }

  Widget _buildDetail(
    BuildContext context,
    Program program,
    List<WorkoutSession> sessions,
  ) {
    final progress = programProgress(program, sessions);
    final weeks = [...program.weeks]
      ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
    final weekIndex =
        _selectedWeekIndex.clamp(0, weeks.isEmpty ? 0 : weeks.length - 1);
    final week = weeks.isEmpty ? null : weeks[weekIndex];
    // No date detection on the coach side: a copied program keeps
    // its dated day titles, but the coach is not training it, so no
    // day is ever "today" here.
    final todaySpot = widget.isCoach ? null : _todayWeekAndDay(program);
    // Sheet -> app check: once per program + stored timestamp.
    final checkKey =
        '${program.id}|${program.sourceModifiedTime}';
    if (program.sourceSpreadsheetId != null &&
        _sheetCheckedKey != checkKey) {
      _sheetCheckedKey = checkKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkSheetChanged(program);
      });
    }
    // Date detection: open on the week containing today and expand
    // today's day. Runs once; the user's own week choice after that
    // is left alone.
    if (todaySpot != null && !_autoWeekDone) {
      _autoWeekDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedWeekIndex = todaySpot.weekIndex;
          _expandedDays.add(todaySpot.dayId);
        });
      });
    }
    // Scroll the chip for the week containing today into view on
    // open (once; browsing to another week after that does not
    // re-scroll).
    if (todaySpot != null && !_scrolledToTodayWeek) {
      _scrolledToTodayWeek = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final keyContext =
            _weekChipKeys[todaySpot.weekIndex]?.currentContext;
        if (keyContext != null) {
          Scrollable.ensureVisible(keyContext, alignment: 0.3);
        }
      });
    }
    final label = progressLabel(progress);
    // Coach programs carry no week-of or meet parts: just the size.
    final metaLine = widget.isCoach
        ? coachProgramMetaLine(program)
        : programMetaLine(program, progress);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          program.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Program options',
            onSelected: (value) {
              if (value == 'active') {
                _setActive(program);
              } else if (value == 'rename') {
                _renameProgram(program);
              } else if (value == 'delete') {
                _deleteProgram(program);
              }
            },
            itemBuilder: (context) => [
              // Coach programs are never active.
              if (!widget.isCoach && !program.isActive)
                const PopupMenuItem(
                  value: 'active',
                  child: Text('Set as active program'),
                ),
              const PopupMenuItem(
                value: 'rename',
                child: Text('Rename program'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete program',
                  style: TextStyle(color: ForgeTheme.red),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (program.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: ForgeTheme.green,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Active program',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ForgeTheme.scaffoldBg,
                      ),
                    ),
                  ),
                if (program.isActive) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    metaLine,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ForgeTheme.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (program.description != null &&
                program.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                program.description!,
                style: const TextStyle(
                  fontSize: 13,
                  color: ForgeTheme.muted,
                ),
              ),
            ],
            // No progress UI on the coach side: a coaching program
            // is not trained, so there is nothing to be "done" of it.
            if (!widget.isCoach && progress.totalDays > 0) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.fraction,
                  minHeight: 6,
                  backgroundColor: ForgeTheme.raised,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    ForgeTheme.accent,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: ForgeTheme.muted,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ...weeks.asMap().entries.map((entry) {
                    final i = entry.key;
                    final w = entry.value;
                    final isTodayWeek = todaySpot?.weekIndex == i;
                    return Padding(
                      key: _weekChipKeys.putIfAbsent(i, () => GlobalKey()),
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isTodayWeek)
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: i == weekIndex
                                    ? ForgeTheme.accent
                                    : ForgeTheme.text,
                              ),
                            if (isTodayWeek) const SizedBox(width: 6),
                            Text(w.title),
                          ],
                        ),
                        selected: i == weekIndex,
                        selectedColor: ForgeTheme.card,
                        side: BorderSide(
                          color: i == weekIndex
                              ? ForgeTheme.accent
                              : ForgeTheme.divider,
                        ),
                        labelStyle: TextStyle(
                          color: i == weekIndex
                              ? ForgeTheme.accent
                              : ForgeTheme.text,
                          fontWeight: i == weekIndex
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                        onSelected: (_) =>
                            setState(() => _selectedWeekIndex = i),
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    onPressed: () => _addWeek(program),
                    icon: const Icon(Icons.add),
                    label: const Text('Add week'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (week == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'This program has no weeks yet. Add a week to get started.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ForgeTheme.muted),
                  ),
                ),
              )
            else ...[
              ...week.days.map((day) {
                final dayIndex = week.days.indexOf(day);
                final expanded = _expandedDays.contains(day.id);
                final isToday = todaySpot != null &&
                    todaySpot.weekIndex == weekIndex &&
                    todaySpot.dayId == day.id;
                return ProgramDayCard(
                  day: day,
                  isToday: isToday,
                  expanded: expanded,
                  units: _units,
                  onToggle: () => setState(() {
                    if (expanded) {
                      _expandedDays.remove(day.id);
                    } else {
                      _expandedDays.add(day.id);
                    }
                  }),
                  onRemoveDay: () =>
                      _removeDay(program, weekIndex, dayIndex),
                  onAddExercise: () =>
                      _addExercise(program, weekIndex, dayIndex),
                  onEditWeight: (exIndex) => _editExerciseWeight(
                    program,
                    weekIndex,
                    dayIndex,
                    exIndex,
                  ),
                  onRemoveExercise: (exIndex) => _removeExercise(
                    program,
                    weekIndex,
                    dayIndex,
                    exIndex,
                  ),
                );
              }),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => _addDay(program, weekIndex),
                icon: const Icon(Icons.add),
                label: const Text('Add day'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Add-exercise dialog: owns its five controllers (the old _addExercise
/// created them in the caller and disposed them after the await — the
/// fields rebuild during the exit animation, so they rebuilt against
/// disposed controllers and crashed). Pops with the built
/// [ProgramExercise], or null when cancelled.
class _AddExerciseDialog extends StatefulWidget {
  const _AddExerciseDialog({required this.units});

  final String units;

  @override
  State<_AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends State<_AddExerciseDialog> {
  String _selectedId = BuiltInExercises.all.first.id;
  bool _custom = false;
  late final TextEditingController _nameController;
  late final TextEditingController _setsController;
  late final TextEditingController _repsController;
  late final TextEditingController _weightController;
  late final TextEditingController _rpeController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _setsController = TextEditingController(text: '3');
    _repsController = TextEditingController(text: '5');
    _weightController = TextEditingController();
    _rpeController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _setsController.dispose();
    _repsController.dispose();
    _weightController.dispose();
    _rpeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add exercise'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedId,
              decoration: const InputDecoration(labelText: 'Exercise'),
              items: [
                ...BuiltInExercises.all.map((e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(e.name),
                    )),
                const DropdownMenuItem(
                  value: '__custom',
                  child: Text('Custom…'),
                ),
              ],
              onChanged: (v) => setState(() {
                _custom = v == '__custom';
                _selectedId = v ?? _selectedId;
              }),
            ),
            if (_custom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Exercise name',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _setsController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Sets'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _repsController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Reps'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weightController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Target weight (${widget.units}, optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rpeController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Target RPE (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final isCustom = _custom;
            final name = isCustom
                ? _nameController.text.trim()
                : BuiltInExercises.all
                    .firstWhere((e) => e.id == _selectedId)
                    .name;
            if (name.isEmpty) return;
            final sets = int.tryParse(_setsController.text) ?? 3;
            final reps = int.tryParse(_repsController.text);
            double? weightKg;
            final weightText = _weightController.text.trim();
            if (weightText.isNotEmpty) {
              final entered = double.tryParse(weightText);
              if (entered != null) {
                weightKg = widget.units == 'lb'
                    ? StrengthMath.lbToKg(entered)
                    : entered;
              }
            }
            Navigator.of(context).pop(ProgramExercise(
              exerciseId: isCustom ? _newId('ex') : _selectedId,
              name: name,
              sets: sets,
              repsMin: reps,
              repsMax: reps,
              targetWeightKg: weightKg,
              targetRpe: _rpeController.text.trim().isEmpty
                  ? null
                  : _rpeController.text.trim(),
            ));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
