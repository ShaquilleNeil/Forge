import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/models/workout.dart';
import 'package:forge/screens/runner.dart';

void main() {
  group('supersetPairKey', () {
    test('the two halves of a sheet pair share their letter', () {
      // Nov 19: the sheet labels the halves "A1" and "A2". The
      // letter is the pair, the number is the position in it — so
      // both must map to "A", or they never pair.
      expect(supersetPairKey('A1'), 'A');
      expect(supersetPairKey('A2'), 'A');
      expect(supersetPairKey('B1'), 'B');
    });

    test('a bare letter maps to itself; a two-digit position strips', () {
      expect(supersetPairKey('A'), 'A');
      expect(supersetPairKey('A10'), 'A');
    });
  });

  group('supersetExecutionOrder', () {
    test('superset partners interleave round-robin, then standalone runs',
        () {
      final groups = [
        ('squat', 'Squat', [0, 1, 2, 3]),
        ('bench', 'Bench', [4, 5, 6, 7]),
        ('curl', 'Curl', [8, 9]),
      ];
      final order = supersetExecutionOrder(groups, {
        'squat': 's1',
        'bench': 's1',
        'curl': null,
      });
      expect(order, [0, 4, 1, 5, 2, 6, 3, 7, 8, 9]);
    });

    test('uneven partners: the longer one finishes on its own', () {
      final groups = [
        ('squat', 'Squat', [0, 1, 2]),
        ('bench', 'Bench', [3, 4]),
      ];
      final order = supersetExecutionOrder(groups, {
        'squat': 's1',
        'bench': 's1',
      });
      expect(order, [0, 3, 1, 4, 2]);
    });

    test('no supersets: flat order, unchanged', () {
      final groups = [
        ('squat', 'Squat', [0, 1]),
        ('bench', 'Bench', [2, 3]),
      ];
      final order = supersetExecutionOrder(groups, {
        'squat': null,
        'bench': '',
      });
      expect(order, [0, 1, 2, 3]);
    });

    test('a lone superset group runs in order', () {
      final groups = [
        ('squat', 'Squat', [0, 1]),
        ('bench', 'Bench', [2, 3]),
      ];
      final order = supersetExecutionOrder(groups, {
        'squat': 's1',
        'bench': null,
      });
      expect(order, [0, 1, 2, 3]);
    });

    test('two separate supersets each interleave', () {
      final groups = [
        ('a1', 'A1', [0, 1]),
        ('a2', 'A2', [2, 3]),
        ('b1', 'B1', [4, 5]),
        ('b2', 'B2', [6, 7]),
      ];
      final order = supersetExecutionOrder(groups, {
        'a1': 's1',
        'a2': 's1',
        'b1': 's2',
        'b2': 's2',
      });
      expect(order, [0, 2, 1, 3, 4, 6, 5, 7]);
    });

    test('empty groups: empty order', () {
      expect(supersetExecutionOrder([], {}), isEmpty);
    });

    test('sheet labels A1/A2 pair once normalized to their letter', () {
      // Nov 19: bench "A1" + deadlift "A2" from the sheet. What
      // _supersetGroupOf produces after supersetPairKey — both halves
      // share "d1|A" — so they interleave: bench-1, deadlift-1,
      // bench-2, deadlift-2. The scroll and the rest-after-round
      // both read this order, so this is the test that pins them.
      final groups = [
        ('d1|bench', 'Bench', [0, 1]),
        ('d1|deadlift', 'Deadlift', [2, 3]),
      ];
      final order = supersetExecutionOrder(groups, {
        'd1|bench': 'd1|A',
        'd1|deadlift': 'd1|A',
      });
      expect(order, [0, 2, 1, 3]);
    });

    test('raw A1 vs A2 labels do not pair — that is why they normalize',
        () {
      final groups = [
        ('d1|bench', 'Bench', [0, 1]),
        ('d1|deadlift', 'Deadlift', [2, 3]),
      ];
      final order = supersetExecutionOrder(groups, {
        'd1|bench': 'd1|A1',
        'd1|deadlift': 'd1|A2',
      });
      expect(order, [0, 1, 2, 3]);
    });

    test('different cross-day link letters are different pairs', () {
      // What _supersetGroupOf produces for links: the shared letter,
      // not the badge. S and T never merge.
      final groups = [
        ('d2|squat', 'Squat', [0, 1]),
        ('d3|row', 'Row', [2, 3]),
      ];
      final order = supersetExecutionOrder(groups, {
        'd2|squat': 'S',
        'd3|row': 'T',
      });
      expect(order, [0, 1, 2, 3]);
    });
  });

  group('shouldStartRestAfterSet', () {
    // A1 (squat, sets 0-1) + A2 (bench, sets 0-1) in superset s1,
    // executed [0, 2, 1, 3]: squat-0, bench-0, squat-1, bench-1.
    List<SessionSet> sets({
      bool squat0Done = false,
      bool bench0Done = false,
      bool bench0Skipped = false,
    }) =>
        [
          SessionSet(
            exerciseId: 'squat',
            name: 'Squat',
            setIndex: 0,
            weightKg: 170,
            reps: 4,
            completed: squat0Done,
          ),
          const SessionSet(
            exerciseId: 'squat',
            name: 'Squat',
            setIndex: 1,
            weightKg: 170,
            reps: 4,
          ),
          SessionSet(
            exerciseId: 'bench',
            name: 'Bench',
            setIndex: 0,
            weightKg: 137.5,
            reps: 4,
            completed: bench0Done,
            skipped: bench0Skipped,
          ),
          const SessionSet(
            exerciseId: 'bench',
            name: 'Bench',
            setIndex: 1,
            weightKg: 137.5,
            reps: 4,
          ),
        ];

    const order = [0, 2, 1, 3];
    const groupOf = {'squat': 's1', 'bench': 's1'};

    test('first exercise of the round: no rest, partner is next', () {
      expect(
        shouldStartRestAfterSet(
          order: order,
          sets: sets(),
          supersetGroupOf: groupOf,
          completedIndex: 0,
        ),
        isFalse,
      );
    });

    test('second exercise of the round: rest starts', () {
      expect(
        shouldStartRestAfterSet(
          order: order,
          sets: sets(squat0Done: true),
          supersetGroupOf: groupOf,
          completedIndex: 2,
        ),
        isTrue,
      );
    });

    test('standalone set: rest starts', () {
      expect(
        shouldStartRestAfterSet(
          order: order,
          sets: sets(),
          supersetGroupOf: {'squat': null, 'bench': null},
          completedIndex: 0,
        ),
        isTrue,
      );
    });

    test('partner same-round set skipped: rest starts', () {
      expect(
        shouldStartRestAfterSet(
          order: order,
          sets: sets(bench0Skipped: true),
          supersetGroupOf: groupOf,
          completedIndex: 0,
        ),
        isTrue,
      );
    });

    test('last set of the workout: rest starts', () {
      expect(
        shouldStartRestAfterSet(
          order: order,
          sets: sets(squat0Done: true, bench0Done: true),
          supersetGroupOf: groupOf,
          completedIndex: 3,
        ),
        isTrue,
      );
    });

    test('sheet pair bench A1 + deadlift A2: no rest mid-round, rest after',
        () {
      // Nov 19, day-namespaced like real data: bench-0, deadlift-0,
      // bench-1, deadlift-1, both halves on "d1|A" after
      // supersetPairKey. Finishing bench-0 must NOT rest (deadlift-0
      // is next); finishing deadlift-0 must rest and scroll back.
      final dSets = [
        const SessionSet(
          exerciseId: 'bench',
          name: 'Bench',
          setIndex: 0,
          weightKg: 137.5,
          reps: 4,
          dayId: 'd1',
        ),
        const SessionSet(
          exerciseId: 'bench',
          name: 'Bench',
          setIndex: 1,
          weightKg: 137.5,
          reps: 4,
          dayId: 'd1',
        ),
        const SessionSet(
          exerciseId: 'deadlift',
          name: 'Deadlift',
          setIndex: 0,
          weightKg: 200,
          reps: 4,
          dayId: 'd1',
        ),
        const SessionSet(
          exerciseId: 'deadlift',
          name: 'Deadlift',
          setIndex: 1,
          weightKg: 200,
          reps: 4,
          dayId: 'd1',
        ),
      ];
      const dOrder = [0, 2, 1, 3];
      const dGroupOf = {'d1|bench': 'd1|A', 'd1|deadlift': 'd1|A'};
      expect(
        shouldStartRestAfterSet(
          order: dOrder,
          sets: dSets,
          supersetGroupOf: dGroupOf,
          completedIndex: 0,
        ),
        isFalse,
      );
      final afterBench = [
        dSets[0].copyWith(completed: true),
        dSets[1],
        dSets[2],
        dSets[3],
      ];
      expect(
        shouldStartRestAfterSet(
          order: dOrder,
          sets: afterBench,
          supersetGroupOf: dGroupOf,
          completedIndex: 2,
        ),
        isTrue,
      );
    });
  });

  group('mixed sessions (day-tagged sets)', () {
    test('the same exercise in two days stays two groups, and the same superset letter does not pair across days',
        () {
      final groups = [
        ('d2|squat', 'Squat', [0, 1]),
        ('d2|bench', 'Bench', [2, 3]),
        ('d3|bench', 'Bench', [4, 5]),
        ('d3|curl', 'Curl', [6, 7]),
      ];
      final order = supersetExecutionOrder(groups, {
        'd2|squat': 'd2|A',
        'd2|bench': 'd2|A',
        'd3|bench': 'd3|A',
        'd3|curl': null,
      });
      // Day 2's superset interleaves; day 3's "A" is a lone group in
      // its own day, so it runs flat — the two days never mix their
      // supersets, even though both use the letter A and both have a
      // bench block.
      expect(order, [0, 2, 1, 3, 4, 5, 6, 7]);
    });

    test('shouldStartRestAfterSet reads the set\'s day tag', () {
      // Day 2: squat + bench in superset A. Day 3: bench alone.
      const sets = [
        SessionSet(
          exerciseId: 'squat',
          name: 'Squat',
          setIndex: 0,
          weightKg: 170,
          reps: 4,
          dayId: 'd2',
        ),
        SessionSet(
          exerciseId: 'squat',
          name: 'Squat',
          setIndex: 1,
          weightKg: 170,
          reps: 4,
          dayId: 'd2',
        ),
        SessionSet(
          exerciseId: 'bench',
          name: 'Bench',
          setIndex: 0,
          weightKg: 137.5,
          reps: 4,
          dayId: 'd2',
        ),
        SessionSet(
          exerciseId: 'bench',
          name: 'Bench',
          setIndex: 1,
          weightKg: 137.5,
          reps: 4,
          dayId: 'd2',
        ),
        SessionSet(
          exerciseId: 'bench',
          name: 'Bench',
          setIndex: 0,
          weightKg: 130,
          reps: 5,
          dayId: 'd3',
        ),
        SessionSet(
          exerciseId: 'bench',
          name: 'Bench',
          setIndex: 1,
          weightKg: 130,
          reps: 5,
          dayId: 'd3',
        ),
      ];
      const order = [0, 2, 1, 3, 4, 5];
      const groupOf = {
        'd2|squat': 'd2|A',
        'd2|bench': 'd2|A',
        'd3|bench': null,
      };
      // Day 2 squat set 1: its partner bench is next — no rest.
      expect(
        shouldStartRestAfterSet(
          order: order,
          sets: sets,
          supersetGroupOf: groupOf,
          completedIndex: 0,
        ),
        isFalse,
      );
      // Day 3 bench set 1: standalone in its own day — rest starts,
      // even though day 2's bench is in a superset.
      expect(
        shouldStartRestAfterSet(
          order: order,
          sets: sets,
          supersetGroupOf: groupOf,
          completedIndex: 4,
        ),
        isTrue,
      );
    });
  });

  group('cross-day superset links', () {
    test('linkPairLetter: S first, then T, then Z, then AA', () {
      expect(linkPairLetter(0), 'S');
      expect(linkPairLetter(1), 'T');
      expect(linkPairLetter(7), 'Z');
      expect(linkPairLetter(8), 'AA');
      expect(linkPairLetter(9), 'AB');
    });

    test('linkCrossDay assigns S1 then S2 — the pair shares its letter',
        () {
      final first = linkCrossDay({}, 'd2|bench', 'd3|row');
      // Bench was tapped first, row picked second: S1 then S2.
      expect(first, {'d2|bench': 'S1', 'd3|row': 'S2'});
      final second = linkCrossDay(first, 'd2|squat', 'd3|curl');
      expect(second['d2|squat'], 'T1');
      expect(second['d3|curl'], 'T2');
      expect(second['d2|bench'], 'S1');
      expect(second['d3|row'], 'S2');
    });

    test('linking an exercise moves it: its old partner is freed', () {
      final links = linkCrossDay(
        {'d2|bench': 'S1', 'd3|row': 'S2'},
        'd2|bench',
        'd3|curl',
      );
      expect(links, {'d2|bench': 'S1', 'd3|curl': 'S2'});
      expect(links.containsKey('d3|row'), isFalse);
    });

    test('unlinkCrossDay removes both sides of the pair', () {
      const links = {
        'd2|bench': 'S1',
        'd3|row': 'S2',
        'd2|squat': 'T1',
        'd3|curl': 'T2',
      };
      expect(
        unlinkCrossDay(links, 'd3|row'),
        {'d2|squat': 'T1', 'd3|curl': 'T2'},
      );
      expect(unlinkCrossDay(links, 'd2|bench'), {
        'd2|squat': 'T1',
        'd3|curl': 'T2',
      });
      expect(unlinkCrossDay(links, 'd9|missing'), links);
    });

    test('linking an exercise to itself is a no-op', () {
      const links = {'d2|bench': 'S1', 'd3|row': 'S2'};
      expect(linkCrossDay(links, 'd2|bench', 'd2|bench'), links);
    });

    test('a linked cross-day pair interleaves, even with the same '
        'sheet letter on both days', () {
      // Day 2 bench and day 3 row share the link letter S; both days
      // also use the sheet letter A for their own pairs — the link
      // is what pairs them, not the letter.
      final groups = [
        ('d2|bench', 'Bench', [0, 1]),
        ('d2|squat', 'Squat', [2, 3]),
        ('d3|row', 'Row', [4, 5]),
        ('d3|curl', 'Curl', [6, 7]),
      ];
      final order = supersetExecutionOrder(groups, {
        'd2|bench': 'S',
        'd2|squat': 'd2|A',
        'd3|row': 'S',
        'd3|curl': null,
      });
      expect(order, [0, 4, 1, 5, 2, 3, 6, 7]);
    });

    test('shouldStartRestAfterSet treats a cross-day partner like a '
        'same-day one', () {
      const sets = [
        SessionSet(
          exerciseId: 'bench',
          name: 'Bench',
          setIndex: 0,
          weightKg: 100,
          reps: 8,
          dayId: 'd2',
        ),
        SessionSet(
          exerciseId: 'bench',
          name: 'Bench',
          setIndex: 1,
          weightKg: 100,
          reps: 8,
          dayId: 'd2',
        ),
        SessionSet(
          exerciseId: 'row',
          name: 'Row',
          setIndex: 0,
          weightKg: 80,
          reps: 10,
          dayId: 'd3',
        ),
        SessionSet(
          exerciseId: 'row',
          name: 'Row',
          setIndex: 1,
          weightKg: 80,
          reps: 10,
          dayId: 'd3',
        ),
      ];
      const order = [0, 2, 1, 3];
      const groupOf = {'d2|bench': 'S', 'd3|row': 'S'};
      // Bench set 1: the row partner is next — no rest.
      expect(
        shouldStartRestAfterSet(
          order: order,
          sets: sets,
          supersetGroupOf: groupOf,
          completedIndex: 0,
        ),
        isFalse,
      );
      // Row set 1: the round is over — rest starts.
      expect(
        shouldStartRestAfterSet(
          order: order,
          sets: sets,
          supersetGroupOf: groupOf,
          completedIndex: 2,
        ),
        isTrue,
      );
    });

    test('cross-day links survive a session JSON round-trip', () {
      final session = WorkoutSession(
        id: 's1',
        userId: 'u1',
        date: DateTime(2026, 11, 19),
        title: 'D2 + D3',
        crossDaySupersets: {'d2|bench': 'S1', 'd3|row': 'S2'},
      );
      final restored = WorkoutSession.fromJson(session.toJson());
      expect(restored.crossDaySupersets, {
        'd2|bench': 'S1',
        'd3|row': 'S2',
      });
    });
  });

  group('set editor type-in', () {
    test('formatNumberInput drops trailing zeros and units', () {
      expect(formatNumberInput(170.0), '170');
      expect(formatNumberInput(137.5), '137.5');
      expect(formatNumberInput(120.25), '120.25');
      expect(formatNumberInput(0), '0');
    });

    test('parseWeightInput reads decimals and clamps to the stepper range', () {
      expect(parseWeightInput('170'), 170.0);
      expect(parseWeightInput('137.5'), 137.5);
      expect(parseWeightInput(' 170 '), 170.0);
      expect(parseWeightInput('600'), 500.0);
      expect(parseWeightInput('-5'), 0.0);
    });

    test('parseWeightInput rejects non-numbers', () {
      expect(parseWeightInput(''), isNull);
      expect(parseWeightInput('abc'), isNull);
      expect(parseWeightInput('170kg'), isNull);
    });

    test('parseRepsInput reads whole numbers and clamps to 1–99', () {
      expect(parseRepsInput('8'), 8);
      expect(parseRepsInput(' 10 '), 10);
      expect(parseRepsInput('0'), 1);
      expect(parseRepsInput('150'), 99);
    });

    test('parseRepsInput rejects decimals and non-numbers', () {
      expect(parseRepsInput('8.5'), isNull);
      expect(parseRepsInput(''), isNull);
      expect(parseRepsInput('eight'), isNull);
    });
  });

  group('copySetsFor', () {
    const day = ProgramDay(
      id: 'd1',
      title: 'Mon Nov 16 · D1 · Squat + bench',
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
          repsMax: 8,
        ),
      ],
    );

    test('builds one set per prescribed set, tagged with the day', () {
      final sets = copySetsFor(day, (ex) => ex.targetWeightKg ?? 0);
      expect(sets.length, 6);
      expect(
        sets.map((s) => s.exerciseId).toList(),
        ['squat', 'squat', 'squat', 'bench', 'bench', 'bench'],
      );
      expect(sets.map((s) => s.setIndex).toList(), [0, 1, 2, 0, 1, 2]);
      expect(sets.map((s) => s.dayId).toSet(), {'d1'});
      expect(
        sets.map((s) => s.blockKey).toSet(),
        {'d1|squat', 'd1|bench'},
      );
      expect(sets.first.weightKg, 120);
      expect(sets.first.reps, 5);
      // Bench takes the min reps when no target weight is given.
      expect(sets[3].reps, 5);
    });

    test('a day with no exercises copies to no sets', () {
      const empty = ProgramDay(
        id: 'd9',
        title: 'Rest',
        dayIndex: 6,
        exercises: [],
      );
      expect(copySetsFor(empty, (ex) => 0), isEmpty);
    });
  });
}
