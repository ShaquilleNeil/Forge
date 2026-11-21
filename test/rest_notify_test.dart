import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/user_profile.dart';
import 'package:forge/services/rest_notify_service.dart';

void main() {
  group('RestNotifyService.format', () {
    test('formats the runner clock: minutes:seconds', () {
      expect(RestNotifyService.format(180), '3:00');
      expect(RestNotifyService.format(90), '1:30');
      expect(RestNotifyService.format(65), '1:05');
      expect(RestNotifyService.format(5), '0:05');
      expect(RestNotifyService.format(0), '0:00');
    });
  });

  group('RestNotifyService notification copy', () {
    test('ongoing notification names the exercise and the next set', () {
      expect(RestNotifyService.restBody(2), 'Rest — next: Set 2');
    });

    test('rest-done title names the set and the exercise', () {
      expect(
        RestNotifyService.doneTitle('Squat', 2),
        'Rest over — Set 2 of Squat',
      );
    });

    test('rest-done body tells the lifter to go', () {
      expect(
        RestNotifyService.doneBody(),
        'Your rest is over. Next set.',
      );
    });

    test('foreground-service text is the rest body plus countdown', () {
      expect(
        RestNotifyService.serviceText(2, 154),
        'Rest — next: Set 2 · 2:34',
      );
      expect(
        RestNotifyService.serviceText(1, 5),
        'Rest — next: Set 1 · 0:05',
      );
    });

    test('foreground-service text never goes below 0:00', () {
      expect(
        RestNotifyService.serviceText(3, -10),
        'Rest — next: Set 3 · 0:00',
      );
    });

    test('vibration pattern is the spec pattern', () {
      expect(
        RestNotifyService.doneVibrationPattern,
        [0, 400, 200, 400, 200, 600],
      );
    });
  });

  group('RestNotifyPrefs', () {
    test('defaults are all on', () {
      const prefs = RestNotifyPrefs();
      expect(prefs.notifications, isTrue);
      expect(prefs.vibrate, isTrue);
      expect(prefs.sound, isTrue);
    });

    test('round-trips through JSON', () {
      const prefs = RestNotifyPrefs(
        notifications: false,
        vibrate: false,
        sound: true,
      );
      final restored = RestNotifyPrefs.fromJson(prefs.toJson());
      expect(restored.notifications, isFalse);
      expect(restored.vibrate, isFalse);
      expect(restored.sound, isTrue);
    });

    test('missing fields in stored JSON fall back to on', () {
      final prefs = RestNotifyPrefs.fromJson({});
      expect(prefs.notifications, isTrue);
      expect(prefs.vibrate, isTrue);
      expect(prefs.sound, isTrue);
    });

    test('builds from the profile toggles', () {
      const profile = UserProfile(
        uid: 'u1',
        displayName: 'Test',
        restNotifications: false,
        restVibrate: true,
        restSound: false,
      );
      final prefs = RestNotifyPrefs.fromProfile(profile);
      expect(prefs.notifications, isFalse);
      expect(prefs.vibrate, isTrue);
      expect(prefs.sound, isFalse);
    });
  });
}
