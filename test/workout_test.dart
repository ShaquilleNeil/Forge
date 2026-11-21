import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/workout.dart';

void main() {
  group('SessionSet.copyWith clearVideo', () {
    const set = SessionSet(
      exerciseId: 'squat',
      name: 'Squat',
      setIndex: 0,
      weightKg: 170,
      reps: 4,
      videoPath: '/tmp/clip.mp4',
      videoUrl: 'https://example.com/clip.mp4',
    );

    test('clearVideo clears both the local path and the uploaded URL', () {
      final cleared = set.copyWith(clearVideo: true);
      expect(cleared.videoPath, isNull);
      expect(cleared.videoUrl, isNull);
      expect(cleared.weightKg, 170);
      expect(cleared.reps, 4);
    });

    test('copyWith without clearVideo keeps the video', () {
      final updated = set.copyWith(weightKg: 175);
      expect(updated.videoPath, '/tmp/clip.mp4');
      expect(updated.videoUrl, 'https://example.com/clip.mp4');
      expect(updated.weightKg, 175);
    });

    test('clearVideo on a set with no video is a no-op', () {
      const bare = SessionSet(
        exerciseId: 'bench',
        name: 'Bench',
        setIndex: 1,
        weightKg: 137.5,
        reps: 4,
      );
      final cleared = bare.copyWith(clearVideo: true);
      expect(cleared.videoPath, isNull);
      expect(cleared.videoUrl, isNull);
    });
  });

  group('mixed sessions', () {
    test('blockKey separates the same exercise in two days', () {
      const d2Bench = SessionSet(
        exerciseId: 'bench',
        name: 'Bench',
        setIndex: 0,
        weightKg: 130,
        reps: 5,
        dayId: 'd2',
      );
      const d3Bench = SessionSet(
        exerciseId: 'bench',
        name: 'Bench',
        setIndex: 0,
        weightKg: 125,
        reps: 5,
        dayId: 'd3',
      );
      expect(d2Bench.blockKey, 'd2|bench');
      expect(d3Bench.blockKey, 'd3|bench');
      expect(d2Bench.blockKey, isNot(d3Bench.blockKey));
    });

    test('a set with no day tag keys by exercise alone', () {
      const free = SessionSet(
        exerciseId: 'bench',
        name: 'Bench',
        setIndex: 0,
        weightKg: 100,
        reps: 5,
      );
      expect(free.blockKey, 'bench');
    });

    test('coversDay matches the primary day and the mixed-in days', () {
      final session = WorkoutSession(
        id: 's1',
        userId: 'u1',
        date: DateTime(2026, 11, 18),
        programId: 'prog1',
        weekId: 'w1',
        dayId: 'd3',
        title: 'D2 + D3',
        status: 'completed',
        mixedDayKeys: ['w1:d2'],
      );
      expect(session.coversDay('prog1', 'w1', 'd3'), isTrue);
      expect(session.coversDay('prog1', 'w1', 'd2'), isTrue);
      expect(session.coversDay('prog1', 'w1', 'd1'), isFalse);
      expect(session.coversDay('prog2', 'w1', 'd3'), isFalse);
      expect(session.coveredDayKeys, ['w1:d3', 'w1:d2']);
    });

    test('mixedDayKeys survive a JSON round-trip and copyWith', () {
      final session = WorkoutSession(
        id: 's1',
        userId: 'u1',
        date: DateTime(2026, 11, 18),
        programId: 'prog1',
        weekId: 'w1',
        dayId: 'd3',
        title: 'D2 + D3',
        status: 'inProgress',
        mixedDayKeys: ['w1:d2'],
      );
      final restored = WorkoutSession.fromJson(session.toJson());
      expect(restored.mixedDayKeys, ['w1:d2']);
      expect(restored.coveredDayKeys, ['w1:d3', 'w1:d2']);
      final finished = session.copyWith(status: 'completed');
      expect(finished.mixedDayKeys, ['w1:d2']);
      expect(finished.status, 'completed');
    });
  });
}
