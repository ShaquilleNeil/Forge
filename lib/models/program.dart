/// A training program: weeks -> days -> prescribed exercises.
/// Weights are kg (truth); [targetWeightKg] or [percentOf1rm] may be null
/// when the prescription is reps/RPE only.
class ProgramExercise {
  final String exerciseId;
  final String name;
  final int sets;
  final int? repsMin;
  final int? repsMax;
  final String? repsText; // the reps part only, e.g. "10-12" — never "3 x 10-12"

  /// The reps label as shown next to the sets count ("<sets> × <this>").
  /// Imports before Nov 16 stored the whole sheet cell ("2 x 8-10") in
  /// [repsText], so a leading "<sets> x " prefix is stripped when it
  /// matches [sets] — those already-imported programs display correctly
  /// without a re-import.
  String? get displayRepsText {
    final text = repsText?.trim();
    if (text == null || text.isEmpty) return text;
    final match = RegExp(
      '^$sets\\s*[x×]\\s*(.+)\$',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1)?.trim() ?? text;
  }
  final double? targetWeightKg;
  final double? percentOf1rm;
  final String? targetRpe;
  final String notes;
  final String? supersetGroup;

  const ProgramExercise({
    required this.exerciseId,
    required this.name,
    this.sets = 3,
    this.repsMin,
    this.repsMax,
    this.repsText,
    this.targetWeightKg,
    this.percentOf1rm,
    this.targetRpe,
    this.notes = '',
    this.supersetGroup,
  });

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'name': name,
        'sets': sets,
        'repsMin': repsMin,
        'repsMax': repsMax,
        'repsText': repsText,
        'targetWeightKg': targetWeightKg,
        'percentOf1rm': percentOf1rm,
        'targetRpe': targetRpe,
        'notes': notes,
        'supersetGroup': supersetGroup,
      };

  factory ProgramExercise.fromJson(Map<String, dynamic> json) =>
      ProgramExercise(
        exerciseId: json['exerciseId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        sets: (json['sets'] as num?)?.toInt() ?? 3,
        repsMin: (json['repsMin'] as num?)?.toInt(),
        repsMax: (json['repsMax'] as num?)?.toInt(),
        repsText: json['repsText'] as String?,
        targetWeightKg: (json['targetWeightKg'] as num?)?.toDouble(),
        percentOf1rm: (json['percentOf1rm'] as num?)?.toDouble(),
        targetRpe: json['targetRpe'] as String?,
        notes: json['notes'] as String? ?? '',
        supersetGroup: json['supersetGroup'] as String?,
      );

  ProgramExercise copyWith({
    String? exerciseId,
    String? name,
    int? sets,
    int? repsMin,
    int? repsMax,
    String? repsText,
    double? targetWeightKg,
    double? percentOf1rm,
    String? targetRpe,
    String? notes,
    String? supersetGroup,
  }) =>
      ProgramExercise(
        exerciseId: exerciseId ?? this.exerciseId,
        name: name ?? this.name,
        sets: sets ?? this.sets,
        repsMin: repsMin ?? this.repsMin,
        repsMax: repsMax ?? this.repsMax,
        repsText: repsText ?? this.repsText,
        targetWeightKg: targetWeightKg ?? this.targetWeightKg,
        percentOf1rm: percentOf1rm ?? this.percentOf1rm,
        targetRpe: targetRpe ?? this.targetRpe,
        notes: notes ?? this.notes,
        supersetGroup: supersetGroup ?? this.supersetGroup,
      );
}

class ProgramDay {
  final String id;
  final String title; // e.g. "D1 — Squat + Bench"
  final int dayIndex;
  final List<ProgramExercise> exercises;

