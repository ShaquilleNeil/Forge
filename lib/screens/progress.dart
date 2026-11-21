import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bodyweight.dart';
import '../models/record.dart';
import '../models/submission.dart';
import '../models/user_profile.dart';
import '../models/workout.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/strength_math.dart';
import '../theme.dart';
import '../widgets/skeleton.dart';
import 'exercise_library.dart';

const _mainLifts = ['squat', 'bench', 'deadlift'];

/// Total of the three main lifts for the DOTS / Goodlift card: a
/// logged record beats the profile lift; the profile lift (from the
/// sheet's prior close, or edited in Settings) is the fallback — the
/// same rule Today's PR tiles use. Null when neither exists for any
/// lift. Pure, so it is unit-testable.
///
/// Without the fallback, DOTS stayed hidden on a fresh account even
/// though Today showed a total: the records collection is empty
/// until a lift is logged in the app (or a sheet re-import reads the
/// D4 top singles), while the profile lifts are there from the
/// start (Nov 19).
double? totalForDots(
  Map<String, Record> records,
  Map<String, double>? mainLifts,
) {
  double total = 0;
  var found = false;
  for (final lift in _mainLifts) {
    final weight = records[lift]?.bestWeightKg ?? mainLifts?[lift] ?? 0;
    if (weight > 0) {
      total += weight;
      found = true;
    }
  }
  return found ? total : null;
}

String _liftName(String exerciseId) {
  switch (exerciseId) {
    case 'squat':
      return 'Squat';
    case 'bench':
      return 'Bench Press';
    case 'deadlift':
      return 'Deadlift';
    default:
      if (exerciseId.isEmpty) return 'Unknown';
      return exerciseId[0].toUpperCase() + exerciseId.substring(1);
  }
}

