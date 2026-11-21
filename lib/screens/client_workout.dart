import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../models/workout.dart';
import '../theme.dart';
import '../widgets/side_pill.dart';
import 'exercise_library.dart';

/// Coach view of a client's finished workout: every exercise's sets
/// (weight × reps, RPE, bar speed) and set videos, tap to play.
/// Read-only — the coach cannot edit or delete anything here.
class ClientWorkoutScreen extends StatelessWidget {
  final WorkoutSession session;
  final String clientName;

  const ClientWorkoutScreen({
    super.key,
    required this.session,
    required this.clientName,
  });

  Map<String, List<SessionSet>> get _grouped {
    final map = <String, List<SessionSet>>{};
    for (final set in session.sets) {
      map.putIfAbsent(set.name, () => []).add(set);
    }
    return map;
  }

  String _duration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(session.title),
        actions: const [
          SidePill(),
          SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '$clientName · ${DateFormat.MMMd().add_jm().format(session.date)}',
            style: ForgeTheme.bodyMuted,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _StatChip(
                label: 'Duration',
                value: _duration(session.durationSec),
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Volume',
                value: '${session.totalVolumeKg.toStringAsFixed(0)} kg',
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Sets',
                value:
                    '${session.sets.where((s) => s.completed).length} done',
              ),
            ],
          ),
          if (session.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(session.notes),
              ),
            ),
          ],
          const SizedBox(height: 16),
          ..._grouped.entries.map((entry) {
            final completed =
                entry.value.where((s) => s.completed).toList();
            if (completed.isEmpty) return const SizedBox.shrink();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius:
                          BorderRadius.circular(ForgeTheme.radiusChip),
                      onTap: () => ExerciseLibraryScreen.open(
                        context,
                        exerciseId: completed.first.exerciseId,
                        exerciseName: entry.key,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              entry.key,
                              style: ForgeTheme.titleMediumBold,
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
                    const SizedBox(height: 8),
                    ...completed.map((set) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 44,
                                child: Text(
                                  'Set ${set.setIndex + 1}',
                                  style: ForgeTheme.bodyMuted,
                                ),
                              ),
                              Text(
                                '${set.weightKg.toStringAsFixed(1)} kg × ${set.reps}',
                                style: ForgeTheme.bodyMediumBold,
                              ),
                              if (set.rpe != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  'RPE ${set.rpe!.toStringAsFixed(1)}',
                                  style: ForgeTheme.bodyMuted,
                                ),
                              ],
                              if (set.barSpeed != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  set.barSpeed!,
                                  style: ForgeTheme.bodyMuted,
                                ),
                              ],
                              const Spacer(),
                              if (set.videoUrl != null)
                                IconButton(
                                  icon: const Icon(
                                    Icons.play_circle_fill,
                                    color: ForgeTheme.accent,
                                  ),
                                  tooltip: 'Play set video',
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => _VideoDialog(
                                          videoUrl: set.videoUrl!),
                                    );
                                  },
                                ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: ForgeTheme.card,
          borderRadius: BorderRadius.circular(ForgeTheme.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: ForgeTheme.captionMuted),
            const SizedBox(height: 2),
            Text(value,
                style: ForgeTheme.bodyMediumBold),
          ],
        ),
      ),
    );
  }
}

/// Same pattern as the history screen's video dialog: network video,
/// tap to play/pause.
class _VideoDialog extends StatefulWidget {
  final String videoUrl;

  const _VideoDialog({required this.videoUrl});

  @override
  State<_VideoDialog> createState() => _VideoDialogState();
}

class _VideoDialogState extends State<_VideoDialog> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
          ..initialize().then((_) {
            if (mounted) setState(() => _ready = true);
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ForgeTheme.card,
      child: AspectRatio(
        aspectRatio: _ready && _controller.value.aspectRatio > 0
            ? _controller.value.aspectRatio
            : 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_ready) VideoPlayer(_controller),
            if (!_ready)
              const CircularProgressIndicator(),
            if (_ready)
              IconButton(
                iconSize: 56,
                icon: Icon(
                  _controller.value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: ForgeTheme.text,
                ),
                onPressed: () {
                  setState(() {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}