  const ProgramDay({
    required this.id,
    required this.title,
    this.dayIndex = 0,
    this.exercises = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dayIndex': dayIndex,
        'exercises': exercises.map((e) => e.toJson()).toList(),
      };

  factory ProgramDay.fromJson(Map<String, dynamic> json) => ProgramDay(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        dayIndex: (json['dayIndex'] as num?)?.toInt() ?? 0,
        exercises: (json['exercises'] as List<dynamic>? ?? [])
            .map((e) => ProgramExercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  ProgramDay copyWith({
    String? id,
    String? title,
    int? dayIndex,
    List<ProgramExercise>? exercises,
  }) =>
      ProgramDay(
        id: id ?? this.id,
        title: title ?? this.title,
        dayIndex: dayIndex ?? this.dayIndex,
        exercises: exercises ?? this.exercises,
      );

  static const _monthByName = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// Parses the calendar date from a day title such as
  /// "Mon Oct 19 · D1 · Squat + bench volume". Titles carry month +
  /// day only, so [year] fills in the year (the program's creation
  /// year — his block is Oct–Dec 2026). Null when the title carries
  /// no date (e.g. a blank-program day).
  static DateTime? parseDate(String title, int year) {
    final match = RegExp(
      r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+([A-Za-z]{3})\s+(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(title.trim());
    if (match == null) return null;
    final month = _monthByName[match.group(1)!.toLowerCase()];
    final day = int.tryParse(match.group(2)!);
    if (month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}

class ProgramWeek {
  final String id;
  final String title; // e.g. "Week 1 — Deload"
  final int weekIndex;
  final List<ProgramDay> days;

  const ProgramWeek({
    required this.id,
    required this.title,
    this.weekIndex = 0,
    this.days = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'weekIndex': weekIndex,
        'days': days.map((d) => d.toJson()).toList(),
      };

  factory ProgramWeek.fromJson(Map<String, dynamic> json) => ProgramWeek(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        weekIndex: (json['weekIndex'] as num?)?.toInt() ?? 0,
        days: (json['days'] as List<dynamic>? ?? [])
            .map((d) => ProgramDay.fromJson(d as Map<String, dynamic>))
            .toList(),
      );

  ProgramWeek copyWith({
    String? id,
    String? title,
    int? weekIndex,
    List<ProgramDay>? days,
  }) =>
      ProgramWeek(
        id: id ?? this.id,
        title: title ?? this.title,
        weekIndex: weekIndex ?? this.weekIndex,
        days: days ?? this.days,
      );
}

/// One lift's attempt plan for a meet: opener, 2nd, 3rd range, last warm-up.
class MeetAttempt {
  final String lift; // 'squat' | 'bench' | 'deadlift'
  final double? projectedMaxKg;
  final double? openerKg;
  final double? secondKg;
  final double? thirdLowKg;
  final double? thirdHighKg;
  final double? lastWarmUpKg;

  const MeetAttempt({
    required this.lift,
    this.projectedMaxKg,
    this.openerKg,
    this.secondKg,
    this.thirdLowKg,
    this.thirdHighKg,
    this.lastWarmUpKg,
  });

  Map<String, dynamic> toJson() => {
        'lift': lift,
        'projectedMaxKg': projectedMaxKg,
        'openerKg': openerKg,
        'secondKg': secondKg,
        'thirdLowKg': thirdLowKg,
        'thirdHighKg': thirdHighKg,
        'lastWarmUpKg': lastWarmUpKg,
      };

  factory MeetAttempt.fromJson(Map<String, dynamic> json) => MeetAttempt(
        lift: json['lift'] as String? ?? '',
        projectedMaxKg: (json['projectedMaxKg'] as num?)?.toDouble(),
        openerKg: (json['openerKg'] as num?)?.toDouble(),
        secondKg: (json['secondKg'] as num?)?.toDouble(),
        thirdLowKg: (json['thirdLowKg'] as num?)?.toDouble(),
        thirdHighKg: (json['thirdHighKg'] as num?)?.toDouble(),
        lastWarmUpKg: (json['lastWarmUpKg'] as num?)?.toDouble(),
      );
}

/// A meet plan: the meet date plus one attempt row per lift.
class MeetPlan {
  final DateTime? date;
  final List<MeetAttempt> attempts;

  const MeetPlan({
    this.date,
    this.attempts = const [],
  });

  Map<String, dynamic> toJson() => {
        'date': date?.toIso8601String(),
        'attempts': attempts.map((a) => a.toJson()).toList(),
      };

  factory MeetPlan.fromJson(Map<String, dynamic> json) => MeetPlan(
        date: json['date'] == null
            ? null
            : DateTime.tryParse(json['date'] as String? ?? ''),
        attempts: (json['attempts'] as List<dynamic>? ?? [])
            .map((a) => MeetAttempt.fromJson(a as Map<String, dynamic>))
            .toList(),
      );
}

class Program {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final List<ProgramWeek> weeks;
  final MeetPlan? meetPlan;
  final bool isActive;
  final DateTime createdAt;
  /// Google Sheet id this program was imported from (null when the
  /// program was built in-app). Write-back targets this sheet only.
  final String? sourceSpreadsheetId;

  /// The sheet's modifiedTime (RFC 3339) the app last knew about: set
  /// at import, refreshed after an app -> sheet write, or when the user
  /// dismisses the "sheet changed" prompt. The two-way sync check
  /// compares the sheet's current modifiedTime against this value.
  final String? sourceModifiedTime;

  /// Set when a coach sent this program to the client. A sent program
  /// becomes the client's active one right away.
  final String? fromCoachUid;
  final String? fromCoachName;

  /// Moved days: day key ("weekId:dayId") -> the date the day was
  /// moved to ("yyyy-MM-dd"). The weeks and days themselves never
  /// move — a move is a one-time scheduling exception. When a session
  /// covering a moved day finishes, its move record is deleted, so
  /// the day goes back to its own slot, marked done by that session.
  /// Empty for programs with no moves.
  final Map<String, String> dayMoves;

  /// Client uids this coaching program was sent to (coach programs
  /// only; training programs never carry it). The coach list shows
  /// "Sent to N clients" from this — a sent program stays listed
  /// here even after the client unlinks.
  final List<String> sentToClientIds;

  const Program({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    this.weeks = const [],
    this.meetPlan,
    this.isActive = false,
    required this.createdAt,
    this.sourceSpreadsheetId,
    this.sourceModifiedTime,
    this.fromCoachUid,
    this.fromCoachName,
    this.dayMoves = const {},
    this.sentToClientIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'name': name,
        'description': description,
        'weeks': weeks.map((w) => w.toJson()).toList(),
        'meetPlan': meetPlan?.toJson(),
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
        'sourceSpreadsheetId': sourceSpreadsheetId,
        'sourceModifiedTime': sourceModifiedTime,
        'fromCoachUid': fromCoachUid,
        'fromCoachName': fromCoachName,
        'dayMoves': dayMoves,
        'sentToClientIds': sentToClientIds,
      };

  factory Program.fromJson(Map<String, dynamic> json) => Program(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        weeks: (json['weeks'] as List<dynamic>? ?? [])
            .map((w) => ProgramWeek.fromJson(w as Map<String, dynamic>))
            .toList(),
        meetPlan: json['meetPlan'] == null
            ? null
            : MeetPlan.fromJson(json['meetPlan'] as Map<String, dynamic>),
        isActive: json['isActive'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        sourceSpreadsheetId: json['sourceSpreadsheetId'] as String?,
        sourceModifiedTime: json['sourceModifiedTime'] as String?,
        fromCoachUid: json['fromCoachUid'] as String?,
        fromCoachName: json['fromCoachName'] as String?,
        dayMoves: (json['dayMoves'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
        sentToClientIds:
            (json['sentToClientIds'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList(),
      );

  Program copyWith({
    String? id,
    String? userId,
    String? name,
    String? description,
    List<ProgramWeek>? weeks,
    MeetPlan? meetPlan,
    bool? isActive,
    DateTime? createdAt,
    String? sourceSpreadsheetId,
    String? sourceModifiedTime,
    String? fromCoachUid,
    String? fromCoachName,
    Map<String, String>? dayMoves,
    List<String>? sentToClientIds,
  }) =>
      Program(
        id: id ?? this.id,
        userId: userId ?? this.userId,
        name: name ?? this.name,
        description: description ?? this.description,
        weeks: weeks ?? this.weeks,
        meetPlan: meetPlan ?? this.meetPlan,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        sourceSpreadsheetId: sourceSpreadsheetId ?? this.sourceSpreadsheetId,
        sourceModifiedTime: sourceModifiedTime ?? this.sourceModifiedTime,
        fromCoachUid: fromCoachUid ?? this.fromCoachUid,
        fromCoachName: fromCoachName ?? this.fromCoachName,
        dayMoves: dayMoves ?? this.dayMoves,
        sentToClientIds: sentToClientIds ?? this.sentToClientIds,
      );
}
