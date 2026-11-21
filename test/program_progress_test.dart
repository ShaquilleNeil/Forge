import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/models/workout.dart';
import 'package:forge/services/program_progress.dart';

ProgramExercise ex(
  String name, {
  int sets = 3,
  int? repsMin,
  int? repsMax,
  double? weight,
  double? pct,
  String? rpe,
  String? repsText,
}) =>
    ProgramExercise(
      exerciseId: name.toLowerCase().replaceAll(' ', '_'),
      name: name,
      sets: sets,
      repsMin: repsMin,
      repsMax: repsMax,
      repsText: repsText,
      targetWeightKg: weight,
      percentOf1rm: pct,
      targetRpe: rpe,
    );

ProgramDay day(
  String id,
  String title, {
  List<ProgramExercise> exercises = const [],
}) =>
    ProgramDay(id: id, title: title, dayIndex: 0, exercises: exercises);

Program program({
  String id = 'p',
  List<ProgramWeek> weeks = const [],
  bool active = false,
  String? description,
  String? sheetId,
  DateTime? meet,
}) =>
    Program(
      id: id,
      userId: 'u',
      name: 'Iron Ascent',
      description: description,
      weeks: weeks,
      meetPlan: meet == null ? null : MeetPlan(date: meet),
      isActive: active,
      createdAt: DateTime(2026, 1, 1),
      sourceSpreadsheetId: sheetId,
    );

WorkoutSession session(
  String id, {
  String weekId = 'w1',
  String dayId = 'd1',
  String status = 'completed',
  List<String> mixed = const [],
}) =>
    WorkoutSession(
      id: id,
      userId: 'u',
      date: DateTime(2026, 11, 9),
      programId: 'p',
      weekId: weekId,
      dayId: dayId,
      title: 'Workout',
      status: status,
      mixedDayKeys: mixed,
    );

