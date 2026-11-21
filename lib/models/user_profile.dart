import 'package:cloud_firestore/cloud_firestore.dart';

/// User profile. Kilos are the stored truth; [units] only changes display.
class UserProfile {
  final String uid;
  final String displayName;
  final String sex; // 'male' | 'female'
  final DateTime? dob;
  final String country;
  final String homeGym;
  final String units; // 'kg' | 'lb'
  final double barWeightKg;
  final String plateSet; // 'calibrated' | 'gym'
  final double? bodyweightKg;
  final double? weightClassKg;
  final Map<String, double> mainLifts; // squat / bench / deadlift -> 1RM kg
  /// When true, finishing a workout writes actuals back to the sheet
  /// the active program was imported from. Off by default.
  final bool writeBackToSheet;

  /// Rest between sets, in seconds. Mains default to 3:00, accessories
  /// to 1:30, supersets to 3:00 — all editable in Settings. A superset
  /// rest starts after the round (both exercises done), not between
  /// the two exercises.
  final int restMainSec;
  final int restAccessorySec;
  final int restSupersetSec;

  /// Rest-timer alerts, all on by default (Settings → Rest timer).
  /// restNotifications: the countdown + "rest over" alert in the
  /// notification shade (and a Live Activity on iOS). restVibrate /
  /// restSound: buzz and sound when the rest ends. Turning the
  /// notifications off leaves the in-app timer and haptics.
  final bool restNotifications;
  final bool restVibrate;
  final bool restSound;

  /// How the user uses Forge — one or both. A lifter trains, a coach
  /// coaches; Alex does both. At least one is always on.
  final bool trains;
  final bool coaches;

  const UserProfile({
    required this.uid,
    required this.displayName,
    this.sex = 'male',
    this.dob,
    this.country = '',
    this.homeGym = '',
    this.units = 'kg',
    this.barWeightKg = 20.0,
    this.plateSet = 'calibrated',
    this.bodyweightKg,
    this.weightClassKg,
    this.mainLifts = const {},
    this.writeBackToSheet = false,
    this.restMainSec = 180,
    this.restAccessorySec = 90,
    this.restSupersetSec = 180,
    this.restNotifications = true,
    this.restVibrate = true,
    this.restSound = true,
    this.trains = true,
    this.coaches = false,
  });

  double get totalKg =>
      (mainLifts['squat'] ?? 0) +
      (mainLifts['bench'] ?? 0) +
      (mainLifts['deadlift'] ?? 0);

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'sex': sex,
        'dob': dob == null ? null : Timestamp.fromDate(dob!),
        'country': country,
        'homeGym': homeGym,
        'units': units,
        'barWeightKg': barWeightKg,
        'plateSet': plateSet,
        'bodyweightKg': bodyweightKg,
        'weightClassKg': weightClassKg,
        'mainLifts': mainLifts,
        'writeBackToSheet': writeBackToSheet,
        'restMainSec': restMainSec,
        'restAccessorySec': restAccessorySec,
        'restSupersetSec': restSupersetSec,
        'restNotifications': restNotifications,
        'restVibrate': restVibrate,
        'restSound': restSound,
        'trains': trains,
        'coaches': coaches,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final dobRaw = json['dob'];
    DateTime? dob;
    if (dobRaw is Timestamp) {
      dob = dobRaw.toDate();
    } else if (dobRaw is String) {
      dob = DateTime.tryParse(dobRaw);
    }
    final liftsRaw = json['mainLifts'] as Map<String, dynamic>? ?? {};
    return UserProfile(
      uid: json['uid'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      sex: json['sex'] as String? ?? 'male',
      dob: dob,
      country: json['country'] as String? ?? '',
      homeGym: json['homeGym'] as String? ?? '',
      units: json['units'] as String? ?? 'kg',
      barWeightKg: (json['barWeightKg'] as num?)?.toDouble() ?? 20.0,
      plateSet: json['plateSet'] as String? ?? 'calibrated',
      bodyweightKg: (json['bodyweightKg'] as num?)?.toDouble(),
      weightClassKg: (json['weightClassKg'] as num?)?.toDouble(),
      mainLifts: liftsRaw.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      writeBackToSheet: json['writeBackToSheet'] as bool? ?? false,
      restMainSec: (json['restMainSec'] as num?)?.toInt() ?? 180,
      restAccessorySec: (json['restAccessorySec'] as num?)?.toInt() ?? 90,
      restSupersetSec: (json['restSupersetSec'] as num?)?.toInt() ?? 180,
      restNotifications: (json['restNotifications'] as bool?) ?? true,
      restVibrate: (json['restVibrate'] as bool?) ?? true,
      restSound: (json['restSound'] as bool?) ?? true,
      trains: (json['trains'] as bool?) ?? true,
      coaches: (json['coaches'] as bool?) ?? false,
    );
  }

  UserProfile copyWith({
    String? displayName,
    String? sex,
    DateTime? dob,
    String? country,
    String? homeGym,
    String? units,
    double? barWeightKg,
    String? plateSet,
    double? bodyweightKg,
    double? weightClassKg,
    Map<String, double>? mainLifts,
    bool? writeBackToSheet,
    int? restMainSec,
    int? restAccessorySec,
    int? restSupersetSec,
    bool? restNotifications,
    bool? restVibrate,
    bool? restSound,
    bool? trains,
    bool? coaches,
  }) =>
      UserProfile(
        uid: uid,
        displayName: displayName ?? this.displayName,
        sex: sex ?? this.sex,
        dob: dob ?? this.dob,
        country: country ?? this.country,
        homeGym: homeGym ?? this.homeGym,
        units: units ?? this.units,
        barWeightKg: barWeightKg ?? this.barWeightKg,
        plateSet: plateSet ?? this.plateSet,
        bodyweightKg: bodyweightKg ?? this.bodyweightKg,
        weightClassKg: weightClassKg ?? this.weightClassKg,
        mainLifts: mainLifts ?? this.mainLifts,
        writeBackToSheet: writeBackToSheet ?? this.writeBackToSheet,
        restMainSec: restMainSec ?? this.restMainSec,
        restAccessorySec: restAccessorySec ?? this.restAccessorySec,
        restSupersetSec: restSupersetSec ?? this.restSupersetSec,
        restNotifications:
            restNotifications ?? this.restNotifications,
        restVibrate: restVibrate ?? this.restVibrate,
        restSound: restSound ?? this.restSound,
        trains: trains ?? this.trains,
        coaches: coaches ?? this.coaches,
      );
}
