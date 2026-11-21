import 'package:flutter_test/flutter_test.dart';
import 'package:forge/theme.dart';

void main() {
  group('ForgeTheme.liftColorFor', () {
    test('maps the three main lifts to their colors', () {
      expect(ForgeTheme.liftColorFor('squat'), ForgeTheme.liftSquat);
      expect(ForgeTheme.liftColorFor('bench'), ForgeTheme.liftBench);
      expect(ForgeTheme.liftColorFor('deadlift'), ForgeTheme.liftDeadlift);
    });

    test('returns muted for accessories and unknown ids', () {
      expect(ForgeTheme.liftColorFor('legpress'), ForgeTheme.muted);
      expect(ForgeTheme.liftColorFor(''), ForgeTheme.muted);
    });
  });

  group('ForgeTheme.sheetAnimationStyle', () {
    test('sheets run 200ms easeOutCubic', () {
      final style = ForgeTheme.sheetAnimationStyle;
      expect(style.duration, const Duration(milliseconds: 200));
      expect(style.reverseDuration, const Duration(milliseconds: 200));
    });
  });
}