/// Monday (start of week) for a date — ISO week bucket.
DateTime _weekStart(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

String formatWeight(double kg, String units) {
  if (units == 'lb') {
    return '${StrengthMath.kgToLb(kg).toStringAsFixed(1)} lb';
  }
  return '${kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 1)} kg';
}

/// Progress: PR table, e1RM trend, weekly volume, bodyweight, DOTS/GL.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final FirestoreService _db = FirestoreService();
  final AuthService _auth = AuthService();

  /// Bumped to re-fetch bodyweight entries after adding one.
  int _bwRefresh = 0;

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Progress')),
        body: const Center(child: Text('Sign in to see your progress.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: StreamBuilder<UserProfile?>(
        stream: _db.watchProfile(uid),
        builder: (context, profileSnap) {
          final profile = profileSnap.data;
          final units = profile?.units ?? 'kg';
          return StreamBuilder<Map<String, Record>>(
            stream: _db.watchRecords(uid),
            builder: (context, recordsSnap) {
              if (recordsSnap.connectionState == ConnectionState.waiting) {
                return const ProgressSkeleton();
              }
              if (recordsSnap.hasError) {
                return _ErrorView(
                  error: '${recordsSnap.error}',
                  onRetry: () => setState(() {}),
                );
              }
              final records = recordsSnap.data ?? {};
              return StreamBuilder<List<WorkoutSession>>(
                stream: _db.watchWorkouts(uid, limit: 100),
                builder: (context, workoutsSnap) {
                  if (workoutsSnap.connectionState ==
                      ConnectionState.waiting) {
                    return const ProgressSkeleton();
                  }
                  if (workoutsSnap.hasError) {
                    return _ErrorView(
                      error: '${workoutsSnap.error}',
                      onRetry: () => setState(() {}),
                    );
                  }
                  final workouts = workoutsSnap.data ?? [];
                  return FutureBuilder<List<BodyweightEntry>>(
                    future: _db.getBodyweight(uid),
                    builder: (context, bwSnap) {
                      if (bwSnap.connectionState == ConnectionState.waiting) {
                        return const ProgressSkeleton();
                      }
                      if (bwSnap.hasError) {
                        return _ErrorView(
                          error: '${bwSnap.error}',
                          onRetry: () => setState(() {}),
                        );
                      }
                      final entries = (bwSnap.data ?? [])
                        ..sort((a, b) => a.date.compareTo(b.date));
                      return _ProgressBody(
                        uid: uid,
                        profile: profile,
                        units: units,
                        records: records,
                        workouts: workouts,
                        bodyweightEntries: entries,
                        onBodyweightAdded: () =>
                            setState(() => _bwRefresh++),
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
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;

  const _ErrorView({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    // Friendly sentence on screen; the raw exception goes to the log.
    debugPrint('Progress load failed: $error');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Could not load progress. Try again.',
              textAlign: TextAlign.center,
              style: ForgeTheme.errorText,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  final String uid;
  final UserProfile? profile;
  final String units;
  final Map<String, Record> records;
  final List<WorkoutSession> workouts;
  final List<BodyweightEntry> bodyweightEntries;
  final VoidCallback onBodyweightAdded;

  const _ProgressBody({
    required this.uid,
    required this.profile,
    required this.units,
    required this.records,
    required this.workouts,
    required this.bodyweightEntries,
    required this.onBodyweightAdded,
  });

  BodyweightEntry? get _latestBodyweight =>
      bodyweightEntries.isEmpty ? null : bodyweightEntries.last;

  double? get _totalKg => totalForDots(records, profile?.mainLifts);

  @override
  Widget build(BuildContext context) {
    final total = _totalKg;
    final latestBw = _latestBodyweight;
    final sex = profile?.sex ?? 'male';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const _SectionTitle('Personal records'),
        const SizedBox(height: 8),
        if (records.isEmpty)
          _EmptyCard(
            text:
                'No PRs yet. PRs are set automatically when you log a heavier lift.',
            actionLabel: 'Start a workout',
            onAction: () => Navigator.of(context).pushNamed('/runner'),
          )
        else
          ...records.entries.map((entry) {
            final record = entry.value;
            return _PrRow(
              record: record,
              units: units,
              latestBodyweight: latestBw,
              onDraftSaved: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Draft saved — ready for Rank.'),
                  ),
                );
              },
            );
          }),
        const SizedBox(height: 24),
        const _SectionTitle('Estimated 1RM trend'),
        const SizedBox(height: 4),
        const Text(
          'Best e1RM per week for the main lifts.',
          style: ForgeTheme.bodyMuted,
        ),
        const SizedBox(height: 8),
        _E1rmChart(workouts: workouts, units: units),
        const SizedBox(height: 24),
        const _SectionTitle('Weekly volume'),
        const SizedBox(height: 4),
        const Text(
          'Total volume lifted per week.',
          style: ForgeTheme.bodyMuted,
        ),
        const SizedBox(height: 8),
        _VolumeChart(workouts: workouts, units: units),
        const SizedBox(height: 24),
        const _SectionTitle('Bodyweight'),
        const SizedBox(height: 8),
        _BodyweightCard(
          entries: bodyweightEntries,
          units: units,
          onAdd: () async {
            final added = await _showAddBodyweightDialog(context, units);
            if (added != null) {
              try {
                await FirestoreService().saveBodyweight(uid, added);
                onBodyweightAdded();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bodyweight saved.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not save: $e')),
                  );
                }
              }
            }
          },
        ),
        const SizedBox(height: 24),
        const _SectionTitle('DOTS / Goodlift'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: total == null || latestBw == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add PRs for squat, bench and deadlift, and log your bodyweight, to see your DOTS and Goodlift points.',
                        style: ForgeTheme.bodyMuted,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).pushNamed('/runner'),
                        child: const Text('Start a workout'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total ${formatWeight(total, units)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'At ${formatWeight(latestBw.weightKg, units)} on ${DateFormat('MMM d, yyyy').format(latestBw.date)}',
                        style: ForgeTheme.bodyMuted,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _ScoreTile(
                              label: 'DOTS · est.',
                              value: StrengthMath.dots(
                                total,
                                latestBw.weightKg,
                                sex,
                              ).toStringAsFixed(1),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ScoreTile(
                              label: 'Goodlift · est.',
                              value: StrengthMath.glPoints(
                                total,
                                latestBw.weightKg,
                                sex,
                              ).toStringAsFixed(1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Estimate only — not an official DOTS or Goodlift score or ranking.',
                        style: ForgeTheme.captionMuted,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return ForgeTheme.sectionHeader(text);
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyCard({
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: ForgeTheme.bodyMuted),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreTile extends StatelessWidget {
  final String label;
  final String value;

  const _ScoreTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ForgeTheme.surface,
        borderRadius: BorderRadius.circular(ForgeTheme.radius),
        border: Border.all(color: ForgeTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ForgeTheme.bodyMuted),
          const SizedBox(height: 4),
          Text(
            value,
            style: ForgeTheme.numeric,
          ),
        ],
      ),
    );
  }
}

/// One PR row, with "Prepare Rank submission" on main-lift rows.
class _PrRow extends StatefulWidget {
  final Record record;
  final String units;
  final BodyweightEntry? latestBodyweight;
  final VoidCallback onDraftSaved;

  const _PrRow({
    required this.record,
    required this.units,
    required this.latestBodyweight,
    required this.onDraftSaved,
  });

  @override
  State<_PrRow> createState() => _PrRowState();
}

class _PrRowState extends State<_PrRow> {
  bool _saving = false;
  bool _draftSaved = false;

  Future<void> _prepareSubmission() async {
    final bw = widget.latestBodyweight;
    if (bw == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add your bodyweight first — it is needed for a Rank submission.'),
        ),
      );
      return;
    }
    final uid = AuthService().currentUid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final submission = Submission(
        id: 'sub_${DateTime.now().millisecondsSinceEpoch}',
        userId: uid,
        setId: widget.record.setId ?? '',
        exerciseId: widget.record.exerciseId,
        claimedWeightKg: widget.record.bestWeightKg,
        bodyweightKg: bw.weightKg,
        date: widget.record.date,
        videoUrl: widget.record.videoUrl,
      );
      await FirestoreService().saveSubmission(uid, submission);
      if (mounted) {
        setState(() => _draftSaved = true);
        widget.onDraftSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save draft: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final isNew =
        DateTime.now().difference(record.date).inDays < 7;
    final isMainLift = _mainLifts.contains(record.exerciseId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                      exerciseId: record.exerciseId,
                      exerciseName: _liftName(record.exerciseId),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: ForgeTheme.liftColorFor(
                                record.exerciseId),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _liftName(record.exerciseId),
                            style: Theme.of(context).textTheme.titleMedium,
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
                if (isNew)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ForgeTheme.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'New',
                      style: ForgeTheme.captionOnAccent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _PrStat(
                    label: 'Best lift',
                    value: formatWeight(record.bestWeightKg, widget.units),
                  ),
                ),
                Expanded(
                  child: _PrStat(
                    label: 'Best e1RM',
                    value: formatWeight(record.bestE1rmKg, widget.units),
                  ),
                ),
                Expanded(
                  child: _PrStat(
                    label: 'Date',
                    value: DateFormat('MMM d, yyyy').format(record.date),
                  ),
                ),
              ],
            ),
            if (isMainLift) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_saving || _draftSaved)
                      ? null
                      : _prepareSubmission,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: Text(
                    _draftSaved
                        ? 'Draft saved — ready for Rank'
                        : 'Prepare Rank submission',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrStat extends StatelessWidget {
  final String label;
  final String value;

  const _PrStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: ForgeTheme.captionMuted),
        const SizedBox(height: 2),
        Text(value, style: ForgeTheme.bodyMediumSemibold),
      ],
    );
  }
}

/// Best e1RM per week, one line per main lift (last 8 weeks with data).
class _E1rmChart extends StatelessWidget {
  final List<WorkoutSession> workouts;
  final String units;

  const _E1rmChart({required this.workouts, required this.units});

  @override
  Widget build(BuildContext context) {
    // best e1RM per lift per week
    final Map<String, Map<DateTime, double>> best = {
      for (final lift in _mainLifts) lift: {},
    };
    for (final session in workouts) {
      if (session.status != 'completed') continue;
      final week = _weekStart(session.date);
      for (final set in session.sets) {
        if (!set.completed) continue;
        if (!_mainLifts.contains(set.exerciseId)) continue;
        final e1rm = StrengthMath.e1rm(set.weightKg, set.reps);
        final current = best[set.exerciseId]![week];
        if (current == null || e1rm > current) {
          best[set.exerciseId]![week] = e1rm;
        }
      }
    }
    final weeks = <DateTime>{
      for (final lift in _mainLifts) ...best[lift]!.keys,
    }.toList()
      ..sort();
    final shownWeeks = weeks.length > 8 ? weeks.sublist(weeks.length - 8) : weeks;
    if (shownWeeks.isEmpty) {
      return SizedBox(
        height: 180,
        child: _EmptyCard(
          text: 'No completed main-lift sets yet. Log a squat, bench or deadlift workout to see your trend.',
          actionLabel: 'Start a workout',
          onAction: () => Navigator.of(context).pushNamed('/runner'),
        ),
      );
    }
    double display(double kg) =>
        units == 'lb' ? StrengthMath.kgToLb(kg) : kg;
    final colors = {
      'squat': ForgeTheme.liftSquat,
      'bench': ForgeTheme.liftBench,
      'deadlift': ForgeTheme.liftDeadlift,
    };
    final lineBars = <LineChartBarData>[];
    final chartLifts = <String>[];
    double? minY;
    double? maxY;
    for (final lift in _mainLifts) {
      final spots = <FlSpot>[];
      for (var i = 0; i < shownWeeks.length; i++) {
        final value = best[lift]![shownWeeks[i]];
        if (value == null) continue;
        final y = display(value);
        spots.add(FlSpot(i.toDouble(), y));
        minY = minY == null ? y : (y < minY ? y : minY);
        maxY = maxY == null ? y : (y > maxY ? y : maxY);
      }
      if (spots.length < 2) continue;
      chartLifts.add(lift);
      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: colors[lift],
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }
    if (lineBars.isEmpty) {
      return SizedBox(
        height: 180,
        child: _EmptyCard(
          text: 'Not enough data yet — log at least two weeks of main lifts to see a trend line.',
          actionLabel: 'Start a workout',
          onAction: () => Navigator.of(context).pushNamed('/runner'),
        ),
      );
    }
    final lo = minY!;
    final hi = maxY!;
    final pad = ((hi - lo) * 0.1).clamp(5.0, 50.0);
    final chartMinY = lo - pad < 0 ? 0.0 : lo - pad;
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              child: LineChart(
                LineChartData(
                  minY: chartMinY,
                  maxY: hi + pad,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: ForgeTheme.divider,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, _) => Text(
                          value.toStringAsFixed(0),
                          style: ForgeTheme.captionMuted,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          final i = value.toInt();
                          if (i < 0 || i >= shownWeeks.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat('MMM d').format(shownWeeks[i]),
                              style: ForgeTheme.captionMuted,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: lineBars,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map(
                            (s) => LineTooltipItem(
                              '${_liftName(chartLifts[s.barIndex])}: ${s.y.toStringAsFixed(1)} $units',
                              ForgeTheme.bodyMedium,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: ForgeTheme.liftSquat, label: 'Squat'),
            SizedBox(width: 16),
            _LegendDot(color: ForgeTheme.liftBench, label: 'Bench'),
            SizedBox(width: 16),
            _LegendDot(color: ForgeTheme.liftDeadlift, label: 'Deadlift'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: ForgeTheme.bodyMuted),
      ],
    );
  }
}

/// Total volume per ISO week (last 8 weeks with workouts).
class _VolumeChart extends StatelessWidget {
  final List<WorkoutSession> workouts;
  final String units;

  const _VolumeChart({required this.workouts, required this.units});

  @override
  Widget build(BuildContext context) {
    final Map<DateTime, double> perWeek = {};
    for (final session in workouts) {
      if (session.status != 'completed') continue;
      final week = _weekStart(session.date);
      final volume =
          session.totalVolumeKg > 0 ? session.totalVolumeKg : session.computedVolumeKg;
      perWeek[week] = (perWeek[week] ?? 0) + volume;
    }
    final weeks = perWeek.keys.toList()..sort();
    final shownWeeks = weeks.length > 8 ? weeks.sublist(weeks.length - 8) : weeks;
    if (shownWeeks.isEmpty) {
      return SizedBox(
        height: 180,
        child: _EmptyCard(
          text: 'No completed workouts yet. Finish a workout to see your weekly volume.',
          actionLabel: 'Start a workout',
          onAction: () => Navigator.of(context).pushNamed('/runner'),
        ),
      );
    }
    double display(double kg) =>
        units == 'lb' ? StrengthMath.kgToLb(kg) : kg;
    final maxY = shownWeeks
        .map((w) => display(perWeek[w]!))
        .reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          child: BarChart(
            BarChartData(
              maxY: maxY * 1.15,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: ForgeTheme.divider,
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, _) => Text(
                      value >= 1000
                          ? '${(value / 1000).toStringAsFixed(1)}k'
                          : value.toStringAsFixed(0),
                      style: ForgeTheme.captionMuted,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final i = value.toInt();
                      if (i < 0 || i >= shownWeeks.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          DateFormat('MMM d').format(shownWeeks[i]),
                          style: ForgeTheme.captionMuted,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < shownWeeks.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: display(perWeek[shownWeeks[i]]!),
                        color: ForgeTheme.accent,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
              ],
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                    '${formatWeight(perWeek[shownWeeks[group.x]]!, units)} total volume',
                    ForgeTheme.bodyMedium,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bodyweight line chart + add-entry button.
class _BodyweightCard extends StatelessWidget {
  final List<BodyweightEntry> entries;
  final String units;
  final VoidCallback onAdd;

  const _BodyweightCard({
    required this.entries,
    required this.units,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entries.isEmpty)
              const Text(
                'No bodyweight entries yet. Log your weight to track it over time and power your DOTS score.',
                style: ForgeTheme.bodyMuted,
              )
            else ...[
              Text(
                'Latest: ${formatWeight(entries.last.weightKg, units)} — ${DateFormat('MMM d, yyyy').format(entries.last.date)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: _BodyweightChart(entries: entries, units: units),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add bodyweight'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyweightChart extends StatelessWidget {
  final List<BodyweightEntry> entries;
  final String units;

  const _BodyweightChart({required this.entries, required this.units});

  @override
  Widget build(BuildContext context) {
    double display(double kg) =>
        units == 'lb' ? StrengthMath.kgToLb(kg) : kg;
    final spots = <FlSpot>[];
    for (var i = 0; i < entries.length; i++) {
      spots.add(FlSpot(i.toDouble(), display(entries[i].weightKg)));
    }
    final values = spots.map((s) => s.y).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY) * 0.2).clamp(1.0, 10.0);
    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(
            color: ForgeTheme.divider,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, _) => Text(
                value.toStringAsFixed(1),
                style: ForgeTheme.captionMuted,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= entries.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM d').format(entries[i].date),
                    style: ForgeTheme.captionMuted,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: ForgeTheme.accent,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
    );
  }
}

/// Manual bodyweight entry dialog. Returns the entry (weight stored in kg).
Future<BodyweightEntry?> _showAddBodyweightDialog(
  BuildContext context,
  String units,
) async {
  final result = await showDialog<_BodyweightResult>(
    context: context,
    builder: (context) => _AddBodyweightDialog(units: units),
  );
  if (result == null) return null;
  final input = double.tryParse(result.weight.trim());
  if (input == null || input <= 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid weight.')),
      );
    }
    return null;
  }
  final weightKg = units == 'lb' ? StrengthMath.lbToKg(input) : input;
  return BodyweightEntry(
    id: 'bw_${DateTime.now().millisecondsSinceEpoch}',
    date: result.date,
    weightKg: weightKg,
  );
}

/// What the bodyweight dialog pops with: the raw entered weight
/// (display units) and the picked date. The caller parses, validates
/// and converts, exactly as before.
typedef _BodyweightResult = ({String weight, DateTime date});

/// Bodyweight dialog: owns its controller (the old
/// _showAddBodyweightDialog created one and never disposed it — a
/// leak) and keeps the picked date as dialog state.
class _AddBodyweightDialog extends StatefulWidget {
  const _AddBodyweightDialog({required this.units});

  final String units;

  @override
  State<_AddBodyweightDialog> createState() => _AddBodyweightDialogState();
}

class _AddBodyweightDialogState extends State<_AddBodyweightDialog> {
  late final TextEditingController _weightController;
  var _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController();
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add bodyweight'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _weightController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Weight (${widget.units})',
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today,
                color: ForgeTheme.accent),
            title: Text(DateFormat('EEE, MMM d, yyyy').format(_date)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null && mounted) {
                setState(() => _date = picked);
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            weight: _weightController.text,
            date: _date,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
