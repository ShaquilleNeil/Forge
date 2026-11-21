import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/theme.dart';
import 'package:forge/widgets/coach_program_card.dart';

Program program({
  List<String> sentTo = const [],
  String? description,
  String? sheetId,
}) =>
    Program(
      id: 'p',
      userId: 'u',
      name: 'Beginner Strength',
      description: description,
      weeks: const [
        ProgramWeek(id: 'w1', title: 'W1', weekIndex: 0, days: [
          ProgramDay(
            id: 'd1',
            title: 'Day 1',
            dayIndex: 0,
            exercises: [
              ProgramExercise(
                exerciseId: 'squat',
                name: 'Squat',
                sets: 3,
              ),
            ],
          ),
        ]),
        ProgramWeek(id: 'w2', title: 'W2', weekIndex: 1, days: [
          ProgramDay(
            id: 'd2',
            title: 'Day 1',
            dayIndex: 0,
            exercises: [
              ProgramExercise(
                exerciseId: 'bench',
                name: 'Bench',
                sets: 3,
              ),
            ],
          ),
        ]),
      ],
      createdAt: DateTime(2026, 11, 21),
      sourceSpreadsheetId: sheetId,
      sentToClientIds: sentTo,
    );

Future<void> pumpCard(
  WidgetTester tester,
  Program p, {
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ForgeTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CoachProgramCard(
            program: p,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CoachProgramCard', () {
    testWidgets('shows name, meta, not-sent and sheet line', (tester) async {
      await pumpCard(tester, program(sheetId: 'sheet-1'));
      expect(find.text('Beginner Strength'), findsOneWidget);
      expect(find.text('2 weeks · 2 days'), findsOneWidget);
      expect(find.text('Not sent yet'), findsOneWidget);
      expect(find.text('Linked to Google Sheet'), findsOneWidget);
      // No progress bar: a coaching program is not trained.
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows the sent count once it has been sent',
        (tester) async {
      await pumpCard(tester, program(sentTo: ['c1', 'c2']));
      expect(find.text('Sent to 2 clients'), findsOneWidget);
      expect(find.text('Not sent yet'), findsNothing);
    });

    testWidgets('one client reads singular', (tester) async {
      await pumpCard(tester, program(sentTo: ['c1']));
      expect(find.text('Sent to 1 client'), findsOneWidget);
    });

    testWidgets('tap opens the program', (tester) async {
      var tapped = false;
      await pumpCard(tester, program(), onTap: () => tapped = true);
      await tester.tap(find.text('Beginner Strength'));
      expect(tapped, isTrue);
    });

    testWidgets('template programs get a Template pill', (tester) async {
      await pumpCard(
        tester,
        program(description: 'Simple Strength (3-day)'),
      );
      expect(find.text('Template'), findsOneWidget);
    });

    testWidgets('spaces every element deliberately — no glued rows',
        (tester) async {
      await pumpCard(tester, program(sheetId: 'sheet-1'));
      // Name row -> meta line.
      final nameRow = tester.getRect(
        find
            .ancestor(
              of: find.text('Beginner Strength'),
              matching: find.byType(Row),
            )
            .first,
      );
      final meta = tester.getRect(find.text('2 weeks · 2 days'));
      expect(meta.top - nameRow.bottom, CoachProgramCard.gapNameToMeta);
      // Meta line -> sent line.
      final sent = tester.getRect(find.text('Not sent yet'));
      expect(sent.top - meta.bottom, CoachProgramCard.gapMetaToSent);
      // Sent line -> sheet line.
      final sheetRow = tester.getRect(
        find
            .ancestor(
              of: find.text('Linked to Google Sheet'),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(sheetRow.top - sent.bottom, CoachProgramCard.gapSentToSheet);
      // Last line -> card bottom edge (the card padding). The Card's
      // own box includes its 12px bottom margin, so the surface is
      // the Material inside it.
      final cardSurface = tester.getRect(
        find
            .descendant(
              of: find.byType(Card),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(cardSurface.bottom - sheetRow.bottom,
          CoachProgramCard.cardPadding);
    });
  });
}
