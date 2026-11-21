import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/exercise.dart';

void main() {
  group('Exercise.nameIsMain', () {
    test('competition lifts and their variations are mains', () {
      expect(Exercise.nameIsMain('Squat'), isTrue);
      expect(Exercise.nameIsMain('Squat, beltless'), isTrue);
      expect(Exercise.nameIsMain('Belt squat, narrow and upright'), isTrue);
      expect(Exercise.nameIsMain('Bench Press'), isTrue);
      expect(Exercise.nameIsMain('Comp bench'), isTrue);
      expect(Exercise.nameIsMain('Close-grip bench'), isTrue);
      expect(Exercise.nameIsMain('Deadlift'), isTrue);
      expect(Exercise.nameIsMain('Paused deadlift'), isTrue);
    });

    test('accessories are not mains', () {
      expect(Exercise.nameIsMain('Seated/lying leg curl'), isFalse);
      expect(Exercise.nameIsMain('Leg extension'), isFalse);
      expect(Exercise.nameIsMain('Rope pushdown'), isFalse);
      expect(Exercise.nameIsMain('Lateral raise (machine)'), isFalse);
      expect(Exercise.nameIsMain('Ab wheel'), isFalse);
      expect(Exercise.nameIsMain('Overhead Press'), isFalse);
      expect(Exercise.nameIsMain('Barbell Row'), isFalse);
    });

    test('Romanian and stiff-leg deadlifts stay accessories', () {
      expect(Exercise.nameIsMain('Romanian Deadlift'), isFalse);
      expect(Exercise.nameIsMain('RDL'), isFalse);
      expect(Exercise.nameIsMain('Stiff-leg deadlift'), isFalse);
    });
  });
}
