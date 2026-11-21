import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/user_profile.dart';
import 'package:forge/services/strength_math.dart';

// A8/A9: editing the profile from Settings used to build a brand-new
// UserProfile(...) with only the form fields, and saveProfile did a
// plain set() — so rest timers, write-back and rest alerts silently
// reset to defaults on every edit, and two rapid Settings toggles
// could clobber each other. The fix is twofold: the form saves from
// _existing?.copyWith(...) (this file) and saveProfile merges
// (SetOptions(merge: true), verified by inspection — a merge write
// needs a live Firestore, so it is not unit-testable here).
void main() {
  const existing = UserProfile(
    uid: 'u1',
    displayName: 'Test',
    units: 'lb',
    writeBackToSheet: true,
    restMainSec: 300,
    restAccessorySec: 60,
    restSupersetSec: 240,
    restNotifications: false,
    restVibrate: false,
    restSound: true,
  );

  group('profile edit preserves settings-owned fields (A8)', () {
    test('copyWith with only form fields keeps rest timers + write-back',
        () {
      // What profile_setup._save does: copy the loaded profile and
      // change only what the form owns.
      final saved = existing.copyWith(
        displayName: 'New Name',
        units: 'kg',
        bodyweightKg: 83,
        mainLifts: const {'squat': 180, 'bench': 120, 'deadlift': 200},
      );
      expect(saved.displayName, 'New Name');
      expect(saved.units, 'kg');
      expect(saved.bodyweightKg, 83);
      // Settings-owned fields: untouched by the form save.
      expect(saved.writeBackToSheet, isTrue);
      expect(saved.restMainSec, 300);
      expect(saved.restAccessorySec, 60);
      expect(saved.restSupersetSec, 240);
      expect(saved.restNotifications, isFalse);
      expect(saved.restVibrate, isFalse);
      expect(saved.restSound, isTrue);
    });

    test('a Settings toggle keeps the other settings (A9)', () {
      // What settings.dart does: copyWith one field on the streamed
      // profile. With merge in saveProfile, two rapid toggles each
      // write only their own field.
      final afterWriteBackOff = existing.copyWith(writeBackToSheet: false);
      expect(afterWriteBackOff.writeBackToSheet, isFalse);
      expect(afterWriteBackOff.restMainSec, 300);
      expect(afterWriteBackOff.restAccessorySec, 60);

      final afterRestChange =
          afterWriteBackOff.copyWith(restMainSec: 240);
      expect(afterRestChange.restMainSec, 240);
      expect(afterRestChange.writeBackToSheet, isFalse);
      expect(afterRestChange.restAccessorySec, 60);
      expect(afterRestChange.restSupersetSec, 240);
    });

    test('custom rest timers + write-back survive a JSON round-trip', () {
      final restored = UserProfile.fromJson(existing.toJson());
      expect(restored.writeBackToSheet, isTrue);
      expect(restored.restMainSec, 300);
      expect(restored.restAccessorySec, 60);
      expect(restored.restSupersetSec, 240);
      expect(restored.restNotifications, isFalse);
      expect(restored.restVibrate, isFalse);
    });
  });

  group('formatWeight (A19 shared helper)', () {
    test('kg stays kg, whole numbers print without decimals', () {
      expect(formatWeight(83, 'kg'), '83 kg');
      expect(formatWeight(132.5, 'kg'), '132.5 kg');
      expect(formatWeight(0, 'kg'), '0 kg');
    });

    test('lb converts from stored kg and labels lb', () {
      expect(formatWeight(83, 'lb'), '183.0 lb');
      expect(formatWeight(100, 'lb'), '220.5 lb');
      expect(formatWeight(20, 'lb'), '44.1 lb');
      expect(formatWeight(15, 'lb'), '33.1 lb');
    });

    test('unknown units fall back to kg', () {
      expect(formatWeight(83, ''), '83 kg');
    });
  });
}
