import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/models/workout.dart';
import 'package:forge/services/sheet_import_service.dart';

// Fixture rows modelled on the Iron Ascent Training Log layout.
// Columns A–I: Exercise | Weight (kg) | Prev wk (kg) | Sets x reps |
// Target RPE | Actual RPE | Bar speed | Status | Notes.
List<List<String>> get w3Rows => [
      ['W3 Nov 9', 'Wave W3: Peak'],
      ['Week starting', 'Nov 9'],
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
      ['Mon Nov 9 · D1 · Squat + bench volume · ~75 min'],
      ['Squat beltless', '132.5', '130', '4 x 4', '7-8', '', '', '', ''],
      [
        'Comp bench',
        '100',
        '95',
        '4 x 4',
        '7-8',
        '',
        '',
        '',
        'Superset A1, with Rope pushdown',
      ],
      ['Rope pushdown', '', '', '3 x 10-12', '8', '', '', '', 'Superset A1'],
      ['Assault bike', '', '', '1 x 25-30 min', '', '', '', '', ''],
      ['', '100', '', '3 x 5', '', '', '', '', ''],
      ['Foam rolling'],
      ['Fri Nov 13 · Rest'],
      ['Full rest. A walk is fine.'],
    ];

List<List<String>> get setupRows => [
      ['Program start (Monday)', 'Oct 19, 2026'],
      ['Rounding increment (kg)', '2.5'],
      ['Prior close: Oct 17 D4 singles (all RPE 8)'],
      ['Squat', '187.5'],
      ['Bench', '122.5'],
      ['Deadlift', '202.5'],
      ['Squat', '70%'],
    ];

// First-week tab copied from the real "Oct 19 Deload" sheet: it has NO
// "Prev wk" column, so "Sets x reps" is C (not D) and "Target RPE" is D.
// A fixed-column parser reads the RPE as the prescription here.
List<List<String>> get deloadRows => [
      ['Oct 19 Deload', 'Deload (clears Oct 17 fatigue)'],
      ['Week starting', 'Oct 19'],
      ['Yellow = you enter', 'Gray = calc'],
      [],
      [
        'Exercise',
        'Weight (kg)',
        'Sets x reps',
        'Target RPE',
        'Actual RPE',
        'Bar speed',
        'Status',
        'Notes',
      ],
      ['Mon Oct 19 · D1 · Squat + bench volume · ~75 min'],
      [
        'Seated/lying leg curl',
        '8.0',
        '2 x 10-12',
        '7',
        '7.0',
        'Fast',
        'On target',
        '',
      ],
      [
        'Squat, beltless',
        '92.5',
        '3 x 4',
        '5',
        '5.0',
        'Fast',
        'On target',
        '70% of D1 load',
      ],
      [
        'Comp bench',
        '70',
        '3 x 5',
        '5',
        '5.0',
        'Fast',
        'On target',
        '70% of D1 load',
      ],
    ];

List<List<String>> get meetRows => [
      ['Meet Jan 16'],
      ['Attempt plan'],
      [
        'Lift',
        'Projected max',
        'Opener',
        '2nd',
        '3rd low',
        '3rd high',
        'Last warm-up',
      ],
      ['Squat', '—', '182.5', '192.5', '197.5', '200', '167.5'],
      ['Bench', '', '120', '125', '130', '130', '110'],
      ['Deadlift', '—', '195', '205', '212.5', '215', '182.5'],
      ['On the day'],
      ['Lift', 'Attempt 1', 'Attempt 2', 'Attempt 3'],
      ['Squat', '', '', ''],
    ];

List<List<String>> get progressRows => [
      ['D4 top singles'],
      [
        'Week',
        'Squat',
        'RPE',
        'Speed',
        'Bench',
        'RPE',
        'Speed',
        'Deadlift',
        'RPE',
        'Speed',
      ],
      ['Oct 17 close', '187.5', '8', '', '122.5', '8', '', '202.5', '8'],
      ['W1', '167.5', '7', 'Normal', '105', '7', 'Fast', '185', '7', 'Normal'],
      ['W2', '172.5', '8', 'Fast', '114.0', '—', '', '192.5', ''],
      ['W3', '180', '9', 'Slow', '120', '9', 'Normal', '200', '9', 'Normal'],
    ];

