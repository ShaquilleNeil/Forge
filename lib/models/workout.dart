/// One logged set inside a workout session.
class SessionSet {
  final String exerciseId;
  final String name;
  final int setIndex; // 0-based within the exercise
  final double weightKg;
  final int reps;
  final double? rpe;
  final String? barSpeed; // Fast | Normal | Slow | Grind
  final bool completed;
  final bool skipped; // deliberately not done this session
  final String? videoPath; // local path, before upload
  final String? videoUrl; // Storage download URL, after upload

  /// The program day this set came from (a [ProgramDay] id). Set when
  /// the runner builds the set from a day; null for free workouts and
  /// for sessions saved before moves existed. A mixed session tags
  /// every set with its own day, so the sheet write-back can route
  /// each day's sets to that day's rows — and so the same exercise in
  /// two mixed days stays two separate blocks in the runner.
  final String? dayId;

  /// The runner's grouping key: the day + the exercise. Two days
  /// sharing an exercise (bench on day 2 and day 3) get different
  /// keys, so their sets never merge into one block.
  String get blockKey => blockKeyFor(dayId, exerciseId);

  /// The grouping key for a day + exercise pair — the same key
  /// [blockKey] computes for a set. Null day means a free workout,
  /// where the exercise alone is the key.
  static String blockKeyFor(String? dayId, String exerciseId) =>
      dayId == null ? exerciseId : '$dayId|$exerciseId';

  const SessionSet({
    required this.exerciseId,
    required this.name,
    required this.setIndex,
    required this.weightKg,
    required this.reps,
    this.rpe,
    this.barSpeed,
    this.completed = false,
    this.skipped = false,
    this.videoPath,
    this.videoUrl,
    this.dayId,
  });

  double get volumeKg => weightKg * reps;

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'name': name,
        'setIndex': setIndex,
        'weightKg': weightKg,
        'reps': reps,
        'rpe': rpe,
        'barSpeed': barSpeed,
        'completed': completed,
        'skipped': skipped,
        'videoPath': videoPath,
        'videoUrl': videoUrl,
        'dayId': dayId,
      };

  factory SessionSet.fromJson(Map<String, dynamic> json) => SessionSet(
        exerciseId: json['exerciseId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        setIndex: (json['setIndex'] as num?)?.toInt() ?? 0,
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
        reps: (json['reps'] as num?)?.toInt() ?? 0,
        rpe: (json['rpe'] as num?)?.toDouble(),
        barSpeed: json['barSpeed'] as String?,
        completed: json['completed'] as bool? ?? false,
        skipped: json['skipped'] as bool? ?? false,
        videoPath: json['videoPath'] as String?,
        videoUrl: json['videoUrl'] as String?,
        dayId: json['dayId'] as String?,
      );

  SessionSet copyWith({
    double? weightKg,
    int? reps,
    double? rpe,
    String? barSpeed,
    bool? completed,
    bool? skipped,
    String? videoPath,
    String? videoUrl,
    // copyWith cannot clear a nullable field by passing null (null
    // means "keep"), so removing a video uses this flag instead.
    bool clearVideo = false,
  }) =>
      SessionSet(
        exerciseId: exerciseId,
        name: name,
        setIndex: setIndex,
        weightKg: weightKg ?? this.weightKg,
        reps: reps ?? this.reps,
        rpe: rpe ?? this.rpe,
        barSpeed: barSpeed ?? this.barSpeed,
        completed: completed ?? this.completed,
        skipped: skipped ?? this.skipped,
        videoPath: clearVideo ? null : (videoPath ?? this.videoPath),
        videoUrl: clearVideo ? null : (videoUrl ?? this.videoUrl),
        dayId: dayId,
      );
}

/// A workout session. [status] is 'inProgress' or 'completed'.
class WorkoutSession {
  final String id;
  final String userId;
  final DateTime date;
  final String? programId;
  final String? weekId;
  final String? dayId;
  final String title;
  final int durationSec;
  final String notes;
  final double totalVolumeKg;
  final String status;
  final List<SessionSet> sets;

  /// When the current rest ends. Phase 4's mini workout bar and Phase 6's
  /// rest notifications read it; the runner sets it when a rest starts.
  /// Null when not resting. Persisted so it survives backgrounding and
  /// app restart.
  final DateTime? restEndsAt;

  /// The rest this countdown started with, in seconds — the draining
  /// bar's full length. +15s extends it too, so the bar never jumps.
  /// Null when not resting.
  final int? restTotalSec;

