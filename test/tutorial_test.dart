import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge/screens/tutorial.dart';
import 'package:forge/services/tutorial_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TutorialService', () {
    test('the seen flag is keyed by account', () {
      expect(
        TutorialService.tutorialKey('uid-a'),
        'forge_tutorial_seen_uid-a',
      );
      expect(
        TutorialService.tutorialKey('uid-b'),
        isNot(TutorialService.tutorialKey('uid-a')),
      );
    });

    test('seen flags round-trip through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final service = TutorialService();
      expect(await service.isTutorialSeen('uid-a'), isFalse);
      await service.markTutorialSeen('uid-a');
      expect(await service.isTutorialSeen('uid-a'), isTrue);
    });

    test('one account seeing the tour does not hide it from another',
        () async {
      // The Nov 19 bug: the flag was per phone, so a second account
      // on the same phone never saw the tour.
      SharedPreferences.setMockInitialValues({});
      final service = TutorialService();
      await service.markTutorialSeen('uid-a');
      expect(await service.isTutorialSeen('uid-a'), isTrue);
      expect(await service.isTutorialSeen('uid-b'), isFalse);
    });
  });

  group('TutorialScreen', () {
    /// Pumps a button that opens the tour for [uid], then opens it.
    Future<void> openTour(WidgetTester tester, String uid) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => TutorialScreen(uid: uid),
                  ),
                );
              },
              child: const Text('Open tour'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open tour'));
      await tester.pumpAndSettle();
      expect(find.text('This is Forge'), findsOneWidget);
    }

    testWidgets('Next walks eight pages; Start training finishes it',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await openTour(tester, 'uid-a');
      const bodies = [
        'Your workout for the day lives here. Start it, move it to '
            'another day, or mix two days into one.',
        'Your program lives here. Tap a day to see its exercises, '
            'tap a weight to change it — and import your spreadsheet '
            'from the button up top.',
        'Log sets as you go. Tap the weight or reps to type them in '
            '— the rest timer starts itself when a set is done. You '
            'get here from the + in the middle.',
        'Every workout, kept. Tap one to review it — every set, and '
            'any video you attached.',
        'Your best lifts, estimated one-rep maxes and weekly volume.',
        'Pair athletes with your QR code or 6-letter code. Tap a '
            'client to review their workouts or send them a program.',
        'Rest timers, sheet write-back and your alerts. Open it from '
            'the gear on Today.',
      ];
      for (final body in bodies) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text(body), findsOneWidget);
      }
      expect(find.text('Start training'), findsOneWidget);
      await tester.tap(find.text('Start training'));
      await tester.pumpAndSettle();
      expect(find.text('This is Forge'), findsNothing);
      expect(await TutorialService().isTutorialSeen('uid-a'), isTrue);
      // The other account is untouched.
      expect(await TutorialService().isTutorialSeen('uid-b'), isFalse);
    });

    testWidgets('Skip ends the tour and marks it seen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await openTour(tester, 'uid-a');
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('This is Forge'), findsNothing);
      expect(await TutorialService().isTutorialSeen('uid-a'), isTrue);
    });
  });
}