List<List<String>> get d4Rows => [
      ['W3 Nov 9', 'Wave W3: Peak'],
      ['Week starting', 'Nov 9'],
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
      ['Sat Nov 14 · D4 · Top singles'],
      ['Squat', '180', '', '1 x 1', '9', '', '', '', ''],
      ['Bench', '120', '', '1 x 1', '9', '', '', '', ''],
      ['Deadlift', '200', '', '1 x 1', '9', '', '', '', ''],
    ];

/// Program parsed from the fixtures (week id 'w3-nov-9', day ids
/// 'day_0' / 'day_1'), as the import would store it.
Program programFromTabs(Map<String, List<List<String>>> tabs) {
  final preview = SheetImportService.previewSpreadsheet(
    FetchedSpreadsheet(title: 'Iron Ascent Training Log', tabs: tabs),
  );
  return Program(
    id: 'prog1',
    userId: 'u1',
    name: preview.programName,
    weeks: preview.weeks,
    createdAt: DateTime(2026, 11, 9),
  );
}

SessionSet set(
  String exerciseId,
  String name,
  int index,
  double weight,
  int reps, {
  double? rpe,
  String? speed,
  bool completed = true,
}) =>
    SessionSet(
      exerciseId: exerciseId,
      name: name,
      setIndex: index,
      weightKg: weight,
      reps: reps,
      rpe: rpe,
      barSpeed: speed,
      completed: completed,
    );

WorkoutSession d1Session({bool partialSquat = false, bool unknown = false}) {
  final sets = <SessionSet>[
    set('squat-beltless', 'Squat beltless', 0, 132.5, 4, rpe: 8, speed: 'Normal'),
    set('squat-beltless', 'Squat beltless', 1, 132.5, 4, rpe: 8.5, speed: 'Normal'),
    set('squat-beltless', 'Squat beltless', 2, 132.5, 4,
        rpe: 8.5, speed: 'Slow', completed: !partialSquat),
    set('squat-beltless', 'Squat beltless', 3, 132.5, 4,
        rpe: 9, speed: 'Normal', completed: !partialSquat),
    set('comp-bench', 'Comp bench', 0, 100, 4, rpe: 7, speed: 'Fast'),
    set('comp-bench', 'Comp bench', 1, 100, 4, rpe: 8, speed: 'Fast'),
    set('comp-bench', 'Comp bench', 2, 100, 4, rpe: 8, speed: 'Fast'),
    set('comp-bench', 'Comp bench', 3, 100, 4, rpe: 8, speed: 'Fast'),
    set('rope-pushdown', 'Rope pushdown', 0, 0, 12),
    set('rope-pushdown', 'Rope pushdown', 1, 0, 12),
    set('rope-pushdown', 'Rope pushdown', 2, 0, 10),
    set('assault-bike', 'Assault bike', 0, 0, 1),
  ];
  if (unknown) {
    sets.add(set('leg-press', 'Leg Press', 0, 200, 10, rpe: 8));
  }
  return WorkoutSession(
    id: 'sess1',
    userId: 'u1',
    date: DateTime(2026, 11, 9),
    programId: 'prog1',
    weekId: 'w3-nov-9',
    dayId: 'day_0',
    title: 'D1',
    status: 'completed',
    sets: sets,
  );
}

