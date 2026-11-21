import 'package:flutter/material.dart';

import '../theme.dart';

/// The state of one set in the active workout.
enum SetRowState {
  /// Not logged yet, and not the set the lifter is on.
  pending,

  /// The one set the lifter is on right now — the only row with an
  /// orange border in the whole workout.
  current,

  /// Logged (weight + reps saved, rest timer started).
  done,

  /// Deliberately not done this session.
  skipped,
}

/// One compact set row in the active workout — a single 56dp line:
///
///   Set # | Previous | kg | Reps | video | check
///
/// Stateless: every interaction goes out through callbacks and the
/// parent owns the session data. The weight field carries a small
/// plate icon (when [showPlates] is true) that opens the plate
/// calculator; tapping the weight or reps value opens the set editor.
/// Skip is swipe-left or long-press on the row. A set with a video
/// attached shows a small camera icon in the video column (the space
/// is always reserved so rows stay aligned).
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.setNumber,
    required this.state,
    required this.weightLabel,
    required this.reps,
    this.previousLabel,
    this.hasVideo = false,
    this.showPlates = true,
    required this.onComplete,
    required this.onSkip,
    required this.onWeightTap,
    required this.onRepsTap,
    required this.onPreviousTap,
    this.onPlatesTap,
  }) : assert(key != null, 'SetRow needs a key: swipe-to-skip uses it.');

  /// 1-based set number within the exercise.
  final int setNumber;

  final SetRowState state;

  /// Weight text, e.g. "120 kg" or "BW".
  final String weightLabel;

  final int reps;

  /// Last session's result for this set, e.g. "117.5 × 4".
  /// Null when there is no previous performance to show.
  final String? previousLabel;

  /// A video is attached to this set (local file or uploaded URL).
  /// Shows a small camera icon in the video column.
  final bool hasVideo;

  /// Show the plate-calculator icon in the weight field. Hide it for
  /// bodyweight sets and machine-based exercises.
  final bool showPlates;

  /// Log the set (or re-log a skipped set).
  final VoidCallback onComplete;

  /// Skip the set (swipe left or long-press).
  final VoidCallback onSkip;

  /// Open the set editor (weight steppers).
  final VoidCallback onWeightTap;

  /// Open the set editor (reps steppers).
  final VoidCallback onRepsTap;

  /// Copy the previous performance into this set.
  final VoidCallback onPreviousTap;

  /// Open the plate calculator for this set. Extra callback beyond
  /// the five in the spec — the plate icon needs its own target.
  final VoidCallback? onPlatesTap;

  // Column geometry — SetRowHeader uses the same constants so the
  // header labels line up with the row cells.
  static const double setNumberWidth = 24;
  static const double checkSize = 48;
  static const double videoWidth = 20;
  static const double columnGap = 6;

  bool get _isDone => state == SetRowState.done;
  bool get _isSkipped => state == SetRowState.skipped;
  bool get _isCurrent => state == SetRowState.current;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isDone
            ? ForgeTheme.green.withValues(alpha: 0.12)
            : ForgeTheme.surface,
        borderRadius: BorderRadius.circular(ForgeTheme.radius),
        border: _isCurrent
            ? Border.all(color: ForgeTheme.accent, width: 2)
            : null,
      ),
      child: Opacity(
        opacity: _isSkipped ? 0.5 : 1,
        child: Row(
          children: [
            SizedBox(
              width: setNumberWidth,
              child: Text(
                '$setNumber',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      _isCurrent ? FontWeight.w700 : FontWeight.normal,
                  color:
                      _isCurrent ? ForgeTheme.accent : ForgeTheme.muted,
                ),
              ),
            ),
            const SizedBox(width: columnGap),
            Expanded(
              flex: 2,
              child: _PreviousCell(
                label: previousLabel,
                onTap: previousLabel == null ? null : onPreviousTap,
              ),
            ),
            const SizedBox(width: columnGap),
            Expanded(
              flex: 4,
              child: _ValueField(
                label: weightLabel,
                onTap: onWeightTap,
                showPlates: showPlates,
                onPlatesTap: onPlatesTap,
              ),
            ),
            const SizedBox(width: columnGap),
            Expanded(
              flex: 2,
              child: _ValueField(
                label: '$reps',
                onTap: onRepsTap,
                centered: true,
              ),
            ),
            const SizedBox(width: columnGap),
            SizedBox(
              width: videoWidth,
              child: hasVideo
                  ? const Tooltip(
                      message: 'Video attached',
                      child: Icon(
                        Icons.videocam,
                        size: 18,
                        color: ForgeTheme.muted,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: columnGap),
            SizedBox(
              width: checkSize,
              height: checkSize,
              child: IconButton(
                onPressed: _isDone ? null : onComplete,
                // 200ms scale-in on the check when a set is logged.
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    key: ValueKey(_isDone),
                    _isDone
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color: _isDone ? ForgeTheme.green : ForgeTheme.muted,
                    size: 28,
                  ),
                ),
                tooltip: _isDone
                    ? 'Set logged'
                    : _isSkipped
                        ? 'Log skipped set'
                        : 'Log set $setNumber',
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );

    // Skip: swipe left, or long-press. A long-press on a logged set
    // does nothing; a skipped set is re-logged with its check button.
    return GestureDetector(
      onLongPress: _isDone ? null : onSkip,
      child: Dismissible(
        key: key!,
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: ForgeTheme.red.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(ForgeTheme.radius),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.skip_next, color: ForgeTheme.red, size: 20),
              SizedBox(width: 4),
              Text(
                'Skip',
                style: ForgeTheme.errorText,
              ),
            ],
          ),
        ),
        confirmDismiss: (_) async {
          if (_isDone) return false;
          onSkip();
          return false;
        },
        child: row,
      ),
    );
  }
}

