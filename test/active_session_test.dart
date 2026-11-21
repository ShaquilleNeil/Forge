import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/workout.dart';
import 'package:forge/services/active_session.dart';

WorkoutSession _sessionWithSets(List<SessionSet> sets) => WorkoutSession(
      id: 's1',
      userId: 'u1',
      date: DateTime(2026, 11, 17, 18, 0),
      title: 'Test day',
      sets: sets,
    );

SessionSet _set(
  String exerciseId,
  String name,
  int setIndex, {
  bool completed = false,
  bool skipped = false,
}) =>
    SessionSet(
      exerciseId: exerciseId,
      name: name,
      setIndex: setIndex,
      weightKg: 100,
      reps: 5,
      completed: completed,
      skipped: skipped,
    );

void main() {
  group('nextOpenSet', () {
    test('returns the first incomplete, non-skipped set', () {
      final session = _sessionWithSets([
        _set('squat', 'Squat', 0, completed: true),
        _set('squat', 'Squat', 1, skipped: true),
        _set('bench', 'Bench Press', 0),
        _set('bench', 'Bench Press', 1),
      ]);
      final next = nextOpenSet(session);
      expect(next, isNotNull);
      expect(next!.exerciseId, 'bench');
      expect(next.setIndex, 0);
    });

    test('returns null when every set is done or skipped', () {
      final session = _sessionWithSets([
        _set('squat', 'Squat', 0, completed: true),
        _set('squat', 'Squat', 1, skipped: true),
      ]);
      expect(nextOpenSet(session), isNull);
    });
  });

  group('formatElapsed', () {
    test('MM:SS under an hour', () {
      final start = DateTime(2026, 11, 17, 18, 0);
      expect(formatElapsed(start, start.add(const Duration(minutes: 7, seconds: 5))), '07:05');
      expect(formatElapsed(start, start.add(const Duration(seconds: 45))), '00:45');
    });

    test('H:MM:SS once it passes an hour', () {
      final start = DateTime(2026, 11, 17, 18, 0);
      expect(
        formatElapsed(start, start.add(const Duration(hours: 1, minutes: 12, seconds: 3))),
        '1:12:03',
      );
    });
  });

  group('formatRestRemaining', () {
    test('null when not resting', () {
      expect(formatRestRemaining(null, DateTime.now()), isNull);
    });

    test('M:SS while resting', () {
      final now = DateTime(2026, 11, 17, 18, 0);
      expect(
        formatRestRemaining(now.add(const Duration(seconds: 95)), now),
        '1:35',
      );
    });

    test('0:00 at or past the end', () {
      final now = DateTime(2026, 11, 17, 18, 0);
      expect(formatRestRemaining(now, now), '0:00');
      expect(
        formatRestRemaining(now.subtract(const Duration(seconds: 10)), now),
        '0:00',
      );
    });
  });

  group('WorkoutSession restEndsAt', () {
    test('round-trips through JSON and copyWith clears it', () {
      final endsAt = DateTime(2026, 11, 17, 18, 3);
      final session = _sessionWithSets([_set('squat', 'Squat', 0)])
          .copyWith(restEndsAt: endsAt, restTotalSec: 180);
      final restored =
          WorkoutSession.fromJson(session.toJson());
      expect(restored.restEndsAt, endsAt);
      expect(restored.restTotalSec, 180);
      expect(restored.copyWith(clearRest: true).restEndsAt, isNull);
      expect(restored.copyWith(clearRest: true).restTotalSec, isNull);
      expect(restored.copyWith().restEndsAt, endsAt);
      expect(restored.copyWith().restTotalSec, 180);
    });

    test('old sessions without the field restore with null restEndsAt', () {
      final json = _sessionWithSets([_set('squat', 'Squat', 0)]).toJson()
        ..remove('restEndsAt')
        ..remove('restTotalSec');
      expect(WorkoutSession.fromJson(json).restEndsAt, isNull);
      expect(WorkoutSession.fromJson(json).restTotalSec, isNull);
    });
  });
}
