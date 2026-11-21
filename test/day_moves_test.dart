import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/models/workout.dart';
import 'package:forge/services/day_moves.dart';

void main() {
  Program buildProgram({Map<String, String> dayMoves = const {}}) {
    return Program(
      id: 'prog1',
      userId: 'u1',
      name: 'Iron Ascent',
      weeks: [
        const ProgramWeek(
          id: 'w1',
          title: 'W1 Nov 16',
          weekIndex: 0,
          days: [
            ProgramDay(
              id: 'd1',
              title: 'Mon Nov 16 · D1 · Squat + bench',
              dayIndex: 0,
              exercises: [
                ProgramExercise(
                  exerciseId: 'squat',
                  name: 'Squat',
                  sets: 3,
                ),
              ],
            ),
            ProgramDay(
              id: 'd2',
              title: 'Tue Nov 17 · D2 · Deadlift',
              dayIndex: 1,
              exercises: [
                ProgramExercise(
                  exerciseId: 'deadlift',
                  name: 'Deadlift',
                  sets: 3,
                ),
              ],
            ),
            ProgramDay(
              id: 'd3',
              title: 'Wed Nov 18 · D3 · Bench + accessories',
              dayIndex: 2,
              exercises: [
                ProgramExercise(
                  exerciseId: 'bench',
                  name: 'Bench',
                  sets: 3,
                ),
              ],
            ),
            ProgramDay(
              id: 'drest',
              title: 'Thu Nov 19 · Rest',
              dayIndex: 3,
              exercises: [],
            ),
          ],
        ),
      ],
      createdAt: DateTime(2026, 11, 1),
      dayMoves: dayMoves,
    );
  }

  ProgramDay day(Program program, String dayId) => program.weeks.first.days
      .firstWhere((d) => d.id == dayId);

  group('day keys', () {
    test('dayKey round-trips through parseDayKey', () {
      expect(parseDayKey(dayKey('w1', 'd2')), (weekId: 'w1', dayId: 'd2'));
      expect(parseDayKey('no-separator'), isNull);
    });

    test('move dates round-trip', () {
      final date = DateTime(2026, 11, 18);
      expect(parseMoveDate(formatMoveDate(date)), date);
      expect(parseMoveDate('not a date'), isNull);
    });

    test('stripDatePrefix leaves undated titles alone', () {
      expect(
        stripDatePrefix('Mon Nov 16 · D1 · Squat + bench'),
        'D1 · Squat + bench',
      );
      expect(stripDatePrefix('My custom day'), 'My custom day');
    });
  });

  group('daysForDate', () {
    test('a scheduled day shows on its own date', () {
      final program = buildProgram();
      final slots = daysForDate(program, DateTime(2026, 11, 17));
      expect(slots.map((s) => s.day.id), ['d2']);
      expect(slots.first.movedFrom, isNull);
    });

    test('a moved day leaves its old date and joins the new one first',
        () {
      final program = buildProgram();
      final week = program.weeks.first;
      final moved = moveDay(
        program,
        week,
        day(program, 'd2'),
        DateTime(2026, 11, 18),
      );
      // The original is untouched; the move lives on the copy.
      expect(program.dayMoves, isEmpty);
      expect(daysForDate(moved, DateTime(2026, 11, 17)), isEmpty);
      final on18 = daysForDate(moved, DateTime(2026, 11, 18));
      expect(on18.map((s) => s.day.id), ['d2', 'd3']);
      expect(on18.first.movedFrom, DateTime(2026, 11, 17));
      expect(on18.last.movedFrom, isNull);
      // The moved day's effective date is the new one.
      expect(
        effectiveDate(moved, day(moved, 'd2')),
        DateTime(2026, 11, 18),
      );
    });

    test('a moved day suppresses a rest day on its new date', () {
      final program = buildProgram();
      final week = program.weeks.first;
      final moved = moveDay(
        program,
        week,
        day(program, 'd2'),
        DateTime(2026, 11, 19),
      );
      final slots = daysForDate(moved, DateTime(2026, 11, 19));
      expect(slots.map((s) => s.day.id), ['d2']);
    });

    test('a rest day shows when nothing else is on its date', () {
      final program = buildProgram();
      final slots = daysForDate(program, DateTime(2026, 11, 19));
      expect(slots.map((s) => s.day.id), ['drest']);
    });
  });

  group('consumeMoves', () {
    test('finishing deletes the move record — the day goes back', () {
      final program = buildProgram();
      final week = program.weeks.first;
      final moved = moveDay(
        program,
        week,
        day(program, 'd2'),
        DateTime(2026, 11, 18),
      );
      final back = consumeMoves(moved, ['w1:d2']);
      expect(back.dayMoves, isEmpty);
      expect(
        effectiveDate(back, day(back, 'd2')),
        DateTime(2026, 11, 17),
      );
      expect(
        daysForDate(back, DateTime(2026, 11, 17)).map((s) => s.day.id),
        ['d2'],
      );
    });

    test('consuming an unknown key changes nothing', () {
      final program = buildProgram();
      expect(identical(consumeMoves(program, ['w1:nope']), program), isTrue);
    });

    test('slotFor reports where a moved day came from', () {
      final program = buildProgram();
      final week = program.weeks.first;
      final moved = moveDay(
        program,
        week,
        day(program, 'd2'),
        DateTime(2026, 11, 18),
      );
      final slot = slotFor(moved, week, day(moved, 'd2'));
      expect(slot.movedFrom, DateTime(2026, 11, 17));
      final plain = slotFor(program, week, day(program, 'd2'));
      expect(plain.movedFrom, isNull);
    });
  });

  group('hasUncompletedDays', () {
    WorkoutSession doneSession(
      String dayId, {
      List<String> mixed = const [],
      String programId = 'prog1',
    }) {
      return WorkoutSession(
        id: 's-$dayId',
        userId: 'u1',
        date: DateTime(2026, 11, 17),
        programId: programId,
        weekId: 'w1',
        dayId: dayId,
        title: 'done',
        status: 'completed',
        mixedDayKeys: mixed,
      );
    }

    test('true while any training day is uncompleted', () {
      expect(hasUncompletedDays(buildProgram(), []), isTrue);
      expect(
        hasUncompletedDays(buildProgram(), [doneSession('d1')]),
        isTrue,
      );
    });

    test('false once every training day is done — rest days do not count', () {
      expect(
        hasUncompletedDays(buildProgram(), [
          doneSession('d1'),
          doneSession('d2'),
          doneSession('d3'),
        ]),
        isFalse,
      );
    });

    test('a mixed-in day counts as done', () {
      // d3 finished with d2 mixed in: d2 and d3 done, d1 still open.
      expect(
        hasUncompletedDays(buildProgram(), [
          doneSession('d3', mixed: ['w1:d2']),
        ]),
        isTrue,
      );
      expect(
        hasUncompletedDays(buildProgram(), [
          doneSession('d1'),
          doneSession('d3', mixed: ['w1:d2']),
        ]),
        isFalse,
      );
    });

    test('a session from another program does not count', () {
      expect(
        hasUncompletedDays(buildProgram(), [
          doneSession('d1', programId: 'other'),
          doneSession('d2', programId: 'other'),
          doneSession('d3', programId: 'other'),
        ]),
        isTrue,
      );
    });
  });
}
