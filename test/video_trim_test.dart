import 'package:flutter_test/flutter_test.dart';
import 'package:forge/services/video_trim_service.dart';

void main() {
  group('formatMmSs', () {
    test('zero', () {
      expect(formatMmSs(0), '0:00');
    });

    test('under a minute', () {
      expect(formatMmSs(45), '0:45');
    });

    test('over a minute', () {
      expect(formatMmSs(75), '1:15');
    });

    test('five minutes', () {
      expect(formatMmSs(300), '5:00');
    });

    test('rounds to the nearest second', () {
      expect(formatMmSs(74.6), '1:15');
    });
  });

  group('isTrimWithinLimit', () {
    test('exactly at the limit fits', () {
      expect(isTrimWithinLimit(0, 300, 300), isTrue);
    });

    test('one second over does not fit', () {
      expect(isTrimWithinLimit(0, 301, 300), isFalse);
    });

    test('a mid-clip cut fits', () {
      expect(isTrimWithinLimit(10, 290, 300), isTrue);
    });
  });
}
