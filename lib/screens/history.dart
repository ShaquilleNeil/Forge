import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../models/user_profile.dart';
import '../models/workout.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/strength_math.dart';
import '../theme.dart';
import '../widgets/skeleton.dart';

/// History: month calendar strip + session list (newest first).
/// Tap a session for the detail view with per-set edit / delete.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final FirestoreService _db = FirestoreService();
  final AuthService _auth = AuthService();

  /// Day (date-only) the list is filtered to, or null for all days.
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('History')),
        body: const Center(child: Text('Sign in to see your history.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: StreamBuilder<UserProfile?>(
        stream: _db.watchProfile(uid),
        builder: (context, profileSnap) {
          final units = profileSnap.data?.units ?? 'kg';
          return StreamBuilder<List<WorkoutSession>>(
            stream: _db.watchWorkouts(uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const HistorySkeleton();
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Could not load your history: ${snap.error}',
                          textAlign: TextAlign.center,
                          style: ForgeTheme.errorText,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final sessions = snap.data ?? [];
              final completed =
                  sessions.where((s) => s.status == 'completed').toList();
              final visible = _selectedDay == null
                  ? sessions
                  : sessions
                      .where((s) => _isSameDay(s.date, _selectedDay!))
                      .toList();
              return Column(
                children: [
                  _MonthStrip(
                    month: DateTime.now(),
                    workoutDays: {
                      for (final s in completed)
                        DateTime(s.date.year, s.date.month, s.date.day),
                    },
                    selectedDay: _selectedDay,
                    emptyVisible: visible.isEmpty,
                    onDayTap: (day) {
                      setState(() {
                        _selectedDay =
                            _isSameDay(day, _selectedDay ?? DateTime(0))
                                ? null
                                : day;
                      });
                    },
                  ),
                  if (_selectedDay != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        children: [
                          Chip(
                            label: Text(
                              DateFormat('EEE, MMM d').format(_selectedDay!),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 18),
                            onDeleted: () =>
                                setState(() => _selectedDay = null),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: visible.isEmpty
                        ? _EmptyState(
                            filtered: _selectedDay != null,
                            onClearFilter: () =>
                                setState(() => _selectedDay = null),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: visible.length,
                            itemBuilder: (context, i) {
                              final session = visible[i];
                              return _SessionRow(
                                session: session,
                                units: units,
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => _SessionDetailScreen(
                                        session: session,
                                        units: units,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Formats a stored-kg weight in the user's display units.
String formatWeight(double kg, String units) {
  if (units == 'lb') {
    return '${StrengthMath.kgToLb(kg).toStringAsFixed(1)} lb';
  }
  return '${kg.toStringAsFixed(kg.truncateToDouble() == kg ? 0 : 1)} kg';
}

String _formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

/// Heaviest completed set per exercise, e.g. "Squat 180 × 1 · Bench 120 × 1".
String topSetsSummary(WorkoutSession session, String units) {
  final best = <String, SessionSet>{};
  for (final set in session.sets) {
    if (!set.completed) continue;
    final current = best[set.name];
    if (current == null || set.weightKg > current.weightKg) {
      best[set.name] = set;
    }
  }
  return best.values
      .take(3)
      .map((s) => '${s.name} ${formatWeight(s.weightKg, units)} × ${s.reps}')
      .join(' · ');
}

class _EmptyState extends StatelessWidget {
  final bool filtered;
  final VoidCallback onClearFilter;

  const _EmptyState({required this.filtered, required this.onClearFilter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filtered
                  ? 'No workout on this day.'
                  : 'No workouts yet.',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (filtered)
              OutlinedButton(
                onPressed: onClearFilter,
                child: const Text('Show all sessions'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.of(context).pushNamed('/runner'),
                child: const Text('Start a workout'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal strip of the current month; dots mark days with a workout.
/// Opens scrolled to today, not the 1st.
class _MonthStrip extends StatefulWidget {
  final DateTime month;
  final Set<DateTime> workoutDays;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDayTap;
  /// True while the empty state is showing below the strip (no sessions
  /// for the selected day, or none at all). The selected cell is an
  /// accent outline then, so the empty state's action is the one solid
  /// accent on screen.
  final bool emptyVisible;

  const _MonthStrip({
    required this.month,
    required this.workoutDays,
    required this.selectedDay,
    required this.onDayTap,
    this.emptyVisible = false,
  });

  @override
  State<_MonthStrip> createState() => _MonthStripState();
}

class _MonthStripState extends State<_MonthStrip> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // One day cell is 48 wide + 3 padding each side = 54. Start with
    // today a few cells in from the left edge.
    final daysInMonth =
        DateTime(widget.month.year, widget.month.month + 1, 0).day;
    final today = DateTime.now();
    final maxOffset =
        ((daysInMonth - 6) * 54).clamp(0, 1 << 20).toDouble();
    var offset = ((today.day - 4) * 54).toDouble();
    if (offset < 0) offset = 0;
    if (offset > maxOffset) offset = maxOffset;
    _scrollController = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final month = widget.month;
    final workoutDays = widget.workoutDays;
    final selectedDay = widget.selectedDay;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final today = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(month),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${workoutDays.length} days trained',
                style: ForgeTheme.bodyMuted,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 64,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: daysInMonth,
            itemBuilder: (context, i) {
              final day = DateTime(month.year, month.month, i + 1);
              final hasWorkout = workoutDays.contains(day);
              final isToday = _isSameDay(day, today);
              final isSelected =
                  selectedDay != null && _isSameDay(day, selectedDay);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(ForgeTheme.radius),
                  onTap: () => widget.onDayTap(day),
                  child: Container(
                    width: 48,
                    decoration: BoxDecoration(
                      color: isSelected && !widget.emptyVisible
                          ? ForgeTheme.accent
                          : ForgeTheme.card,
                      borderRadius: BorderRadius.circular(ForgeTheme.radius),
                      border: (isToday && !isSelected) ||
                              (isSelected && widget.emptyVisible)
                          ? Border.all(color: ForgeTheme.accent)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('EEE').format(day).substring(0, 2),
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected && !widget.emptyVisible
                                ? ForgeTheme.scaffoldBg
                                : isSelected
                                    ? ForgeTheme.accent
                                    : ForgeTheme.muted,
                          ),
                        ),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected && !widget.emptyVisible
                                ? ForgeTheme.scaffoldBg
                                : isSelected
                                    ? ForgeTheme.accent
                                    : ForgeTheme.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasWorkout
                                ? (isSelected && !widget.emptyVisible
                                    ? ForgeTheme.scaffoldBg
                                    : ForgeTheme.accent)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            selectedDay == null
                ? 'Tap a day to filter'
                : 'Tap again to clear',
            style: ForgeTheme.captionMuted,
          ),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  final WorkoutSession session;
  final String units;
  final VoidCallback onTap;

  const _SessionRow({
    required this.session,
    required this.units,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final volume = session.totalVolumeKg > 0
        ? session.totalVolumeKg
        : session.computedVolumeKg;
    final summary = topSetsSummary(session, units);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.title.isEmpty ? 'Workout' : session.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (session.status != 'completed')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: ForgeTheme.accentTint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'In progress',
                        style: ForgeTheme.captionAccentLight,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEE, MMM d, yyyy').format(session.date),
                style: ForgeTheme.bodyMuted,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _StatChip(
                    icon: Icons.fitness_center,
                    label: 'Volume ${formatWeight(volume, units)}',
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    icon: Icons.timer_outlined,
                    label: _formatDuration(session.durationSec),
                  ),
                ],
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(summary, style: ForgeTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ForgeTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ForgeTheme.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ForgeTheme.muted),
          const SizedBox(width: 4),
          Text(label, style: ForgeTheme.captionMuted),
        ],
      ),
    );
  }
}

/// Detail view: all sets grouped by exercise, with edit / delete.
class _SessionDetailScreen extends StatefulWidget {
  final WorkoutSession session;
  final String units;

  const _SessionDetailScreen({required this.session, required this.units});

  @override
  State<_SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<_SessionDetailScreen> {
  final FirestoreService _db = FirestoreService();
  final AuthService _auth = AuthService();
  late WorkoutSession _session;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
  }

  Map<String, List<SessionSet>> get _grouped {
    final map = <String, List<SessionSet>>{};
    for (final set in _session.sets) {
      map.putIfAbsent(set.name, () => []).add(set);
    }
    return map;
  }

  Future<void> _persist(WorkoutSession updated) async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await _db.saveWorkout(uid, updated);
      if (mounted) setState(() => _session = updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editSet(SessionSet set) async {
    final result = await showDialog<_EditSetResult>(
      context: context,
      builder: (context) => _EditSetDialog(set: set, units: widget.units),
    );
    if (result == null) return;
    final weightInput = double.tryParse(result.weight.trim());
    final reps = int.tryParse(result.reps.trim());
    if (weightInput == null || reps == null || reps <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid weight and reps.')),
        );
      }
      return;
    }
    final weightKg = widget.units == 'lb'
        ? StrengthMath.lbToKg(weightInput)
        : weightInput;
    final rpe = double.tryParse(result.rpe.trim());
    final barSpeed = result.barSpeed;
    // Rebuild the edited set directly: copyWith cannot clear rpe/barSpeed.
    final rebuilt = _session.sets.map((s) {
      if (identical(s, set)) {
        return SessionSet(
          exerciseId: s.exerciseId,
          name: s.name,
          setIndex: s.setIndex,
          weightKg: weightKg,
          reps: reps,
          rpe: rpe,
          barSpeed: barSpeed,
          completed: s.completed,
          videoPath: s.videoPath,
          videoUrl: s.videoUrl,
        );
      }
      return s;
    }).toList();
    await _persist(
      _session.copyWith(
        sets: rebuilt,
        totalVolumeKg: rebuilt
            .where((s) => s.completed)
            .fold<double>(0.0, (sum, s) => sum + s.volumeKg),
      ),
    );
  }

  Future<void> _deleteSet(SessionSet set) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete set?'),
        content: Text(
          'Delete ${set.name} — ${formatWeight(set.weightKg, widget.units)} × ${set.reps}?',
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
    final remaining =
        _session.sets.where((s) => !identical(s, set)).toList();
    // Re-index sets within each exercise so setIndex stays 0-based.
    final counters = <String, int>{};
    final reindexed = remaining.map((s) {
      final next = counters[s.exerciseId] ?? 0;
      counters[s.exerciseId] = next + 1;
      return SessionSet(
        exerciseId: s.exerciseId,
        name: s.name,
        setIndex: next,
        weightKg: s.weightKg,
        reps: s.reps,
        rpe: s.rpe,
        barSpeed: s.barSpeed,
        completed: s.completed,
        videoPath: s.videoPath,
        videoUrl: s.videoUrl,
      );
    }).toList();
    await _persist(
      _session.copyWith(
        sets: reindexed,
        totalVolumeKg: reindexed
            .where((s) => s.completed)
            .fold<double>(0.0, (sum, s) => sum + s.volumeKg),
      ),
    );
  }

  Future<void> _deleteSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete workout?'),
        content: Text(
          'Delete "${_session.title}" from ${DateFormat('MMM d, yyyy').format(_session.date)}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ForgeTheme.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete workout'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final uid = _auth.currentUid;
    if (uid == null) return;
    try {
      await _db.deleteWorkout(uid, _session.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final volume = _session.totalVolumeKg > 0
        ? _session.totalVolumeKg
        : _session.computedVolumeKg;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _session.title.isEmpty ? 'Workout' : _session.title,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete workout',
            onPressed: _saving ? null : _deleteSession,
          ),
        ],
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : grouped.isEmpty
              ? const Center(
                  child: Text(
                    'This workout has no sets yet.',
                    style: ForgeTheme.bodyMuted,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Row(
                      children: [
                        _StatChip(
                          icon: Icons.calendar_today,
                          label: DateFormat('EEE, MMM d, yyyy')
                              .format(_session.date),
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.fitness_center,
                          label:
                              'Volume ${formatWeight(volume, widget.units)}',
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.timer_outlined,
                          label: _formatDuration(_session.durationSec),
                        ),
                      ],
                    ),
                    if (_session.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_session.notes),
                    ],
                    const SizedBox(height: 16),
                    for (final entry in grouped.entries) ...[
                      Text(
                        entry.key,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      for (final set in entry.value)
                        _SetRow(
                          set: set,
                          units: widget.units,
                          onEdit: () => _editSet(set),
                          onDelete: () => _deleteSet(set),
                          onPlayVideo: set.videoUrl != null
                              ? () => _playVideo(context, set.videoUrl!)
                              : null,
                        ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
    );
  }

  void _playVideo(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (context) => _VideoDialog(videoUrl: url),
    );
  }
}

String _trimKg(double kg) =>
    kg.truncateToDouble() == kg ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);

/// What the edit-set dialog pops with: the raw entered text (display
/// units) plus the picked bar speed, or null when cancelled. The
/// caller parses and validates, exactly as before.
typedef _EditSetResult = ({
  String weight,
  String reps,
  String rpe,
  String? barSpeed,
});

/// Edit-set dialog: owns its three controllers (the old _editSet
/// created them in the caller and never disposed them — a leak — and
/// read them after the dialog closed). Content scrolls (P3): three
/// fields plus a dropdown overflowed on short screens.
class _EditSetDialog extends StatefulWidget {
  const _EditSetDialog({required this.set, required this.units});

  final SessionSet set;
  final String units;

  @override
  State<_EditSetDialog> createState() => _EditSetDialogState();
}

class _EditSetDialogState extends State<_EditSetDialog> {
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  late final TextEditingController _rpeController;
  String? _barSpeed;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(
      text: widget.units == 'lb'
          ? StrengthMath.kgToLb(widget.set.weightKg).toStringAsFixed(1)
          : _trimKg(widget.set.weightKg),
    );
    _repsController =
        TextEditingController(text: widget.set.reps.toString());
    _rpeController =
        TextEditingController(text: widget.set.rpe?.toString() ?? '');
    _barSpeed = widget.set.barSpeed;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _rpeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit set — ${widget.set.name}'),
      content: SingleChildScrollView(
        child: Column(
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
            TextField(
              controller: _repsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reps'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rpeController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'RPE (optional)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _barSpeed,
              decoration:
                  const InputDecoration(labelText: 'Bar speed'),
              items: const ['Fast', 'Normal', 'Slow', 'Grind']
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _barSpeed = v),
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
          onPressed: () => Navigator.of(context).pop((
            weight: _weightController.text,
            reps: _repsController.text,
            rpe: _rpeController.text,
            barSpeed: _barSpeed,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _SetRow extends StatelessWidget {
  final SessionSet set;
  final String units;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onPlayVideo;

  const _SetRow({
    required this.set,
    required this.units,
    required this.onEdit,
    required this.onDelete,
    this.onPlayVideo,
  });

  @override
  Widget build(BuildContext context) {
    final details = <String>[];
    if (set.rpe != null) details.add('RPE ${set.rpe}');
    if (set.barSpeed != null) details.add(set.barSpeed!);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: ForgeTheme.surface,
          foregroundColor: ForgeTheme.accent,
          child: Text('${set.setIndex + 1}'),
        ),
        title: Text(
          '${formatWeight(set.weightKg, units)} × ${set.reps}',
        ),
        subtitle: details.isEmpty
            ? null
            : Text(details.join(' · '),
                style: ForgeTheme.bodyMuted),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onPlayVideo != null)
              IconButton(
                icon: const Icon(Icons.play_circle_fill),
                color: ForgeTheme.accent,
                tooltip: 'Play set video',
                onPressed: onPlayVideo,
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit set',
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: ForgeTheme.red,
              tooltip: 'Delete set',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple video player dialog for a set's recorded video.
class _VideoDialog extends StatefulWidget {
  final String videoUrl;

  const _VideoDialog({required this.videoUrl});

  @override
  State<_VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<_VideoDialog> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((Object _) {
        if (mounted) setState(() => _failed = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set video'),
      content: SizedBox(
        width: double.maxFinite,
        child: _failed
            ? const Text(
                'Could not load this video.',
                style: ForgeTheme.errorText,
              )
            : _controller.value.isInitialized
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                      const SizedBox(height: 8),
                      IconButton(
                        icon: Icon(
                          _controller.value.isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          size: 40,
                          color: ForgeTheme.accent,
                        ),
                        onPressed: () {
                          setState(() {
                            _controller.value.isPlaying
                                ? _controller.pause()
                                : _controller.play();
                          });
                        },
                      ),
                    ],
                  )
                : const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
