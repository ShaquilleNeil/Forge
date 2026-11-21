import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge/screens/privacy_policy.dart';

void main() {
  group('PrivacyPolicyScreen', () {
    testWidgets('shows every section, the date and the contact',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PrivacyPolicyScreen()),
      );
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Effective November 19, 2026'), findsOneWidget);
      // The list builds lazily — scroll each section into view
      // before asserting on it.
      for (final section in kPrivacySections) {
        await tester.scrollUntilVisible(find.text(section.title), 200);
        expect(find.text(section.title), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.textContaining('contact@example.com'),
        200,
      );
      expect(find.textContaining('contact@example.com'),
          findsOneWidget);
      expect(find.textContaining('Delete account'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('your-firebase-project-id.web.app/privacy.html'),
        200,
      );
      expect(
        find.textContaining('your-firebase-project-id.web.app/privacy.html'),
        findsOneWidget,
      );
    });

    test('the policy has no empty section', () {
      expect(kPrivacySections, isNotEmpty);
      for (final section in kPrivacySections) {
        expect(section.title, isNotEmpty);
        expect(section.body, isNotEmpty);
      }
    });
  });
}