  /// Day keys ("weekId:dayId") of the additional program days this
  /// session covers, beyond the primary [dayId]. A mixed session —
  /// two days done as one long workout — lists the moved-in day(s)
  /// here. Empty for single-day sessions. The days go back to their
  /// own slots when the session finishes (the move records are
  /// deleted then); these keys stay on the session so history and the
  /// sheet write-back keep attributing each set to its own day.
  final List<String> mixedDayKeys;

  /// Cross-day superset links, picked in the runner during a mixed
  /// workout: blockKey ("dayId|exerciseId") -> badge ("S1", "S2",
  /// "T1", ...). Two exercises sharing a link letter alternate set
  /// by set even though they come from different days, and rest on
  /// the superset timer after each round. A link wins over the
  /// exercise's same-day sheet superset for this run — the sheet
  /// partner is
  /// left standalone. Persisted with the session, so a crash keeps
  /// the links.
  final Map<String, String> crossDaySupersets;

  /// Whether this session covers a program day — as its primary day,
  /// or as one of its mixed-in days.
  bool coversDay(String programId, String weekId, String dayId) {
    if (this.programId != programId) return false;
    if (this.weekId == weekId && this.dayId == dayId) return true;
    return mixedDayKeys.contains('$weekId:$dayId');
  }

  /// Every program day this session covers, as "weekId:dayId" keys.
  List<String> get coveredDayKeys => [
        if (weekId != null && dayId != null) '$weekId:$dayId',
        ...mixedDayKeys,
      ];

  const WorkoutSession({
    required this.id,
    required this.userId,
    required this.date,
    this.programId,
    this.weekId,
    this.dayId,
    required this.title,
    this.durationSec = 0,
    this.notes = '',
    this.totalVolumeKg = 0,
    this.status = 'inProgress',
    this.sets = const [],
    this.restEndsAt,
    this.restTotalSec,
    this.mixedDayKeys = const [],
    this.crossDaySupersets = const {},
  });

  double get computedVolumeKg => sets
      .where((s) => s.completed)
      .fold(0.0, (sum, s) => sum + s.volumeKg);

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'date': date.toIso8601String(),
        'programId': programId,
        'weekId': weekId,
        'dayId': dayId,
        'title': title,
        'durationSec': durationSec,
        'notes': notes,
        'totalVolumeKg': totalVolumeKg,
        'status': status,
        'sets': sets.map((s) => s.toJson()).toList(),
        'restEndsAt': restEndsAt?.toIso8601String(),
        'restTotalSec': restTotalSec,
        'mixedDayKeys': mixedDayKeys,
        'crossDaySupersets': crossDaySupersets,
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) =>
      WorkoutSession(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        programId: json['programId'] as String?,
        weekId: json['weekId'] as String?,
        dayId: json['dayId'] as String?,
        title: json['title'] as String? ?? '',
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        notes: json['notes'] as String? ?? '',
        totalVolumeKg: (json['totalVolumeKg'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? 'inProgress',
        sets: (json['sets'] as List<dynamic>? ?? [])
            .map((s) => SessionSet.fromJson(s as Map<String, dynamic>))
            .toList(),
        restEndsAt: DateTime.tryParse(
          json['restEndsAt'] as String? ?? '',
        ),
        restTotalSec: (json['restTotalSec'] as num?)?.toInt(),
        mixedDayKeys: (json['mixedDayKeys'] as List<dynamic>? ?? [])
            .map((k) => k.toString())
            .toList(),
        crossDaySupersets:
            (json['crossDaySupersets'] as Map<String, dynamic>? ?? {})
                .map((k, v) => MapEntry(k.toString(), v.toString())),
      );

  WorkoutSession copyWith({
    DateTime? date,
    String? title,
    int? durationSec,
    String? notes,
    double? totalVolumeKg,
    String? status,
    List<SessionSet>? sets,
    DateTime? restEndsAt,
    int? restTotalSec,
    Map<String, String>? crossDaySupersets,
    // copyWith cannot clear a nullable field by passing null (null means
    // "keep"), so ending a rest uses this flag instead.
    bool clearRest = false,
  }) =>
      WorkoutSession(
        id: id,
        userId: userId,
        date: date ?? this.date,
        programId: programId,
        weekId: weekId,
        dayId: dayId,
        title: title ?? this.title,
        durationSec: durationSec ?? this.durationSec,
        notes: notes ?? this.notes,
        totalVolumeKg: totalVolumeKg ?? this.totalVolumeKg,
        status: status ?? this.status,
        sets: sets ?? this.sets,
        restEndsAt: clearRest ? null : (restEndsAt ?? this.restEndsAt),
        restTotalSec:
            clearRest ? null : (restTotalSec ?? this.restTotalSec),
        mixedDayKeys: mixedDayKeys,
        crossDaySupersets: crossDaySupersets ?? this.crossDaySupersets,
      );
}
