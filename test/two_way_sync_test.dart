import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/models/workout.dart';
import 'package:forge/services/sheet_import_service.dart';

// Fixture rows modelled on the Iron Ascent Training Log layout.
// Columns A–I: Exercise | Weight (kg) | Prev wk (kg) | Sets x reps |
// Target RPE | Actual RPE | Bar speed | Status | Notes.
List<List<String>> get weekRows => [
      ['W1 Oct 26', 'Wave W1'],
      ['Week starting', 'Oct 26'],
      [],
      [],
      [
        'Exercise',
        'Weight (kg)',
        'Prev wk (kg)',
        'Sets x reps',
        'Target RPE',
        'Actual RPE',
        'Bar speed',
        'Status',
        'Notes',
      ],
      ['Mon Oct 26 · D1 · Squat + bench'],
      ['Squat', '120', '', '3 x 5', '8', '', '', '', ''],
      ['Bench', '97.5', '', '3 x 5', '8', '', '', '', ''],
      ['Tue Oct 27 · D2 · Deadlift'],
      ['Deadlift', '170', '', '3 x 5', '8', '', '', '', ''],
      ['Squat beltless', '', '', '3 x 5', '8', '', '', '', ''],
    ];

const _d1 = ProgramDay(
  id: 'd1',
  title: 'Mon Oct 26 · D1 · Squat + bench',
  dayIndex: 0,
  exercises: [],
);
const _d2 = ProgramDay(
  id: 'd2',
  title: 'Tue Oct 27 · D2 · Deadlift',
  dayIndex: 1,
  exercises: [],
);

// One shared instance: findExerciseRow matches days by identity
// (week.days.indexOf(day)), so the days passed in must be the same
// objects the week holds.
const week = ProgramWeek(
  id: 'w1',
  title: 'W1 Oct 26',
  weekIndex: 0,
  days: [_d1, _d2],
);

FetchedSpreadsheet get fetched =>
    FetchedSpreadsheet(title: 'Iron Ascent', tabs: {'W1 Oct 26': weekRows});

Map<String, List<List<String>>> get formulaTabs => {
      'W1 Oct 26': weekRows,
    };

/// Same week as weekRows, but with an extra 'Tempo' column inserted at
/// B, pushing the weight to C and everything after it one column right.
List<List<String>> get shiftedRows => [
      ['W1 Oct 26', 'Wave W1'],
      ['Week starting', 'Oct 26'],
      [],
      [],
      [
        'Exercise',
        'Tempo',
        'Weight (kg)',
        'Prev wk (kg)',
        'Sets x reps',
        'Target RPE',
        'Actual RPE',
        'Bar speed',
        'Status',
        'Notes',
      ],
      ['Mon Oct 26 · D1 · Squat + bench'],
      ['Squat', '3-1-0', '120', '', '3 x 5', '8', '', '', '', ''],
      ['Bench', '3-1-0', '97.5', '', '3 x 5', '8', '', '', '', ''],
      ['Tue Oct 27 · D2 · Deadlift'],
      ['Deadlift', '3-1-0', '170', '', '3 x 5', '8', '', '', '', ''],
    ];

FetchedSpreadsheet get shiftedFetched => FetchedSpreadsheet(
      title: 'Iron Ascent',
      tabs: {'W1 Oct 26': shiftedRows},
    );

