import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/screens/coach_program_detail.dart';
import 'package:forge/screens/coach_programs.dart';
import 'package:forge/services/coach_service.dart';
import 'package:forge/services/program_progress.dart';

void main() {
  group('formatPrescription', () {
    test('sets, reps, weight and RPE', () {
      const exercise = ProgramExercise(
        exerciseId: 'squat',
        name: 'Squat',
        sets: 3,
        repsText: '8-10',
        targetWeightKg: 120,
        targetRpe: '8',
      );
      expect(formatPrescription(exercise), '3 × 8-10 · 120 kg · RPE 8');
    });

    test('percent of 1RM instead of weight', () {
      const exercise = ProgramExercise(
        exerciseId: 'bench',
        name: 'Bench',
        sets: 4,
        repsText: '5',
        percentOf1rm: 80,
      );
      expect(formatPrescription(exercise), '4 × 5 · 80% 1RM');
    });

    test('reps only', () {
      const exercise = ProgramExercise(
        exerciseId: 'plank',
        name: 'Side plank',
        sets: 2,
        repsText: '30 s/side',
      );
      expect(formatPrescription(exercise), '2 × 30 s/side');
    });

    test('strips a leading sets prefix from an old import', () {
      const exercise = ProgramExercise(
        exerciseId: 'squat',
        name: 'Squat',
        sets: 2,
        repsText: '2 x 8-10',
      );
      expect(formatPrescription(exercise), '2 × 8-10');
    });
  });

  group('findActiveProgram', () {
    Program program(
      String id, {
      bool active = false,
      String? fromCoachUid,
      DateTime? createdAt,
    }) =>
        Program(
          id: id,
          userId: 'u1',
          name: id,
          createdAt: createdAt ?? DateTime(2026, 11, 16),
          isActive: active,
          fromCoachUid: fromCoachUid,
        );

    test('returns the active program', () {
      final programs = [program('a'), program('b', active: true)];
      expect(findActiveProgram(programs)?.id, 'b');
    });

    test('null when nothing is active', () {
      expect(findActiveProgram([program('a')]), isNull);
    });

    test('null for an empty list', () {
      expect(findActiveProgram([]), isNull);
    });
  });

  group('latestSentByMe', () {
    Program program(
      String id, {
      String? fromCoachUid,
      DateTime? createdAt,
    }) =>
        Program(
          id: id,
          userId: 'u1',
          name: id,
          createdAt: createdAt ?? DateTime(2026, 11, 16),
          fromCoachUid: fromCoachUid,
        );

    test('returns the latest program sent by this coach', () {
      final programs = [
        program('old',
            fromCoachUid: 'coach1',
            createdAt: DateTime(2026, 11, 14)),
        program('new',
            fromCoachUid: 'coach1',
            createdAt: DateTime(2026, 11, 16)),
      ];
      expect(latestSentByMe(programs, 'coach1')?.id, 'new');
    });

    test('ignores programs sent by another coach', () {
      final programs = [
        program('theirs', fromCoachUid: 'coach2'),
      ];
      expect(latestSentByMe(programs, 'coach1'), isNull);
    });

    test('ignores the client’s own programs', () {
      final programs = [program('own')];
      expect(latestSentByMe(programs, 'coach1'), isNull);
    });

    test('null for an empty list', () {
      expect(latestSentByMe([], 'coach1'), isNull);
    });
  });

  group('coachCopyOf', () {
    Program source() => Program(
          id: 'prog-train',
          userId: 'u1',
          name: 'Iron Ascent',
          description: 'My block',
          weeks: const [
            ProgramWeek(
              id: 'w1',
              title: 'Week 1',
              weekIndex: 0,
              days: [
                ProgramDay(
                  id: 'd1',
                  title: 'Mon Nov 9 · D1',
                  dayIndex: 0,
                  exercises: [
                    ProgramExercise(
                      exerciseId: 'squat',
                      name: 'Squat',
                      sets: 3,
                    ),
                  ],
                ),
              ],
            ),
          ],
          meetPlan: const MeetPlan(
            date: null,
            attempts: [],
          ),
          isActive: true,
          createdAt: DateTime(2026, 11, 1),
          sourceSpreadsheetId: 'sheet-1',
          sourceModifiedTime: 't0',
          fromCoachUid: 'someone',
          fromCoachName: 'Someone',
          dayMoves: const {'w1:d1': '2026-11-18'},
          sentToClientIds: const ['client-1'],
        );

    test('is a clean snapshot: new id, never active, nothing linked', () {
      final copy = coachCopyOf(
        source(),
        newId: 'prog-coach',
        now: DateTime(2026, 11, 21),
      );
      expect(copy.id, 'prog-coach');
      expect(copy.userId, 'u1');
      expect(copy.name, 'Iron Ascent');
      expect(copy.description, 'My block');
      expect(copy.isActive, isFalse);
      expect(copy.createdAt, DateTime(2026, 11, 21));
      expect(copy.meetPlan, isNull);
      expect(copy.sourceSpreadsheetId, isNull);
      expect(copy.sourceModifiedTime, isNull);
      expect(copy.fromCoachUid, isNull);
      expect(copy.fromCoachName, isNull);
      expect(copy.dayMoves, isEmpty);
      expect(copy.sentToClientIds, isEmpty);
    });

    test('keeps the weeks verbatim', () {
      final copy = coachCopyOf(
        source(),
        newId: 'prog-coach',
        now: DateTime(2026, 11, 21),
      );
      expect(copy.weeks.length, 1);
      expect(copy.weeks.first.days.first.exercises.first.name, 'Squat');
    });

    test('editing the copy does not touch the source', () {
      final original = source();
      final copy = coachCopyOf(
        original,
        newId: 'prog-coach',
        now: DateTime(2026, 11, 21),
      );
      final renamed = copy.copyWith(name: 'Renamed');
      expect(renamed.name, 'Renamed');
      expect(original.name, 'Iron Ascent');
    });
  });

  group('sentToClientIds', () {
    test('survives a JSON round-trip', () {
      final program = Program(
        id: 'p',
        userId: 'u',
        name: 'Beginner Strength',
        createdAt: DateTime(2026, 11, 21),
        sentToClientIds: const ['c1', 'c2'],
      );
      final restored = Program.fromJson(program.toJson());
      expect(restored.sentToClientIds, ['c1', 'c2']);
    });

    test('defaults to empty for old docs without the field', () {
      final program = Program.fromJson({
        'id': 'p',
        'userId': 'u',
        'name': 'Old',
        'createdAt': '2026-11-21T00:00:00.000',
      });
      expect(program.sentToClientIds, isEmpty);
    });
  });

  group('coachProgramMetaLine', () {
    test('weeks and days, plural', () {
      final program = Program(
        id: 'p',
        userId: 'u',
        name: 'Block',
        weeks: const [
          ProgramWeek(id: 'w1', title: 'W1', weekIndex: 0, days: [
            ProgramDay(id: 'd1', title: 'D1', dayIndex: 0),
            ProgramDay(id: 'd2', title: 'D2', dayIndex: 1),
          ]),
          ProgramWeek(id: 'w2', title: 'W2', weekIndex: 1, days: [
            ProgramDay(id: 'd3', title: 'D1', dayIndex: 0),
          ]),
        ],
        createdAt: DateTime(2026, 11, 21),
      );
      expect(coachProgramMetaLine(program), '2 weeks · 3 days');
    });

    test('singular week and day', () {
      final program = Program(
        id: 'p',
        userId: 'u',
        name: 'Block',
        weeks: const [
          ProgramWeek(id: 'w1', title: 'W1', weekIndex: 0, days: [
            ProgramDay(id: 'd1', title: 'D1', dayIndex: 0),
          ]),
        ],
        createdAt: DateTime(2026, 11, 21),
      );
      expect(coachProgramMetaLine(program), '1 week · 1 day');
    });
  });
}
