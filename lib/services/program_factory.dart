import '../models/program.dart';
import 'strength_math.dart';

String newProgramId(String prefix) =>
    '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

/// A blank program: one week, one empty day. Shared by the training
/// and coach sides — the sides differ only in which collection the
/// program is saved to, never in how it is built.
Program buildBlankProgram({required String uid, required String name}) {
  return Program(
    id: newProgramId('prog'),
    userId: uid,
    name: name,
    weeks: [
      ProgramWeek(
        id: newProgramId('week'),
        title: 'Week 1',
        weekIndex: 0,
        days: [
          ProgramDay(
            id: newProgramId('day'),
            title: 'Day 1 — Training',
            dayIndex: 0,
          ),
        ],
      ),
    ],
    createdAt: DateTime.now(),
  );
}

/// The Simple Strength (3-day) template, built from 1RMs. [mainLifts]
/// maps 'squat'/'bench'/'deadlift' to kg; a missing lift falls back
/// to 180/120/200 — the template is a starting point the coach
/// adjusts either way, on either side.
Program buildTemplateProgram({
  required String uid,
  required String name,
  required Map<String, double> mainLifts,
}) {
  double lift(String key, double fallback) => mainLifts[key] ?? fallback;
  double at(double lift, double pct) =>
      StrengthMath.roundToIncrement(lift * pct, 2.5);
  ProgramExercise main(String id, String label, double weight) =>
      ProgramExercise(
        exerciseId: id,
        name: label,
        sets: 3,
        repsMin: 5,
        repsMax: 5,
        targetWeightKg: weight,
        percentOf1rm: 0.70,
      );
  ProgramExercise accessory(String id, String label, int sets, int reps) =>
      ProgramExercise(
        exerciseId: id,
        name: label,
        sets: sets,
        repsMin: reps,
        repsMax: reps,
      );
  return Program(
    id: newProgramId('prog'),
    userId: uid,
    name: name,
    description: 'Simple Strength (3-day)',
    weeks: [
      ProgramWeek(
        id: newProgramId('week'),
        title: 'Week 1',
        weekIndex: 0,
        days: [
          ProgramDay(
            id: newProgramId('day'),
            title: 'Day 1 — Squat',
            dayIndex: 0,
            exercises: [
              main('squat', 'Squat', at(lift('squat', 180), 0.70)),
              accessory('legpress', 'Leg Press', 3, 10),
              accessory('rdl', 'Romanian Deadlift', 3, 8),
            ],
          ),
          ProgramDay(
            id: newProgramId('day'),
            title: 'Day 2 — Bench',
            dayIndex: 1,
            exercises: [
              main('bench', 'Bench Press', at(lift('bench', 120), 0.70)),
              accessory('ohp', 'Overhead Press', 3, 8),
              accessory('dips', 'Dips', 3, 10),
              accessory('row', 'Barbell Row', 3, 8),
            ],
          ),
          ProgramDay(
            id: newProgramId('day'),
            title: 'Day 3 — Deadlift',
            dayIndex: 2,
            exercises: [
              main('deadlift', 'Deadlift', at(lift('deadlift', 200), 0.70)),
              main('squat', 'Squat', at(lift('squat', 180), 0.60)),
              accessory('pullup', 'Pull-Up', 3, 8),
              accessory('row', 'Barbell Row', 3, 8),
            ],
          ),
        ],
      ),
    ],
    createdAt: DateTime.now(),
  );
}