void main() {
  group('parseSetsReps', () {
    test('range form "3 x 10-12"', () {
      final parsed = SheetImportService.parseSetsReps('3 x 10-12');
      expect(parsed.sets, 3);
      expect(parsed.repsMin, 10);
      expect(parsed.repsMax, 12);
      expect(parsed.repsText, '10-12');
    });

    test('single form "1 x 1"', () {
      final parsed = SheetImportService.parseSetsReps('1 x 1');
      expect(parsed.sets, 1);
      expect(parsed.repsMin, 1);
      expect(parsed.repsMax, 1);
    });

    test('timed form "1 x 25-30 min" keeps reps text, no rep bounds', () {
      final parsed = SheetImportService.parseSetsReps('1 x 25-30 min');
      expect(parsed.sets, 1);
      expect(parsed.repsMin, isNull);
      expect(parsed.repsMax, isNull);
      expect(parsed.repsText, '25-30 min');
    });

    test('per-side form "2 x 30 s/side" keeps reps text, no rep bounds', () {
      final parsed = SheetImportService.parseSetsReps('2 x 30 s/side');
      expect(parsed.sets, 2);
      expect(parsed.repsMin, isNull);
      expect(parsed.repsMax, isNull);
      expect(parsed.repsText, '30 s/side');
    });
  });

  group('parseWeekTab', () {
    test('W3 D1 rows: weights, sets, RPE, superset, bodyweight null', () {
      final week = SheetImportService.parseWeekTab('W3 Nov 9', w3Rows);
      expect(week.title, 'W3 Nov 9');
      expect(week.days.length, 2);

      final d1 = week.days[0];
      expect(d1.title, contains('D1'));
      expect(d1.exercises.length, 4);

      final squat = d1.exercises[0];
      expect(squat.name, 'Squat beltless');
      expect(squat.targetWeightKg, 132.5);
      expect(squat.sets, 4);
      expect(squat.repsMin, 4);
      expect(squat.repsMax, 4);
      expect(squat.targetRpe, '7-8');

      final bench = d1.exercises[1];
      expect(bench.targetWeightKg, 100);
      expect(bench.supersetGroup, 'A1');
      expect(bench.notes, contains('Superset A1'));

      // Bodyweight accessory: kept, with a null target weight.
      final pushdown = d1.exercises[2];
      expect(pushdown.name, 'Rope pushdown');
      expect(pushdown.targetWeightKg, isNull);
      expect(pushdown.sets, 3);
      expect(pushdown.repsMin, 10);
      expect(pushdown.repsMax, 12);

      // Conditioning: sets only, free-text reps kept as-is.
      final bike = d1.exercises[3];
      expect(bike.name, 'Assault bike');
      expect(bike.targetWeightKg, isNull);
      expect(bike.sets, 1);
      expect(bike.repsMin, isNull);
      expect(bike.repsText, '25-30 min');
    });

    test('first-week tab without "Prev wk" still maps sets/RPE/notes', () {
      final week =
          SheetImportService.parseWeekTab('Oct 19 Deload', deloadRows);
      expect(week.days.length, 1);
      final d1 = week.days[0];
      expect(d1.exercises.length, 3);

      final curl = d1.exercises[0];
      expect(curl.name, 'Seated/lying leg curl');
      expect(curl.targetWeightKg, 8.0);
      expect(curl.sets, 2);
      expect(curl.repsMin, 10);
      expect(curl.repsMax, 12);
      expect(curl.targetRpe, '7');

      final squat = d1.exercises[1];
      expect(squat.sets, 3);
      expect(squat.repsMin, 4);
      expect(squat.repsMax, 4);
      expect(squat.targetRpe, '5');
      expect(squat.notes, contains('70% of D1 load'));
    });

    test('rest day has no exercises and keeps its note', () {
      final week = SheetImportService.parseWeekTab('W3 Nov 9', w3Rows);
      final rest = week.days[1];
      expect(rest.title, contains('Rest'));
      expect(rest.exercises, isEmpty);
      expect(rest.title, contains('Full rest. A walk is fine.'));
    });

    test('week start date comes from the "Week starting" row', () {
      final start = SheetImportService.parseWeekStartDate(w3Rows);
      expect(start, DateTime(2026, 11, 9));
    });

    test('uninterpretable rows are reported with 1-based row numbers', () {
      final skipped = <SkippedRow>[];
      SheetImportService.parseWeekTab(
        'W3 Nov 9',
        w3Rows,
        skippedRows: skipped,
      );
      expect(skipped.map((s) => s.row), containsAll([11, 12]));
      expect(skipped.length, 2);
      expect(skipped.every((s) => s.tab == 'W3 Nov 9'), isTrue);
    });
  });

  group('parseSetup', () {
    test('program start, rounding, and prior-close lifts', () {
      final setup = SheetImportService.parseSetup(setupRows);
      expect(setup.programStart, DateTime(2026, 10, 19));
      expect(setup.roundingKg, 2.5);
      expect(setup.priorClose['squat'], 187.5);
      expect(setup.priorClose['bench'], 122.5);
      expect(setup.priorClose['deadlift'], 202.5);
    });
  });

  group('parseMeet', () {
    test('attempt plan for all three lifts; on-the-day log ignored', () {
      final meet = SheetImportService.parseMeet(meetRows);
      expect(meet.date, DateTime(2027, 1, 16));
      expect(meet.attempts.length, 3);

      final squat = meet.attempts.firstWhere((a) => a.lift == 'squat');
      expect(squat.projectedMaxKg, isNull);
      expect(squat.openerKg, 182.5);
      expect(squat.secondKg, 192.5);
      expect(squat.thirdLowKg, 197.5);
      expect(squat.thirdHighKg, 200);
      expect(squat.lastWarmUpKg, 167.5);

      final bench = meet.attempts.firstWhere((a) => a.lift == 'bench');
      expect(bench.openerKg, 120);
      expect(bench.secondKg, 125);
      expect(bench.thirdLowKg, 130);
      expect(bench.thirdHighKg, 130);
      expect(bench.lastWarmUpKg, 110);

      final deadlift = meet.attempts.firstWhere((a) => a.lift == 'deadlift');
      expect(deadlift.openerKg, 195);
      expect(deadlift.secondKg, 205);
      expect(deadlift.thirdLowKg, 212.5);
      expect(deadlift.thirdHighKg, 215);
      expect(deadlift.lastWarmUpKg, 182.5);
    });
  });

  group('parseProgress', () {
    test('latest non-empty row per lift wins (W3)', () {
      final latest = SheetImportService.parseProgress(progressRows);
      expect(latest['squat']!.weightKg, 180);
      expect(latest['squat']!.rpe, 9);
      expect(latest['squat']!.speed, 'Slow');
      expect(latest['squat']!.weekLabel, 'W3');
      expect(latest['bench']!.weightKg, 120);
      expect(latest['bench']!.rpe, 9);
      expect(latest['bench']!.speed, 'Normal');
      expect(latest['deadlift']!.weightKg, 200);
      expect(latest['deadlift']!.rpe, 9);
      expect(latest['deadlift']!.speed, 'Normal');
    });
  });

  group('previewSpreadsheet', () {
    test('full sheet preview: name, weeks, meet, singles, start dates', () {
      final preview = SheetImportService.previewSpreadsheet(
        FetchedSpreadsheet(
          title: 'Iron Ascent Training Log',
          tabs: {
            'Setup': setupRows,
            'W3 Nov 9': w3Rows,
            'Meet Jan 16': meetRows,
            'Progress': progressRows,
          },
        ),
      );
      expect(preview.programName, 'Iron Ascent');
      expect(preview.weekCount, 1);
      expect(preview.dayCount, 2);
      expect(preview.exerciseCount, 4);
      expect(preview.weekStartDates['W3 Nov 9'], DateTime(2026, 11, 9));
      expect(preview.meetPlan!.attempts.length, 3);
      expect(preview.setup!.priorClose['squat'], 187.5);
      expect(preview.topSingles['squat']!.weightKg, 180);
      expect(preview.skippedRows.length, 2);
    });
  });

  group('buildWriteBack', () {
    FetchedSpreadsheet fetchedFrom(
      Map<String, List<List<String>>> tabs,
    ) =>
        FetchedSpreadsheet(
          title: 'Iron Ascent Training Log',
          tabs: tabs,
        );

    test('D1: actual RPE, bar speed and status land on the right rows', () {
      final fetched = fetchedFrom({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        program: program,
        session: d1Session(),
      );
      expect(plan.skipped, isEmpty);
      expect(plan.updates.length, 4);

      // Squat beltless is row 7; heaviest set is a tie at 132.5, so the
      // last set carries the RPE (9) and speed (Normal).
      final squat = plan.updates.firstWhere(
        (u) => u.range == "'W3 Nov 9'!F7:H7",
      );
      expect(squat.values, [
        ['9', 'Normal', 'Done']
      ]);

      // Comp bench is row 8; RPE 8, speed Fast, all 4 sets done.
      final bench = plan.updates.firstWhere(
        (u) => u.range == "'W3 Nov 9'!F8:H8",
      );
      expect(bench.values, [
        ['8', 'Fast', 'Done']
      ]);

      // Bodyweight / conditioning rows have no RPE or speed, so only
      // the status cell lands (H only, not the whole F:H row).
      final pushdown = plan.updates.firstWhere(
        (u) => u.range == "'W3 Nov 9'!H9:H9",
      );
      expect(pushdown.values, [
        ['Done']
      ]);
      final bike = plan.updates.firstWhere(
        (u) => u.range == "'W3 Nov 9'!H10:H10",
      );
      expect(bike.values, [
        ['Done']
      ]);

      // A D1 session never touches Progress.
      expect(
        plan.updates.any((u) => u.range.contains('Progress')),
        isFalse,
      );
    });

    test('week-tab ranges only cover B and the actuals columns F–H', () {
      final fetched = fetchedFrom({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        program: program,
        session: d1Session(),
      );
      for (final u in plan.updates) {
        expect(u.range, matches(RegExp(r"^'W3 Nov 9'![BF-H]\d+:[BF-H]\d+$")));
      }
    });

    test('B: the heaviest set weight lands when B is blank', () {
      // Squat row has no weight in B — the 132.5 from the heaviest set
      // is written there, and the F:H actuals land as usual.
      final rows = w3Rows.map((r) => List<String>.from(r)).toList();
      rows[6][1] = '';
      final fetched = fetchedFrom({
        'W3 Nov 9': rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': rows,
        'Progress': progressRows,
      });
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        program: program,
        session: d1Session(),
      );
      final squatWeight = plan.updates.firstWhere(
        (u) => u.range == "'W3 Nov 9'!B7:B7",
      );
      expect(squatWeight.values, [
        ['132.5']
      ]);
      expect(
        plan.updates
            .firstWhere((u) => u.range == "'W3 Nov 9'!F7:H7")
            .values,
        [
          ['9', 'Normal', 'Done']
        ],
      );
      // Bench B is filled (100), so no B update for that row.
      expect(
        plan.updates.any((u) => u.range.startsWith("'W3 Nov 9'!B8")),
        isFalse,
      );
      // Bodyweight rows have no weight to record — B stays blank.
      expect(
        plan.updates.any((u) => u.range.contains('!B9') ||
            u.range.contains('!B10')),
        isFalse,
      );
    });

    test('B: a formula in B protects it even when the formatted value '
        'is blank', () {
      // The beltless case: B looks empty in the normal read, but the
      // cell holds a formula. Only the F:H actuals are written.
      final formulaRows =
          w3Rows.map((r) => List<String>.from(r)).toList();
      formulaRows[6][1] = '=SI(Setup!C15,"","")';
      final rows = w3Rows.map((r) => List<String>.from(r)).toList();
      rows[6][1] = '';
      final fetched = fetchedFrom({
        'W3 Nov 9': rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': rows,
        'Progress': progressRows,
      });
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        formulaTabs: {'W3 Nov 9': formulaRows},
        program: program,
        session: d1Session(),
      );
      expect(
        plan.updates.any((u) => u.range.startsWith("'W3 Nov 9'!B7")),
        isFalse,
      );
      expect(
        plan.updates
            .firstWhere((u) => u.range == "'W3 Nov 9'!F7:H7")
            .values,
        [
          ['9', 'Normal', 'Done']
        ],
      );
    });

    test('partial completion writes Partial and the top set so far', () {
      final fetched = fetchedFrom({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        program: program,
        session: d1Session(partialSquat: true),
      );
      final squat = plan.updates.firstWhere(
        (u) => u.range == "'W3 Nov 9'!F7:H7",
      );
      expect(squat.values, [
        ['8.5', 'Normal', 'Partial']
      ]);
    });

    test('exercise not in the sheet is skipped, never written blind', () {
      final fetched = fetchedFrom({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        program: program,
        session: d1Session(unknown: true),
      );
      expect(plan.updates.length, 4);
      expect(plan.skipped.length, 1);
      expect(plan.skipped.first, contains('Leg Press'));
    });

    test('D4: only new-best singles reach the Progress tab', () {
      final fetched = fetchedFrom({
        'W3 Nov 9': d4Rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': d4Rows,
        'Progress': progressRows,
      });
      final session = WorkoutSession(
        id: 'sess-d4',
        userId: 'u1',
        date: DateTime(2026, 11, 14),
        programId: 'prog1',
        weekId: 'w3-nov-9',
        dayId: 'day_0',
        title: 'D4',
        status: 'completed',
        sets: [
          set('squat', 'Squat', 0, 185, 1, rpe: 9.5, speed: 'Slow'),
          set('bench', 'Bench', 0, 120, 1, rpe: 9, speed: 'Normal'),
          set('deadlift', 'Deadlift', 0, 202.5, 1, rpe: 9, speed: 'Normal'),
        ],
      );
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        program: program,
        session: session,
      );
      expect(plan.skipped, isEmpty);

      // Week-tab actuals still land (rows 7–9 in the D4 fixture).
      expect(
        plan.updates
            .where((u) => u.range == "'W3 Nov 9'!F7:H7")
            .single
            .values,
        [
          ['9.5', 'Slow', 'Done']
        ],
      );

      // Progress W3 is row 6. Squat 185 beats 180; deadlift 202.5 beats
      // 200; bench 120 only ties 120, so it is not overwritten.
      final squatProgress = plan.updates.firstWhere(
        (u) => u.range == "'Progress'!B6:D6",
      );
      expect(squatProgress.values, [
        ['185', '9.5', 'Slow']
      ]);
      final deadliftProgress = plan.updates.firstWhere(
        (u) => u.range == "'Progress'!H6:J6",
      );
      expect(deadliftProgress.values, [
        ['202.5', '9', 'Normal']
      ]);
      expect(
        plan.updates.any((u) => u.range.startsWith("'Progress'!E")),
        isFalse,
      );
    });

    test('only-if-empty: a filled RPE is left alone, speed and status '
        'still land', () {
      // Squat row already has an Actual RPE typed in (F filled, G/H
      // empty) — the write-back must not touch F.
      final rows =
          w3Rows.map((r) => List<String>.from(r)).toList();
      rows[6][5] = '8';
      final fetched = fetchedFrom({
        'W3 Nov 9': rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': rows,
        'Progress': progressRows,
      });
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        program: program,
        session: d1Session(),
      );
      // Only the empty cells: G:H, not F:H.
      final squat = plan.updates.firstWhere(
        (u) => u.range == "'W3 Nov 9'!G7:H7",
      );
      expect(squat.values, [
        ['Normal', 'Done']
      ]);
      expect(
        plan.updates.any((u) => u.range.startsWith("'W3 Nov 9'!F7")),
        isFalse,
      );
      // Other rows are untouched by the squat's filled cell.
      expect(
        plan.updates
            .firstWhere((u) => u.range == "'W3 Nov 9'!F8:H8")
            .values,
        [
          ['8', 'Fast', 'Done']
        ],
      );
      expect(plan.skipped, isEmpty);
    });

    test('a formula that evaluates to blank still protects the cell', () {
      // The beltless case: the formatted read shows F empty, but the
      // cell holds a formula (like the deload weight formula). The
      // formula-visible read is what keeps it safe.
      final formulaRows =
          w3Rows.map((r) => List<String>.from(r)).toList();
      formulaRows[6][5] = '=SI(Setup!C15,"","")';
      final fetched = fetchedFrom({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': w3Rows,
        'Progress': progressRows,
      });
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        formulaTabs: {'W3 Nov 9': formulaRows},
        program: program,
        session: d1Session(),
      );
      final squat = plan.updates.firstWhere(
        (u) => u.range == "'W3 Nov 9'!G7:H7",
      );
      expect(squat.values, [
        ['Normal', 'Done']
      ]);
      expect(
        plan.updates.any((u) => u.range.startsWith("'W3 Nov 9'!F7")),
        isFalse,
      );
    });

    test('a fully filled row is skipped with a note', () {
      final rows =
          w3Rows.map((r) => List<String>.from(r)).toList();
      rows[6][5] = '8';
      rows[6][6] = 'Normal';
      rows[6][7] = 'Done';
      final fetched = fetchedFrom({
        'W3 Nov 9': rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': rows,
        'Progress': progressRows,
      });
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        program: program,
        session: d1Session(),
      );
      // No update touches row 7 at all.
      expect(
        plan.updates.any((u) => u.range.contains('!F7') ||
            u.range.contains('!G7') ||
            u.range.contains('!H7')),
        isFalse,
      );
      expect(plan.updates.length, 3);
      expect(plan.skipped.length, 1);
      expect(plan.skipped.first, contains('Squat beltless'));
      expect(plan.skipped.first, contains('left alone'));
    });

    test('Progress: a formula in the best cell protects it even from '
        'a better single', () {
      // W3 squat best (row 6, col B) holds a formula; the 185 single
      // beats 180 but must not overwrite it. Deadlift is unaffected.
      final formulaProgress =
          progressRows.map((r) => List<String>.from(r)).toList();
      formulaProgress[5][1] = '=MAX(B3:B5)';
      final fetched = fetchedFrom({
        'W3 Nov 9': d4Rows,
        'Progress': progressRows,
      });
      final program = programFromTabs({
        'W3 Nov 9': d4Rows,
        'Progress': progressRows,
      });
      final session = WorkoutSession(
        id: 'sess-d4',
        userId: 'u1',
        date: DateTime(2026, 11, 14),
        programId: 'prog1',
        weekId: 'w3-nov-9',
        dayId: 'day_0',
        title: 'D4',
        status: 'completed',
        sets: [
          set('squat', 'Squat', 0, 185, 1, rpe: 9.5, speed: 'Slow'),
          set('bench', 'Bench', 0, 120, 1, rpe: 9, speed: 'Normal'),
          set('deadlift', 'Deadlift', 0, 202.5, 1, rpe: 9, speed: 'Normal'),
        ],
      );
      final plan = SheetImportService.buildWriteBack(
        fetched: fetched,
        formulaTabs: {'Progress': formulaProgress},
        program: program,
        session: session,
      );
      expect(
        plan.updates.any((u) => u.range.startsWith("'Progress'!B")),
        isFalse,
      );
      expect(
        plan.updates
            .firstWhere((u) => u.range == "'Progress'!H6:J6")
            .values,
        [
          ['202.5', '9', 'Normal']
        ],
      );
      expect(plan.skipped.any((s) => s.contains('formula')), isTrue);
    });
  });

  group('displayRepsText', () {
    test('strips a legacy "<sets> x " prefix from stored reps text', () {
      const exercise = ProgramExercise(
        exerciseId: 'legcurl',
        name: 'Seated/lying leg curl',
        sets: 2,
        repsText: '2 x 10-12',
      );
      expect(exercise.displayRepsText, '10-12');
    });

    test('leaves clean reps text alone', () {
      const exercise = ProgramExercise(
        exerciseId: 'squat',
        name: 'Squat, beltless',
        sets: 4,
        repsText: '4',
      );
      expect(exercise.displayRepsText, '4');
    });

    test('does not strip a prefix that does not match the sets count', () {
      const exercise = ProgramExercise(
        exerciseId: 'bench',
        name: 'Comp bench',
        sets: 3,
        repsText: '2 x 5',
      );
      expect(exercise.displayRepsText, '2 x 5');
    });

    test('null reps text stays null', () {
      const exercise = ProgramExercise(
        exerciseId: 'bike',
        name: 'Assault bike',
        sets: 1,
      );
      expect(exercise.displayRepsText, isNull);
    });
  });

  group('mergeImportedProgram', () {
    // A re-imported week: same ids the sheet always parses to
    // (week id = tab-title slug, day id = index in the week), with
    // one number changed in the sheet.
    const preview = ImportPreview(
      programName: 'Iron Ascent',
      weeks: [
        ProgramWeek(
          id: 'w1-nov-9',
          title: 'W3 Nov 9',
          weekIndex: 0,
          days: [
            ProgramDay(
              id: 'day_0',
              title: 'Mon Nov 9 · D1 · Squat + bench volume',
              dayIndex: 0,
              exercises: [
                ProgramExercise(
                  exerciseId: 'squat-beltless',
                  name: 'Squat beltless',
                  sets: 4,
                  repsMin: 4,
                  repsMax: 4,
                  targetWeightKg: 175,
                ),
              ],
            ),
          ],
        ),
      ],
    );

    test('a re-import keeps the moved days and takes the new values', () {
      final existing = Program(
        id: 'prog1',
        userId: 'u1',
        name: 'Iron Ascent',
        description: 'mine',
        weeks: const [],
        createdAt: DateTime(2026, 11, 9),
        dayMoves: const {'w1-nov-9:day_0': '2026-11-18'},
        sourceSpreadsheetId: 'sheet1',
        sourceModifiedTime: 'old',
        isActive: true,
      );
      final merged = SheetImportService.mergeImportedProgram(
        uid: 'u1',
        preview: preview,
        existing: existing,
        isFirstProgram: false,
        spreadsheetId: 'sheet1',
        sourceModifiedTime: 'new',
      );
      // The move survives: day_0 still lands on Nov 18.
      expect(merged.dayMoves, {'w1-nov-9:day_0': '2026-11-18'});
      // ...and the sheet's new numbers land.
      expect(
        merged.weeks.first.days.first.exercises.first.targetWeightKg,
        175,
      );
      // The app-owned fields survive too.
      expect(merged.id, 'prog1');
      expect(merged.description, 'mine');
      expect(merged.isActive, isTrue);
      expect(merged.sourceModifiedTime, 'new');
    });

    test('a first import starts with no moves and becomes active', () {
      final merged = SheetImportService.mergeImportedProgram(
        uid: 'u1',
        preview: preview,
        existing: null,
        isFirstProgram: true,
      );
      expect(merged.dayMoves, isEmpty);
      expect(merged.isActive, isTrue);
      expect(merged.weeks, preview.weeks);
    });

    test('a later program that is not first stays inactive', () {
      final merged = SheetImportService.mergeImportedProgram(
        uid: 'u1',
        preview: preview,
        existing: null,
        isFirstProgram: false,
      );
      expect(merged.isActive, isFalse);
    });

    test('a move for a day the sheet no longer has is kept verbatim', () {
      final existing = Program(
        id: 'prog1',
        userId: 'u1',
        name: 'Iron Ascent',
        weeks: const [],
        createdAt: DateTime(2026, 11, 9),
        dayMoves: const {'w1-nov-9:day_9': '2026-11-18'},
        isActive: true,
      );
      final merged = SheetImportService.mergeImportedProgram(
        uid: 'u1',
        preview: preview,
        existing: existing,
        isFirstProgram: false,
      );
      expect(merged.dayMoves, {'w1-nov-9:day_9': '2026-11-18'});
    });

    test('a coach import is never active, even as the first program', () {
      final merged = SheetImportService.mergeImportedProgram(
        uid: 'u1',
        preview: preview,
        existing: null,
        isFirstProgram: true,
        coach: true,
      );
      expect(merged.isActive, isFalse);
      expect(merged.weeks, preview.weeks);
    });

    test('a coach re-import stays inactive even when the old one was active',
        () {
      final existing = Program(
        id: 'prog1',
        userId: 'u1',
        name: 'Iron Ascent',
        weeks: const [],
        createdAt: DateTime(2026, 11, 9),
        isActive: true,
      );
      final merged = SheetImportService.mergeImportedProgram(
        uid: 'u1',
        preview: preview,
        existing: existing,
        isFirstProgram: false,
        coach: true,
      );
      expect(merged.isActive, isFalse);
      expect(merged.id, 'prog1');
    });
  });
}
