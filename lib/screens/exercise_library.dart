import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/exercise.dart';
import '../models/record.dart';
import '../models/workout.dart';
import '../services/firestore_service.dart';
import '../services/strength_math.dart';
import '../theme.dart';

/// Exercise library: search + category chips over [BuiltInExercises.all],
/// each row showing the user's best for that lift, tap for history + PR.
///
/// v1 has built-in exercises only — no custom-exercise creation.
/// Exercise library: 10 built-ins + search + category chips, with a
/// per-exercise detail sheet (best lift, best e1RM, recent history).
///
/// [initialExerciseId] opens that exercise's detail sheet as soon as
/// the records load (used by the runner and Progress exercise-name
/// taps). [initialQuery] pre-fills the search instead, for exercise
/// ids that are not built-ins.
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({
    super.key,
    this.initialExerciseId,
    this.initialQuery,
  });

  final String? initialExerciseId;
  final String? initialQuery;

  /// Open the library on one exercise's detail. When the id is a
  /// built-in the detail sheet opens; otherwise the list is filtered
  /// to the exercise name.
  static void open(
    BuildContext context, {
    required String exerciseId,
    String? exerciseName,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExerciseLibraryScreen(
          initialExerciseId: exerciseId,
          initialQuery: exerciseName,
        ),
      ),
    );
  }

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _Best {
  const _Best({required this.bestWeightKg, required this.bestE1rmKg});

  final double bestWeightKg;
  final double bestE1rmKg;
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _firestore = FirestoreService();
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String _units = 'kg';
  String _query = '';
  String _category = 'all';
  Map<String, Record> _records = {};
  List<WorkoutSession> _workouts = [];
  bool _openedInitial = false;

  static const _categories = <String, String>{
    'all': 'All',
    'squat': 'Squat',
    'bench': 'Bench',
    'deadlift': 'Deadlift',
    'accessory': 'Accessory',
    'conditioning': 'Conditioning',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'You need to sign in to see the exercise library.';
      });
      return;
    }
    try {
      final results = await Future.wait([
        _firestore.getProfile(uid),
        _firestore.getRecords(uid),
        _firestore.getWorkouts(uid, limit: 50),
      ]);
      if (!mounted) return;
      setState(() {
        _units = (results[0] as dynamic)?.units as String? ?? 'kg';
        _records = results[1] as Map<String, Record>;
        _workouts = results[2] as List<WorkoutSession>;
        _loading = false;
      });
      _openInitialExercise();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the library. $e';
      });
    }
  }

  /// Open the exercise the screen was pushed for: the detail sheet
  /// when it is a built-in, otherwise a search for its name.
  void _openInitialExercise() {
    if (_openedInitial) return;
    final exerciseId = widget.initialExerciseId;
    if (exerciseId == null) return;
    _openedInitial = true;
    final match = BuiltInExercises.all
        .where((e) => e.id == exerciseId)
        .firstOrNull;
    if (match != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showExerciseSheet(match);
      });
      return;
    }
    final query = widget.initialQuery;
    if (query != null && query.isNotEmpty) {
      setState(() {
        _query = query;
        _searchController.text = query;
      });
    }
  }

  String _fmtNum(double v) {
    final s = v.toStringAsFixed(2);
    return s.replaceAll(RegExp(r'\.?0+$'), '');
  }

  String _fmtWeight(double kg) {
    if (_units == 'lb') return '${StrengthMath.kgToLb(kg).round()} lb';
    return '${_fmtNum(kg)} kg';
  }

  /// Best for one lift: max of the saved record and the best set in
  /// past workouts (best by estimated 1RM).
  _Best? _bestFor(String exerciseId) {
    double bestWeight = _records[exerciseId]?.bestWeightKg ?? 0;
    double bestE1rm = _records[exerciseId]?.bestE1rmKg ?? 0;
    var found = _records.containsKey(exerciseId);
    for (final session in _workouts) {
      for (final set in session.sets) {
        if (set.exerciseId != exerciseId || !set.completed) continue;
        found = true;
        final e1rm = StrengthMath.e1rm(set.weightKg, set.reps);
        if (set.weightKg > bestWeight) bestWeight = set.weightKg;
        if (e1rm > bestE1rm) bestE1rm = e1rm;
      }
    }
    if (!found) return null;
    return _Best(bestWeightKg: bestWeight, bestE1rmKg: bestE1rm);
  }

  /// Recent completed sets for one lift, newest first.
  List<({DateTime date, SessionSet set, String sessionTitle})> _historyFor(
    String exerciseId,
  ) {
    final rows = <({DateTime date, SessionSet set, String sessionTitle})>[];
    for (final session in _workouts) {
      for (final set in session.sets) {
        if (set.exerciseId == exerciseId && set.completed) {
          rows.add((
            date: session.date,
            set: set,
            sessionTitle: session.title,
          ));
        }
      }
    }
    rows.sort((a, b) => b.date.compareTo(a.date));
    return rows.take(20).toList();
  }

  List<Exercise> get _filtered {
    final q = _query.trim().toLowerCase();
    return BuiltInExercises.all.where((e) {
      if (_category != 'all' && e.category != _category) return false;
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  String _categoryLabel(String category) =>
      _categories[category] ?? category;

  /// Selected chip color: the lift color for squat/bench/deadlift,
  /// accent for the rest.
  Color _selectedChipColor(String category) {
    final lift = ForgeTheme.liftColorFor(category);
    return lift == ForgeTheme.muted ? ForgeTheme.accent : lift;
  }

  Future<void> _showExerciseSheet(Exercise exercise) async {
    final best = _bestFor(exercise.id);
    final history = _historyFor(exercise.id);
    final record = _records[exercise.id];
    final dateFmt = DateFormat('MMM d, yyyy');
    await showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: ForgeTheme.sheetAnimationStyle,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ForgeTheme.divider,
                  borderRadius: BorderRadius.circular(ForgeTheme.radiusSm),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              exercise.name,
              style: ForgeTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _categoryLabel(exercise.category) +
                  (exercise.isMain ? '  ·  Main lift' : ''),
              style: ForgeTheme.bodyMuted,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ForgeTheme.card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: best == null
                  ? const Text(
                      'No PR yet — log a set to set your first best.',
                      style: ForgeTheme.bodyMuted,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.emoji_events,
                                color: ForgeTheme.accent, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Personal best',
                              style: ForgeTheme.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Best: ${_fmtWeight(best.bestWeightKg)}',
                          style: ForgeTheme.headlineMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Estimated 1RM: ${_fmtWeight(best.bestE1rmKg)}'
                          '${record != null ? '  ·  ${dateFmt.format(record.date)}' : ''}',
                          style: ForgeTheme.bodyMuted,
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Recent sets',
              style: ForgeTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              const Text(
                'No sets logged yet for this lift.',
                style: ForgeTheme.bodyMuted,
              )
            else
              for (final row in history)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: ForgeTheme.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_fmtWeight(row.set.weightKg)} × ${row.set.reps}',
                              style: ForgeTheme.titleMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${dateFmt.format(row.date)}'
                              '${row.set.rpe != null ? '  ·  RPE ${row.set.rpe!.toStringAsFixed(1)}' : ''}'
                              '${row.set.barSpeed != null ? '  ·  ${row.set.barSpeed}' : ''}',
                              style: ForgeTheme.bodyMuted,
                            ),
                          ],
                        ),
                      ),
                      if (row.set.videoUrl != null)
                        const Icon(
                          Icons.videocam,
                          color: ForgeTheme.accent,
                          size: 20,
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exercise Library')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                            _load();
                          },
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: const InputDecoration(
                          hintText: 'Search exercises',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        children: _categories.entries.map((entry) {
                          final selected = _category == entry.key;
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(entry.value),
                              selected: selected,
                              onSelected: (_) =>
                                  setState(() => _category = entry.key),
                              selectedColor:
                                  _selectedChipColor(entry.key),
                              labelStyle: TextStyle(
                                color: selected
                                    ? ForgeTheme.scaffoldBg
                                    : ForgeTheme.text,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                              backgroundColor: ForgeTheme.card,
                              side: const BorderSide(
                                color: ForgeTheme.divider,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'No exercises match that search.',
                                    style: ForgeTheme.bodyMuted,
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton(
                                    onPressed: () => setState(() {
                                      _query = '';
                                      _searchController.clear();
                                    }),
                                    child: const Text('Clear search'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              itemCount: _filtered.length + 1,
                              itemBuilder: (context, index) {
                                if (index == _filtered.length) {
                                  return const Padding(
                                    padding:
                                        EdgeInsets.only(top: 16, bottom: 8),
                                    child: Text(
                                      'Built-in exercises only in v1 — '
                                      'custom exercises are not '
                                      'supported yet.',
                                      textAlign: TextAlign.center,
                                      style: ForgeTheme.captionMuted,
                                    ),
                                  );
                                }
                                final exercise = _filtered[index];
                                final best = _bestFor(exercise.id);
                                return Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: ForgeTheme.card,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    title: Text(
                                      exercise.name,
                                      style: ForgeTheme.titleMedium,
                                    ),
                                    subtitle: Text(
                                      _categoryLabel(exercise.category) +
                                          (exercise.isMain
                                              ? '  ·  Main lift'
                                              : ''),
                                      style: ForgeTheme.bodyMuted,
                                    ),
                                    trailing: best == null
                                        ? const Text(
                                            'No sets yet',
                                            style: ForgeTheme.bodyMuted,
                                          )
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                'Best ${_fmtWeight(best.bestWeightKg)}',
                                                style: ForgeTheme.titleMediumTabular,
                                              ),
                                              Text(
                                                'e1RM ${_fmtWeight(best.bestE1rmKg)}',
                                                style: ForgeTheme.captionMuted
                                                    .copyWith(fontFeatures: const [
                                                  FontFeature
                                                      .tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                    onTap: () =>
                                        _showExerciseSheet(exercise),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