void main() {
  group('sheetChanged', () {
    test('no stored timestamp means no change (baseline)', () {
      expect(
        SheetImportService.sheetChanged(
          null,
          DateTime.utc(2026, 11, 17, 13, 20),
        ),
        isFalse,
      );
    });

    test('no current timestamp means no change', () {
      expect(
        SheetImportService.sheetChanged('2026-11-17T13:20:00.000Z', null),
        isFalse,
      );
    });

    test('same instant in different string forms is no change', () {
      expect(
        SheetImportService.sheetChanged(
          '2026-11-17T13:20:00.000Z',
          DateTime.parse('2026-11-17T13:20:00Z'),
        ),
        isFalse,
      );
    });

    test('a newer modifiedTime is a change', () {
      expect(
        SheetImportService.sheetChanged(
          '2026-11-17T13:20:00.000Z',
          DateTime.utc(2026, 11, 17, 14, 0),
        ),
        isTrue,
      );
    });

    test('an unparseable stored timestamp is no change', () {
      expect(
        SheetImportService.sheetChanged(
          'not a date',
          DateTime.utc(2026, 11, 17, 14, 0),
        ),
        isFalse,
      );
    });
  });

  group('findExerciseRow', () {
    test('finds an exercise in the first day section', () {
      expect(
        SheetImportService.findExerciseRow(
          fetched: fetched,
          week: week,
          day: week.days[0],
          exerciseName: 'Bench',
        ),
        7,
      );
    });

    test('finds an exercise in the second day section', () {
      expect(
        SheetImportService.findExerciseRow(
          fetched: fetched,
          week: week,
          day: week.days[1],
          exerciseName: 'Deadlift',
        ),
        9,
      );
    });

    test('does not match an exercise from another day section', () {
      // Squat beltless lives in D2's section; D1 must not find it.
      expect(
        SheetImportService.findExerciseRow(
          fetched: fetched,
          week: week,
          day: week.days[0],
          exerciseName: 'Squat beltless',
        ),
        isNull,
      );
    });

    test('missing exercise returns null', () {
      expect(
        SheetImportService.findExerciseRow(
          fetched: fetched,
          week: week,
          day: week.days[0],
          exerciseName: 'Overhead press',
        ),
        isNull,
      );
    });

    test('missing tab returns null', () {
      expect(
        SheetImportService.findExerciseRow(
          fetched: const FetchedSpreadsheet(title: 'x', tabs: {}),
          week: week,
          day: week.days[0],
          exerciseName: 'Squat',
        ),
        isNull,
      );
    });
  });

  group('buildWeightWrite', () {
    test('writes the new weight into column B of the exercise row', () {
      final update = SheetImportService.buildWeightWrite(
        fetched: fetched,
        formulaTabs: formulaTabs,
        week: week,
        day: week.days[0],
        exerciseName: 'Squat',
        weightKg: 125,
      );
      expect(update, isNotNull);
      expect(update!.range, "'W1 Oct 26'!B7");
      expect(update.values, [
        ['125'],
      ]);
    });

    test('a typed value in B is overwritten', () {
      // Bench B holds 97.5 (typed) — the app is now the source of the
      // new number, so the write still happens.
      final update = SheetImportService.buildWeightWrite(
        fetched: fetched,
        formulaTabs: formulaTabs,
        week: week,
        day: week.days[0],
        exerciseName: 'Bench',
        weightKg: 100,
      );
      expect(update, isNotNull);
      expect(update!.range, "'W1 Oct 26'!B8");
    });

    test('a formula in B is never touched', () {
      final formulaRows = weekRows
          .map((r) => List<String>.from(r))
          .toList();
      // Squat beltless B (row 11, index 10) holds a formula.
      formulaRows[10][1] = '=B7*0.9';
      final update = SheetImportService.buildWeightWrite(
        fetched: fetched,
        formulaTabs: {'W1 Oct 26': formulaRows},
        week: week,
        day: week.days[1],
        exerciseName: 'Squat beltless',
        weightKg: 155,
      );
      expect(update, isNull);
    });

    test('missing row returns null', () {
      expect(
        SheetImportService.buildWeightWrite(
          fetched: fetched,
          formulaTabs: formulaTabs,
          week: week,
          day: week.days[0],
          exerciseName: 'Overhead press',
          weightKg: 60,
        ),
        isNull,
      );
    });

    test('missing formula read returns null (cannot verify B)', () {
      expect(
        SheetImportService.buildWeightWrite(
          fetched: fetched,
          formulaTabs: {},
          week: week,
          day: week.days[0],
          exerciseName: 'Squat',
          weightKg: 125,
        ),
        isNull,
      );
    });

    test('a zero weight is not written', () {
      expect(
        SheetImportService.buildWeightWrite(
          fetched: fetched,
          formulaTabs: formulaTabs,
          week: week,
          day: week.days[0],
          exerciseName: 'Squat',
          weightKg: 0,
        ),
        isNull,
      );
    });
  });

  test('Program JSON round-trips sourceModifiedTime', () {
    final program = Program(
      id: 'p1',
      userId: 'u1',
      name: 'Iron Ascent',
      createdAt: DateTime(2026, 11, 16),
      sourceSpreadsheetId: 'sheet-1',
      sourceModifiedTime: '2026-11-17T13:20:00.000Z',
    );
    expect(
      Program.fromJson(program.toJson()).sourceModifiedTime,
      '2026-11-17T13:20:00.000Z',
    );
  });

  group('WeekColumns', () {
    test('defaults match the Iron Ascent layout', () {
      const cols = WeekColumns();
      expect(cols.weight, 1);
      expect(cols.setsReps, 3);
      expect(cols.targetRpe, 4);
      expect(cols.actualRpe, 5);
      expect(cols.barSpeed, 6);
      expect(cols.status, 7);
      expect(cols.notes, 8);
    });

    test('fromHeader maps a weight in C and shifts the rest', () {
      final cols = WeekColumns.fromHeader(shiftedRows[4]);
      expect(cols.weight, 2);
      expect(cols.setsReps, 4);
      expect(cols.targetRpe, 5);
      expect(cols.actualRpe, 6);
      expect(cols.barSpeed, 7);
      expect(cols.status, 8);
      expect(cols.notes, 9);
    });

    test('a column the header does not name keeps its default', () {
      final cols = WeekColumns.fromHeader(['Exercise', 'Weight (kg)']);
      expect(cols.weight, 1);
      expect(cols.setsReps, 3);
    });

    test('fromRows finds the header row and maps it', () {
      expect(WeekColumns.fromRows(shiftedRows).weight, 2);
      expect(WeekColumns.fromRows(weekRows).weight, 1);
    });

    test('fromRows without a header row returns defaults', () {
      expect(
        WeekColumns.fromRows([
          ['W1 Oct 26'],
          ['Squat', '120'],
        ]).weight,
        1,
      );
    });
  });

  group('shifted layout — weight in C', () {
    test('parseWeekTab reads the weight from C', () {
      final parsed =
          SheetImportService.parseWeekTab('W1 Oct 26', shiftedRows);
      expect(parsed.days.length, 2);
      final squat = parsed.days[0].exercises[0];
      expect(squat.name, 'Squat');
      expect(squat.targetWeightKg, 120);
      expect(squat.sets, 3);
      expect(squat.repsMin, 5);
      expect(squat.repsMax, 5);
      expect(squat.targetRpe, '8');
    });

    test('buildWeightWrite writes to C, not B', () {
      final update = SheetImportService.buildWeightWrite(
        fetched: shiftedFetched,
        formulaTabs: {'W1 Oct 26': shiftedRows},
        week: week,
        day: week.days[0],
        exerciseName: 'Squat',
        weightKg: 125,
      );
      expect(update, isNotNull);
      expect(update!.range, "'W1 Oct 26'!C7");
      expect(update.values, [
        ['125'],
      ]);
    });

    test('buildWriteBack puts RPE, speed and status in the shifted columns',
        () {
      final program = Program(
        id: 'prog1',
        userId: 'u1',
        name: 'Iron Ascent',
        weeks: [
          const ProgramWeek(
            id: 'w1',
            title: 'W1 Oct 26',
            weekIndex: 0,
            days: [
              ProgramDay(
                id: 'd1',
                title: 'Mon Oct 26 · D1 · Squat + bench',
                dayIndex: 0,
                exercises: [
                  ProgramExercise(
                    exerciseId: 'squat',
                    name: 'Squat',
                    sets: 3,
                    repsMin: 5,
                    repsMax: 5,
                    targetWeightKg: 120,
                  ),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime(2026, 11, 16),
      );
      final session = WorkoutSession(
        id: 'sess1',
        userId: 'u1',
        date: DateTime(2026, 10, 26),
        programId: 'prog1',
        weekId: 'w1',
        dayId: 'd1',
        title: 'D1',
        status: 'completed',
        sets: [
          for (var i = 0; i < 3; i++)
            SessionSet(
              exerciseId: 'squat',
              name: 'Squat',
              setIndex: i,
              weightKg: 122.5,
              reps: 5,
              rpe: 8,
              barSpeed: 'Normal',
              completed: true,
            ),
        ],
      );
      final plan = SheetImportService.buildWriteBack(
        fetched: shiftedFetched,
        formulaTabs: {'W1 Oct 26': shiftedRows},
        program: program,
        session: session,
      );
      // C already holds the prescription (120), so the weight is left
      // alone; RPE, speed and status land in G, H, I — not F, G, H.
      expect(plan.updates.length, 1);
      expect(plan.updates[0].range, "'W1 Oct 26'!G7:I7");
      expect(plan.updates[0].values, [
        ['8', 'Normal', 'Done'],
      ]);
    });
  });

  group('mixed sessions', () {
    test('buildWriteBack writes each day\'s sets to its own day', () {
      final program = Program(
        id: 'prog1',
        userId: 'u1',
        name: 'Iron Ascent',
        weeks: [
          const ProgramWeek(
            id: 'w1',
            title: 'W1 Oct 26',
            weekIndex: 0,
            days: [
              ProgramDay(
                id: 'd1',
                title: 'Mon Oct 26 · D1 · Squat + bench',
                dayIndex: 0,
                exercises: [
                  ProgramExercise(
                    exerciseId: 'squat',
                    name: 'Squat',
                    sets: 3,
                    repsMin: 5,
                    repsMax: 5,
                    targetWeightKg: 120,
                  ),
                  ProgramExercise(
                    exerciseId: 'bench',
                    name: 'Bench',
                    sets: 3,
                    repsMin: 5,
                    repsMax: 5,
                    targetWeightKg: 97.5,
                  ),
                ],
              ),
              ProgramDay(
                id: 'd2',
                title: 'Tue Oct 27 · D2 · Deadlift',
                dayIndex: 1,
                exercises: [
                  ProgramExercise(
                    exerciseId: 'deadlift',
                    name: 'Deadlift',
                    sets: 3,
                    repsMin: 5,
                    repsMax: 5,
                    targetWeightKg: 170,
                  ),
                  ProgramExercise(
                    exerciseId: 'squat-beltless',
                    name: 'Squat beltless',
                    sets: 3,
                    repsMin: 5,
                    repsMax: 5,
                  ),
                ],
              ),
            ],
          ),
        ],
        createdAt: DateTime(2026, 11, 16),
      );
      // Day 1 moved onto day 2 and mixed with it: the session's
      // primary day is d2 (the host), d1 rides in mixedDayKeys, and
      // every set is tagged with its own day.
      final session = WorkoutSession(
        id: 'sess1',
        userId: 'u1',
        date: DateTime(2026, 10, 27),
        programId: 'prog1',
        weekId: 'w1',
        dayId: 'd2',
        title: 'D1 + D2',
        status: 'completed',
        mixedDayKeys: ['w1:d1'],
        sets: [
          for (var i = 0; i < 3; i++) ...[
            SessionSet(
              exerciseId: 'squat',
              name: 'Squat',
              setIndex: i,
              weightKg: 122.5,
              reps: 5,
              rpe: 8,
              barSpeed: 'Normal',
              completed: true,
              dayId: 'd1',
            ),
            SessionSet(
              exerciseId: 'bench',
              name: 'Bench',
              setIndex: i,
              weightKg: 100,
              reps: 5,
              rpe: 8,
              barSpeed: 'Normal',
              completed: true,
              dayId: 'd1',
            ),
            SessionSet(
              exerciseId: 'deadlift',
              name: 'Deadlift',
              setIndex: i,
              weightKg: 172.5,
              reps: 5,
              rpe: 8,
              barSpeed: 'Normal',
              completed: true,
              dayId: 'd2',
            ),
          ],
        ],
      );
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        formulaTabs: formulaTabs,
        program: program,
        session: session,
      );
      // Each day's RPE / speed / status lands on its own section:
      // squat + bench on day 1's rows, deadlift on day 2's row.
      // Weights stay untouched (all three prescriptions are filled).
      // Squat beltless has no sets in the session and is not written.
      expect(plan.skipped, isEmpty);
      expect(plan.updates.length, 3);
      expect(
        plan.updates.map((u) => u.range).toSet(),
        {
          "'W1 Oct 26'!F7:H7",
          "'W1 Oct 26'!F8:H8",
          "'W1 Oct 26'!F10:H10",
        },
      );
      for (final update in plan.updates) {
        expect(update.values, [
          ['8', 'Normal', 'Done'],
        ]);
      }
    });
  });
}