/// Column headers for the set rows — same geometry as [SetRow] so the
/// labels line up with the cells. Shown once at the top of each
/// exercise card.
class SetRowHeader extends StatelessWidget {
  const SetRowHeader({super.key});

  static const _labelStyle = ForgeTheme.captionSemibold;

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: SetRow.setNumberWidth,
            child: Text('Set', textAlign: TextAlign.center, style: _labelStyle),
          ),
          SizedBox(width: SetRow.columnGap),
          Expanded(
            flex: 2,
            child: Text('Previous', style: _labelStyle),
          ),
          SizedBox(width: SetRow.columnGap),
          Expanded(
            flex: 4,
            child: Padding(
              padding: EdgeInsets.only(left: 10),
              child: Text('kg', style: _labelStyle),
            ),
          ),
          SizedBox(width: SetRow.columnGap),
          Expanded(
            flex: 2,
            child: Text('Reps', textAlign: TextAlign.center, style: _labelStyle),
          ),
          SizedBox(width: SetRow.columnGap),
          SizedBox(width: SetRow.videoWidth),
          SizedBox(width: SetRow.columnGap),
          SizedBox(width: SetRow.checkSize),
        ],
      ),
    );
  }
}

/// Last session's result for this set ("117.5 × 4"), muted gray.
/// Tapping it copies those values into the set. Shows "—" when
/// there is no previous performance.
class _PreviousCell extends StatelessWidget {
  const _PreviousCell({required this.label, required this.onTap});

  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label ?? '—',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ForgeTheme.bodyMuted.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (onTap == null) {
      return Align(alignment: Alignment.centerLeft, child: text);
    }
    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Align(alignment: Alignment.centerLeft, child: text),
        ),
      ),
    );
  }
}

/// A neutral dark-gray value field with white text and no orange
/// outline — weight or reps. Tapping opens the set editor. The weight
/// field can carry a small plate icon at its right edge that opens
/// the plate calculator instead.
class _ValueField extends StatelessWidget {
  const _ValueField({
    required this.label,
    required this.onTap,
    this.centered = false,
    this.showPlates = false,
    this.onPlatesTap,
  });

  final String label;
  final VoidCallback onTap;
  final bool centered;
  final bool showPlates;
  final VoidCallback? onPlatesTap;

  @override
  Widget build(BuildContext context) {
    final hasPlates = showPlates && onPlatesTap != null;
    final value = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: ForgeTheme.titleMediumBoldTabular,
      ),
    );
    final textCell = Material(
      color: ForgeTheme.card,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.horizontal(
        left: const Radius.circular(8),
        right: Radius.circular(hasPlates ? 0 : 8),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Align(
            alignment:
                centered ? Alignment.center : Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: centered ? 0 : 10, right: 4),
              child: value,
            ),
          ),
        ),
      ),
    );
    if (!hasPlates) return textCell;
    return Row(
      children: [
        Expanded(child: textCell),
        Material(
          color: ForgeTheme.card,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(8),
          ),
          child: InkWell(
            onTap: onPlatesTap,
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.layers,
                size: 20,
                color: ForgeTheme.muted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