void main() {
  group('programProgress', () {
    test('counts done training days from finished sessions only', () {
      final p = program(weeks: [
        ProgramWeek(id: 'w1', title: 'W1', weekIndex: 0, days: [
          day('d1', 'Mon Nov 9 · D1', exercises: [ex('Squat')]),
          day('d2', 'Tue Nov 10 · D2', exercises: [ex('Bench')]),
          day('d3', 'Wed Nov 11 · Rest day'),
          day('d4', 'Thu Nov 12 · D4'),
        ]),
        ProgramWeek(id: 'w2', title: 'W2', weekIndex: 1, days: [
          day('d5', 'Mon Nov 16 · D1', exercises: [ex('Squat')]),
        ]),
      ]);
      // d1 done, d2 in progress (does not count), d3 is rest, d4 is
      // empty — only d1, d2 and d5 are training days.
      final progress = programProgress(p, [
        session('s1', dayId: 'd1'),
        session('s2', dayId: 'd2', status: 'inProgress'),
      ], now: DateTime(2026, 11, 9));
      expect(progress.doneDays, 1);
      expect(progress.totalDays, 3);
      expect(progress.doneWeeks, 0);
      expect(progress.totalWeeks, 2);
      expect(progress.fraction, closeTo(1 / 3, 0.001));
    });

    test('a mixed session marks both days done', () {
      final p = program(weeks: [
        ProgramWeek(id: 'w1', title: 'W1', weekIndex: 0, days: [
          day('d1', 'Mon Nov 9 · D1', exercises: [ex('Squat')]),
          day('d2', 'Tue Nov 10 · D2', exercises: [ex('Bench')]),
        ]),
      ]);
      final progress = programProgress(p, [
        session('s1', dayId: 'd1', mixed: ['w1:d2']),
      ], now: DateTime(2026, 11, 9));
      expect(progress.doneDays, 2);
      expect(progress.totalDays, 2);
      expect(progress.doneWeeks, 1);
    });

    test('a session for another program does not count', () {
      final p = program(weeks: [
        ProgramWeek(id: 'w1', title: 'W1', weekIndex: 0, days: [
          day('d1', 'Mon Nov 9 · D1', exercises: [ex('Squat')]),
        ]),
      ]);
      final other = WorkoutSession(
        id: 's9',
        userId: 'u',
        date: DateTime(2026, 11, 9),
        programId: 'other',
        weekId: 'w1',
        dayId: 'd1',
        title: 'Workout',
        status: 'completed',
      );
      final progress = programProgress(p, [other],
          now: DateTime(2026, 11, 9));
      expect(progress.doneDays, 0);
      expect(progress.totalDays, 1);
    });
  });

  group('currentWeekIndex', () {
    final p = program(weeks: [
      ProgramWeek(id: 'w1', title: 'W1', weekIndex: 0, days: [
        day('d1', 'Mon Nov 9 · D1', exercises: [ex('Squat')]),
      ]),
      ProgramWeek(id: 'w2', title: 'W2', weekIndex: 1, days: [
        day('d2', 'Mon Nov 16 · D1', exercises: [ex('Squat')]),
      ]),
      ProgramWeek(id: 'w3', title: 'W3', weekIndex: 2, days: [
        day('d3', 'Mon Nov 23 · D1', exercises: [ex('Squat')]),
      ]),
    ]);

    test('today inside a week returns that week', () {
      expect(currentWeekIndex(p, DateTime(2026, 11, 9)), 0);
      expect(currentWeekIndex(p, DateTime(2026, 11, 16)), 1);
    });

    test('today between weeks returns the first future week', () {
      expect(currentWeekIndex(p, DateTime(2026, 11, 12)), 1);
    });

    test('today after the last week returns the last week', () {
      expect(currentWeekIndex(p, DateTime(2026, 12, 1)), 2);
    });

    test('no dated days returns null', () {
      final dateless = program(weeks: [
        ProgramWeek(id: 'w1', title: 'Week 1', weekIndex: 0, days: [
          day('d1', 'Day 1', exercises: [ex('Squat')]),
        ]),
      ]);
      expect(currentWeekIndex(dateless, DateTime(2026, 11, 9)), isNull);
    });
  });

  group('programMetaLine', () {
    test('joins weeks, current week and meet when present', () {
      final p = program(
        weeks: [
          ProgramWeek(id: 'w1', title: 'W1', weekIndex: 0, days: [
            day('d1', 'Mon Nov 9 · D1', exercises: [ex('Squat')]),
          ]),
          ProgramWeek(id: 'w2', title: 'W2', weekIndex: 1, days: [
            day('d2', 'Mon Nov 16 · D1', exercises: [ex('Squat')]),
          ]),
        ],
        meet: DateTime(2027, 1, 16),
      );
      final progress = programProgress(p, [], now: DateTime(2026, 11, 9));
      expect(
        programMetaLine(p, progress),
        '2 weeks · Week 1 of 2 · Meet Jan 16',
      );
    });

    test('omits the week and meet parts when they do not exist', () {
      final p = program(weeks: [
        ProgramWeek(id: 'w1', title: 'Week 1', weekIndex: 0, days: [
          day('d1', 'Day 1', exercises: [ex('Squat')]),
        ]),
      ]);
      final progress = programProgress(p, [], now: DateTime(2026, 11, 9));
      expect(programMetaLine(p, progress), '1 week');
    });
  });

  group('progressLabel', () {
    test('empty, not started, and counted labels', () {
      const empty = ProgramProgress(
        doneDays: 0,
        totalDays: 0,
        doneWeeks: 0,
        totalWeeks: 1,
        currentWeekIndex: null,
      );
      expect(progressLabel(empty), '');
      const fresh = ProgramProgress(
        doneDays: 0,
        totalDays: 12,
        doneWeeks: 0,
        totalWeeks: 3,
        currentWeekIndex: 0,
      );
      expect(progressLabel(fresh), 'Not started yet');
      const partial = ProgramProgress(
        doneDays: 5,
        totalDays: 12,
        doneWeeks: 1,
        totalWeeks: 3,
        currentWeekIndex: 1,
      );
      expect(progressLabel(partial), '5 of 12 days done');
    });
  });

  group('day summaries', () {
    test('estimated minutes are 10 plus 3 per set', () {
      final d = day('d1', 'Mon Nov 9 · D1', exercises: [
        ex('Squat', sets: 4),
        ex('Bench', sets: 3),
      ]);
      expect(estimatedMinutesForDay(d), 10 + 7 * 3);
      expect(daySummaryLine(d), '2 exercises · 7 sets · ~31 min');
    });

    test('rest and empty days say so', () {
      expect(daySummaryLine(day('d1', 'Fri · Rest day')), 'Rest day');
      expect(daySummaryLine(day('d1', 'Day 1')), 'No exercises yet');
    });

    test('preview names show the first two, then an ellipsis', () {
      expect(dayPreviewNames(day('d1', 'Day 1')), '');
      expect(
        dayPreviewNames(day('d1', 'Day 1', exercises: [ex('Squat')])),
        'Squat',
      );
      expect(
        dayPreviewNames(day('d1', 'Day 1', exercises: [
          ex('Squat'),
          ex('Bench'),
          ex('Deadlift'),
        ])),
        'Squat · Bench · …',
      );
    });
  });

  group('exerciseSummary', () {
    test('sets, reps, weight and RPE', () {
      expect(
        exerciseSummary(
          ex('Squat', sets: 4, repsMin: 4, repsMax: 4, weight: 120, rpe: '8'),
          'kg',
        ),
        '4 × 4 · 120 kg · RPE 8',
      );
    });

    test('reps range, percent of 1RM, and pounds', () {
      expect(
        exerciseSummary(
          ex('Bench', sets: 3, repsMin: 8, repsMax: 10, pct: 0.7),
          'kg',
        ),
        '3 × 8–10 · 70% 1RM',
      );
      expect(
        exerciseSummary(ex('Squat', sets: 3, repsMin: 5, weight: 100), 'lb'),
        '3 × 5 · 220 lb',
      );
    });

    test('stored reps text is stripped to the reps part', () {
      expect(
        exerciseSummary(
          ex('Squat', sets: 2, repsText: '2 x 8-10'),
          'kg',
        ),
        '2 × 8-10',
      );
    });
  });
}
