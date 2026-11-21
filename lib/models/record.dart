/// A personal record: best weight and best estimated 1RM for an exercise.
class Record {
  final String exerciseId;
  final double bestWeightKg;
  final double bestE1rmKg;
  final DateTime date;
  final String? setId; // "sessionId:setIndex" of the set that set it
  final String? videoUrl;

  const Record({
    required this.exerciseId,
    required this.bestWeightKg,
    required this.bestE1rmKg,
    required this.date,
    this.setId,
    this.videoUrl,
  });

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'bestWeightKg': bestWeightKg,
        'bestE1rmKg': bestE1rmKg,
        'date': date.toIso8601String(),
        'setId': setId,
        'videoUrl': videoUrl,
      };

  factory Record.fromJson(Map<String, dynamic> json) => Record(
        exerciseId: json['exerciseId'] as String? ?? '',
        bestWeightKg: (json['bestWeightKg'] as num?)?.toDouble() ?? 0,
        bestE1rmKg: (json['bestE1rmKg'] as num?)?.toDouble() ?? 0,
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        setId: json['setId'] as String?,
        videoUrl: json['videoUrl'] as String?,
      );
}
