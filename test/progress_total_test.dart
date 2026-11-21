import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/record.dart';
import 'package:forge/screens/progress.dart';

Record record(String exerciseId, double weight) => Record(
      exerciseId: exerciseId,
      bestWeightKg: weight,
      bestE1rmKg: weight,
      date: DateTime(2026, 11, 19),
    );

void main() {
  group('totalForDots', () {
    test('records alone: sums the three lifts', () {
      expect(
        totalForDots(
          {
            'squat': record('squat', 180),
            'bench': record('bench', 120),
            'deadlift': record('deadlift', 200),
          },
          null,
        ),
        500,
      );
    });

    test('profile lifts alone: the fallback Today already uses', () {
      // Profile lifts only: no records yet, but the profile holds
      // 210 / 125 / 205 — DOTS must show 540, not nothing.
      expect(
        totalForDots(
          {},
          {'squat': 210, 'bench': 125, 'deadlift': 205},
        ),
        540,
      );
    });

    test('a record beats the profile lift for the same lift', () {
      expect(
        totalForDots(
          {'squat': record('squat', 185)},
          {'squat': 210, 'bench': 125, 'deadlift': 205},
        ),
        // 185 (record) + 125 + 205 (profile), not 210.
        515,
      );
    });

    test('a partial mix still totals: one record, two profile lifts', () {
      expect(
        totalForDots(
          {'deadlift': record('deadlift', 205)},
          {'squat': 210, 'bench': 125},
        ),
        540,
      );
    });

    test('neither records nor profile lifts: null, so the card hides', () {
      expect(totalForDots({}, null), isNull);
      expect(totalForDots({}, {}), isNull);
    });

    test('a zero profile lift counts as nothing', () {
      expect(
        totalForDots({}, {'squat': 0, 'bench': 125, 'deadlift': 205}),
        330,
      );
      expect(totalForDots({}, {'squat': 0}), isNull);
    });

    test('records under other exercise ids do not count', () {
      expect(
        totalForDots(
          {'squat-beltless': record('squat-beltless', 200)},
          null,
        ),
        isNull,
      );
    });
  });
}
