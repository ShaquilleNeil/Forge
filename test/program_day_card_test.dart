import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/theme.dart';
import 'package:forge/widgets/program_day_card.dart';

const _day = ProgramDay(
  id: 'd1',
  title: 'Mon Nov 9 · D1 · Squat + bench',
  dayIndex: 0,
  exercises: [
    ProgramExercise(
      exerciseId: 'squat',
      name: 'Squat, beltless',
      sets: 3,
      repsMin: 4,
      repsMax: 4,
      targetWeightKg: 120,
      targetRpe: '8',
    ),
    ProgramExercise(
      exerciseId: 'bench',
      name: 'Comp bench',
      sets: 2,
      repsMin: 5,
      repsMax: 5,
      targetWeightKg: 97.5,
    ),
  ],
);

Future<void> pumpDayCard(
  WidgetTester tester, {
  bool expanded = false,
  bool isToday = false,
  VoidCallback? onToggle,
  VoidCallback? onRemoveDay,
  VoidCallback? onAddExercise,
  void Function(int)? onEditWeight,
  void Function(int)? onRemoveExercise,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ForgeTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProgramDayCard(
            day: _day,
            isToday: isToday,
            expanded: expanded,
            units: 'kg',
            onToggle: onToggle ?? () {},
            onRemoveDay: onRemoveDay ?? () {},
            onAddExercise: onAddExercise ?? () {},
            onEditWeight: onEditWeight ?? (_) {},
            onRemoveExercise: onRemoveExercise ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ProgramDayCard', () {
    testWidgets('collapsed shows title, summary and preview names',
        (tester) async {
      await pumpDayCard(tester);
      expect(
        find.text('Mon Nov 9 · D1 · Squat + bench'),
        findsOneWidget,
      );
      expect(find.text('2 exercises · 5 sets · ~25 min'), findsOneWidget);
      expect(find.text('Squat, beltless · Comp bench'), findsOneWidget);
      expect(find.text('Add exercise'), findsNothing);
    });

    testWidgets('expanded shows exercises with summaries and actions',
        (tester) async {
      await pumpDayCard(tester, expanded: true);
      expect(find.text('3 × 4 · 120 kg · RPE 8'), findsOneWidget);
      expect(find.text('2 × 5 · 97.5 kg'), findsOneWidget);
      expect(find.text('Add exercise'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    testWidgets('today gets the Today tag', (tester) async {
      await pumpDayCard(tester, isToday: true);
      expect(find.text('Today'), findsOneWidget);
      expect(
        find.text('Today · 2 exercises · 5 sets · ~25 min'),
        findsOneWidget,
      );
    });

    testWidgets('taps call the right callbacks with the right index',
        (tester) async {
      var toggled = false;
      var removedDay = false;
      var added = false;
      var edited = -1;
      var removed = -1;
      await pumpDayCard(
        tester,
        expanded: true,
        onToggle: () => toggled = true,
        onRemoveDay: () => removedDay = true,
        onAddExercise: () => added = true,
        onEditWeight: (i) => edited = i,
        onRemoveExercise: (i) => removed = i,
      );
      await tester.tap(find.text('Mon Nov 9 · D1 · Squat + bench'));
      expect(toggled, isTrue);
      await tester.tap(find.byIcon(Icons.delete_outlined));
      expect(removedDay, isTrue);
      await tester.tap(find.byIcon(Icons.edit_outlined).at(1));
      expect(edited, 1);
      await tester.tap(find.byIcon(Icons.close).at(0));
      expect(removed, 0);
      await tester.tap(find.text('Add exercise'));
      expect(added, isTrue);
    });

    testWidgets('spaces every element deliberately — no glued rows',
        (tester) async {
      await pumpDayCard(tester, expanded: true);
      // Header row (title + delete button + chevron) -> summary line.
      // Measured from the row, not the title text: the delete button
      // makes the row taller than the title itself.
      final headerRow = tester.getRect(
        find
            .ancestor(
              of: find.text('Mon Nov 9 · D1 · Squat + bench'),
              matching: find.byType(Row),
            )
            .first,
      );
      final summary =
          tester.getRect(find.text('2 exercises · 5 sets · ~25 min'));
      expect(
        summary.top - headerRow.bottom,
        ProgramDayCard.gapTitleToSummary,
      );
      // Summary -> preview names.
      final names =
          tester.getRect(find.text('Squat, beltless · Comp bench'));
      expect(
        names.top - summary.bottom,
        ProgramDayCard.gapSummaryToNames,
      );
      // Add exercise button -> card bottom edge. The Card's own box
      // includes its 12px bottom margin, so the surface is the
      // Material inside it.
      final cardSurface = tester.getRect(
        find
            .descendant(
              of: find.byType(Card),
              matching: find.byType(Material),
            )
            .first,
      );
      final addButton = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Add exercise'),
      );
      expect(
        cardSurface.bottom - addButton.bottom,
        ProgramDayCard.addButtonBottomPadding,
      );
    });
  });
}
