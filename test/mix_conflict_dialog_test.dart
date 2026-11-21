import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge/theme.dart';
import 'package:forge/widgets/mix_conflict_dialog.dart';

void main() {
  /// Opens the dialog and returns a reader for the choice it pops with.
  Future<MoveChoice? Function()> openDialog(WidgetTester tester) async {
    MoveChoice? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: ForgeTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<MoveChoice>(
                  context: context,
                  builder: (_) => const MixConflictDialog(
                    movingName: 'D3 · Bench assistance + upper back',
                    occupantName: 'D4 · Deload: 70% of W3 singles',
                    occupantShort: 'D4',
                    targetLabel: 'Sat, Nov 21',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  group('MixConflictDialog', () {
    testWidgets('spaces every element deliberately — no glued buttons, '
        'no dead space', (tester) async {
      await openDialog(tester);

      final mixBox =
          tester.getRect(find.widgetWithText(FilledButton, 'Mix them'));
      final shiftBox = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Shift D4 to another day'),
      );
      final cancelBox =
          tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
      final bodyBox =
          tester.getRect(find.textContaining('Moving D3'));
      // The card is the Material inside the full-screen Dialog route
      // page — find.byType(Dialog) is the whole screen (Nov 19).
      final cardBox = tester.getRect(
        find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first,
      );

      // The gaps are the numbers the dialog owns — not the
      // framework's 4 dp overflow default (Nov 19 screenshot).
      expect(
        mixBox.top - bodyBox.bottom,
        moreOrLessEquals(MixConflictDialog.bodyToActionsGap, epsilon: 0.5),
      );
      expect(
        shiftBox.top - mixBox.bottom,
        moreOrLessEquals(MixConflictDialog.actionGap, epsilon: 0.5),
      );
      expect(
        cancelBox.top - shiftBox.bottom,
        moreOrLessEquals(MixConflictDialog.cancelGap, epsilon: 0.5),
      );
      // The dialog ends 24 dp below Cancel — no dead space.
      expect(
        cardBox.bottom - cancelBox.bottom,
        moreOrLessEquals(24, epsilon: 0.5),
      );
      // The two main actions are the same width: full-width, stacked.
      expect(mixBox.width, moreOrLessEquals(shiftBox.width, epsilon: 0.5));
    });

    testWidgets('tapping Mix pops MoveChoice.mix', (tester) async {
      final readResult = await openDialog(tester);
      await tester.tap(find.text('Mix them'));
      await tester.pumpAndSettle();
      expect(readResult(), MoveChoice.mix);
      expect(find.text('Should we mix?'), findsNothing);
    });

    testWidgets('tapping Shift pops MoveChoice.shift', (tester) async {
      final readResult = await openDialog(tester);
      await tester.tap(find.text('Shift D4 to another day'));
      await tester.pumpAndSettle();
      expect(readResult(), MoveChoice.shift);
    });

    testWidgets('tapping Cancel pops MoveChoice.cancel', (tester) async {
      final readResult = await openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(readResult(), MoveChoice.cancel);
    });
  });
}
