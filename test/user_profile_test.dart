import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/user_profile.dart';

void main() {
  group('UserProfile rest durations', () {
    test('defaults are 3:00 for mains and 1:30 for accessories', () {
      const profile = UserProfile(uid: 'u1', displayName: 'Test');
      expect(profile.restMainSec, 180);
      expect(profile.restAccessorySec, 90);
      expect(profile.restSupersetSec, 180);
    });

    test('missing rest fields in stored JSON fall back to defaults', () {
      final profile = UserProfile.fromJson({
        'uid': 'u1',
        'displayName': 'Test',
      });
      expect(profile.restMainSec, 180);
      expect(profile.restAccessorySec, 90);
      expect(profile.restSupersetSec, 180);
    });

    test('custom rest durations survive a JSON round-trip', () {
      const profile = UserProfile(
        uid: 'u1',
        displayName: 'Test',
        restMainSec: 300,
        restAccessorySec: 60,
        restSupersetSec: 240,
      );
      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.restMainSec, 300);
      expect(restored.restAccessorySec, 60);
      expect(restored.restSupersetSec, 240);
    });

    test('copyWith changes one rest value and keeps the other', () {
      const profile = UserProfile(uid: 'u1', displayName: 'Test');
      final updated = profile.copyWith(restMainSec: 240);
      expect(updated.restMainSec, 240);
      expect(updated.restAccessorySec, 90);
      expect(updated.restSupersetSec, 180);
    });

    test('copyWith changes the superset rest on its own', () {
      const profile = UserProfile(uid: 'u1', displayName: 'Test');
      final updated = profile.copyWith(restSupersetSec: 150);
      expect(updated.restSupersetSec, 150);
      expect(updated.restMainSec, 180);
      expect(updated.restAccessorySec, 90);
    });
  });

  group('UserProfile rest alerts', () {
    test('all three rest toggles default to on', () {
      const profile = UserProfile(uid: 'u1', displayName: 'Test');
      expect(profile.restNotifications, isTrue);
      expect(profile.restVibrate, isTrue);
      expect(profile.restSound, isTrue);
    });

    test('missing alert fields in stored JSON fall back to on', () {
      final profile = UserProfile.fromJson({
        'uid': 'u1',
        'displayName': 'Test',
      });
      expect(profile.restNotifications, isTrue);
      expect(profile.restVibrate, isTrue);
      expect(profile.restSound, isTrue);
    });

    test('turned-off toggles survive a JSON round-trip', () {
      const profile = UserProfile(
        uid: 'u1',
        displayName: 'Test',
        restNotifications: false,
        restVibrate: false,
        restSound: true,
      );
      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.restNotifications, isFalse);
      expect(restored.restVibrate, isFalse);
      expect(restored.restSound, isTrue);
    });

    test('copyWith flips one toggle and keeps the others', () {
      const profile = UserProfile(uid: 'u1', displayName: 'Test');
      final updated = profile.copyWith(restNotifications: false);
      expect(updated.restNotifications, isFalse);
      expect(updated.restVibrate, isTrue);
      expect(updated.restSound, isTrue);
    });
  });

  group('UserProfile roles', () {
    test('defaults to training only', () {
      const profile = UserProfile(uid: 'u1', displayName: 'Test');
      expect(profile.trains, isTrue);
      expect(profile.coaches, isFalse);
    });

    test('missing role fields in stored JSON fall back to training only', () {
      final profile = UserProfile.fromJson({
        'uid': 'u1',
        'displayName': 'Test',
      });
      expect(profile.trains, isTrue);
      expect(profile.coaches, isFalse);
    });

    test('both roles survive a JSON round-trip', () {
      const profile = UserProfile(
        uid: 'u1',
        displayName: 'Test',
        trains: true,
        coaches: true,
      );
      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.trains, isTrue);
      expect(restored.coaches, isTrue);
    });

    test('copyWith can turn coaching on and off', () {
      const profile = UserProfile(uid: 'u1', displayName: 'Test');
      expect(profile.copyWith(coaches: true).coaches, isTrue);
      expect(
        profile.copyWith(coaches: true).copyWith(coaches: false).coaches,
        isFalse,
      );
    });
  });
}
