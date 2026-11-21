import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/storage_service.dart';
import '../services/video_trim_service.dart';
import '../theme.dart';

/// What the trim screen hands back to the caller.
class TrimResult {
  /// The file to attach — the trimmed cut, or the original when the
  /// full range was kept.
  final String path;

  /// Kept length in seconds.
  final double durationSec;

  /// True when a real cut was made (range shorter than the full clip).
  final bool trimmed;

  const TrimResult({
    required this.path,
    required this.durationSec,
    required this.trimmed,
  });
}

/// Trims a set video in-app: preview, play/pause, and a slider that
/// picks the start and end of the cut to keep. The kept cut must fit
/// inside [StorageService.maxVideoSeconds] — a gallery clip of any
/// length can be cut down to fit.
class VideoTrimScreen extends StatefulWidget {
  final String videoPath;
  final double durationSec;

  const VideoTrimScreen({
    super.key,
    required this.videoPath,
    required this.durationSec,
  });

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  late final VideoPlayerController _controller;
  late RangeValues _range;
  bool _ready = false;
  bool _trimming = false;

  double get _keptSec => _range.end - _range.start;

  bool get _isFullRange =>
      _range.start <= 0 && _range.end >= widget.durationSec - 0.5;

  bool get _keptTooLong =>
      !isTrimWithinLimit(
        _range.start,
        _range.end,
        StorageService.maxVideoSeconds.toDouble(),
      );

  @override
  void initState() {
    super.initState();
    _range = RangeValues(0, widget.durationSec);
    _controller = VideoPlayerController.file(File(widget.videoPath));
    _controller.initialize().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (!_ready) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        // Restart from the cut start when the preview ran past it.
        final pos = _controller.value.position.inMilliseconds / 1000;
        if (pos < _range.start || pos >= _range.end) {
          _controller.seekTo(
            Duration(milliseconds: (_range.start * 1000).round()),
          );
        }
        _controller.play();
      }
    });
  }

  Future<void> _keepCut() async {
    if (_trimming || _keptTooLong) return;
    if (_isFullRange) {
      if (mounted) {
        Navigator.of(context).pop(
          TrimResult(
            path: widget.videoPath,
            durationSec: widget.durationSec,
            trimmed: false,
          ),
        );
      }
      return;
    }
    setState(() => _trimming = true);
    final out = await trimVideo(
      inputPath: widget.videoPath,
      startSec: _range.start,
      endSec: _range.end,
    );
    if (!mounted) return;
    setState(() => _trimming = false);
    if (out == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not cut that video. Try a different range.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      TrimResult(path: out, durationSec: _keptSec, trimmed: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    const maxKept = StorageService.maxVideoSeconds;
    return Scaffold(
      appBar: AppBar(title: const Text('Trim video')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The video takes whatever space is left after the
              // controls below — it shrinks to fit, so nothing scrolls.
              // A tall portrait clip gets a smaller window instead of
              // pushing the slider and buttons off screen.
              Expanded(
                child: Center(
                  child: _ready && _controller.value.aspectRatio > 0
                      ? AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_controller),
                              IconButton(
                                iconSize: 56,
                                icon: Icon(
                                  _controller.value.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                  color: ForgeTheme.text
                                      .withValues(alpha: 0.85),
                                ),
                                onPressed: _togglePlay,
                              ),
                            ],
                          ),
                        )
                      : const AspectRatio(
                          aspectRatio: 16 / 9,
                          child:
                              Center(child: CircularProgressIndicator()),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Drag the handles to choose the cut to keep.',
                style: ForgeTheme.bodyMuted,
              ),
              const SizedBox(height: 8),
              RangeSlider(
                values: _range,
                min: 0,
                max: widget.durationSec,
                divisions: widget.durationSec.ceil().clamp(1, 600),
                labels: RangeLabels(
                  formatMmSs(_range.start),
                  formatMmSs(_range.end),
                ),
                onChanged: (values) => setState(() => _range = values),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Start ${formatMmSs(_range.start)}'),
                  Text(
                    'Kept ${formatMmSs(_keptSec)}',
                    style: ForgeTheme.bodyMediumBold,
                  ),
                  Text('End ${formatMmSs(_range.end)}'),
                ],
              ),
              if (_keptTooLong) ...[
                const SizedBox(height: 8),
                Text(
                  'Cut must be ${formatMmSs(maxKept.toDouble())} or less — '
                  'shorten it.',
                  style: ForgeTheme.errorText,
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _trimming || _keptTooLong ? null : _keepCut,
                  child: Text(
                    _trimming
                        ? 'Cutting video…'
                        : _isFullRange
                            ? 'Keep full video'
                            : 'Keep this cut (${formatMmSs(_keptSec)})',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _trimming
                    ? null
                    : () => Navigator.of(context).pop(
                          TrimResult(
                            path: widget.videoPath,
                            durationSec: widget.durationSec,
                            trimmed: false,
                          ),
                        ),
                child: const Text('Use full video'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
