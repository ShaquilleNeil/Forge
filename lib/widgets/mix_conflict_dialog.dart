import 'package:flutter/material.dart';

/// What the user picked in the mix/shift dialog.
enum MoveChoice { mix, shift, cancel }

/// "Should we mix?" — shown when a workout is moved onto a day that
/// already has one.
///
/// Layout rule (Nov 19, from a phone screenshot): this dialog owns
/// every gap itself. The old version put the three buttons in
/// AlertDialog.actions, which stacks them with the framework's
/// default overflow spacing — 4 dp — so Mix and Shift looked glued
/// together, with dead space below Cancel. Nothing here relies on
/// a default: title, body and buttons live in one Column with a
/// named gap between each pair, and the dialog's own paddings are
/// set explicitly.
class MixConflictDialog extends StatelessWidget {
  /// Gap between the body text and the first button. The decision
  /// needs air after the explanation.
  static const double bodyToActionsGap = 24;

  /// Gap between the two main actions. They are both 52 dp tall and
  /// full-width, so they need a real gap or they read as one block.
  static const double actionGap = 12;

  /// Gap before Cancel. It is the quiet way out, so it sits a little
  /// closer to the actions than they sit to each other.
  static const double cancelGap = 8;

  const MixConflictDialog({
    super.key,
    required this.movingName,
    required this.occupantName,
    required this.occupantShort,
    required this.targetLabel,
  });

  final String movingName;
  final String occupantName;
  final String occupantShort;
  final String targetLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Should we mix?'),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Moving $movingName to $targetLabel, but that day already '
            'has $occupantName. Mix them into one long workout, or '
            'shift $occupantName to another day?',
          ),
          const SizedBox(height: bodyToActionsGap),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(MoveChoice.mix),
              child: const Text('Mix them'),
            ),
          ),
          const SizedBox(height: actionGap),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).pop(MoveChoice.shift),
              child: Text('Shift $occupantShort to another day'),
            ),
          ),
          const SizedBox(height: cancelGap),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(MoveChoice.cancel),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}
