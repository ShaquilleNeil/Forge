import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/models/workout.dart';
import 'package:forge/services/program_progress.dart';
import 'package:forge/theme.dart';
import 'package:forge/widgets/program_card.dart';

Program program({
  bool active = false,
  String? description,
  String? sheetId,
}) =>
    Program(
      id: 'p',
      userId: 'u',
      name: 'Iron Ascent',
      description: description,
      weeks: [
        const ProgramWeek(id: 'w1', title: 'W1', weekIndex: 0, days: [
          ProgramDay(
            id: 'd1',
            title: 'Mon Nov 9 · D1',
            dayIndex: 0,
            exercises: [
              ProgramExercise(
                exerciseId: 'squat',
                name: 'Squat',
                sets: 3,
                repsMin: 5,
                repsMax: 5,
              ),
            ],
          ),
          ProgramDay(
            id: 'd2',
            title: 'Tue Nov 10 · D2',
            dayIndex: 1,
            exercises: [
              ProgramExercise(
                exerciseId: 'bench',
                name: 'Bench',
                sets: 3,
                repsMin: 5,
                repsMax: 5,
              ),
            ],
          ),
        ]),
        const ProgramWeek(id: 'w2', title: 'W2', weekIndex: 1, days: [
          ProgramDay(
            id: 'd5',
            title: 'Mon Nov 16 · D1',
            dayIndex: 0,
            exercises: [
              ProgramExercise(
                exerciseId: 'squat',
                name: 'Squat',
                sets: 3,
                repsMin: 5,
                repsMax: 5,
              ),
            ],
          ),
        ]),
      ],
      isActive: active,
      createdAt: DateTime(2026, 1, 1),
      sourceSpreadsheetId: sheetId,
    );

Future<void> pumpCard(
  WidgetTester tester,
  Program p, {
  List<WorkoutSession> sessions = const [],
  VoidCallback? onTap,
}) async {
  final progress = programProgress(p, sessions, now: DateTime(2026, 11, 9));
  await tester.pumpWidget(
    MaterialApp(
      theme: ForgeTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProgramCard(
            program: p,
            progress: progress,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ProgramCard', () {
    testWidgets('shows name, pill, meta, progress and sheet line',
        (tester) async {
      await pumpCard(
        tester,
        program(active: true, sheetId: 'sheet-1'),
        sessions: [
          WorkoutSession(
            id: 's1',
            userId: 'u',
            date: DateTime(2026, 11, 9),
            programId: 'p',
            weekId: 'w1',
            dayId: 'd1',
            title: 'Workout',
            status: 'completed',
          ),
        ],
      );
      expect(find.text('Iron Ascent'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('2 weeks · Week 1 of 2'), findsOneWidget);
      expect(find.text('1 of 3 days done'), findsOneWidget);
      expect(find.text('Linked to Google Sheet'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('tap opens the program', (tester) async {
      var tapped = false;
      await pumpCard(
        tester,
        program(),
        onTap: () => tapped = true,
      );
      await tester.tap(find.text('Iron Ascent'));
      expect(tapped, isTrue);
    });

    testWidgets('template programs get a Template pill, not Active',
        (tester) async {
      await pumpCard(
        tester,
        program(description: 'Simple Strength (3-day)'),
      );
      expect(find.text('Template'), findsOneWidget);
      expect(find.text('Active'), findsNothing);
    });

    testWidgets('no progress bar when the program has no training days',
        (tester) async {
      final empty = Program(
        id: 'p',
        userId: 'u',
        name: 'Empty',
        weeks: const [],
        createdAt: DateTime(2026, 1, 1),
      );
      await pumpCard(tester, empty);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Not started yet'), findsNothing);
    });

    testWidgets('spaces every element deliberately — no glued rows',
        (tester) async {
      await pumpCard(
        tester,
        program(active: true, sheetId: 'sheet-1'),
        sessions: [
          WorkoutSession(
            id: 's1',
            userId: 'u',
            date: DateTime(2026, 11, 9),
            programId: 'p',
            weekId: 'w1',
            dayId: 'd1',
            title: 'Workout',
            status: 'completed',
          ),
        ],
      );
      // Name row -> meta line.
      final nameRow = tester.getRect(
        find
            .ancestor(
              of: find.text('Iron Ascent'),
              matching: find.byType(Row),
            )
            .first,
      );
      final meta = tester.getRect(find.text('2 weeks · Week 1 of 2'));
      expect(meta.top - nameRow.bottom, ProgramCard.gapNameToMeta);
      // Meta line -> progress bar.
      final bar = tester.getRect(find.byType(LinearProgressIndicator));
      expect(bar.top - meta.bottom, ProgramCard.gapMetaToBar);
      // Progress bar -> label.
      final label = tester.getRect(find.text('1 of 3 days done'));
      expect(label.top - bar.bottom, ProgramCard.gapBarToLabel);
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
      final sheetRow = tester.getRect(
        find
            .ancestor(
              of: find.text('Linked to Google Sheet'),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(cardSurface.bottom - sheetRow.bottom, ProgramCard.cardPadding);
    });
  });
}
