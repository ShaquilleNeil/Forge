/// Draft submission to Rank (public side). Data hook only in v1:
/// nothing leaves the user's account unless they submit it later.
/// [status] is 'draft' in v1.
class Submission {
  final String id;
  final String userId;
  final String setId; // "sessionId:setIndex"
  final String exerciseId;
  final double claimedWeightKg;
  final double bodyweightKg;
  final DateTime date;
  final String? videoUrl;
  final String status;

  const Submission({
    required this.id,
    required this.userId,
    required this.setId,
    required this.exerciseId,
    required this.claimedWeightKg,
    required this.bodyweightKg,
    required this.date,
    this.videoUrl,
    this.status = 'draft',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'setId': setId,
        'exerciseId': exerciseId,
        'claimedWeightKg': claimedWeightKg,
        'bodyweightKg': bodyweightKg,
        'date': date.toIso8601String(),
        'videoUrl': videoUrl,
        'status': status,
      };

  factory Submission.fromJson(Map<String, dynamic> json) => Submission(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        setId: json['setId'] as String? ?? '',
        exerciseId: json['exerciseId'] as String? ?? '',
        claimedWeightKg: (json['claimedWeightKg'] as num?)?.toDouble() ?? 0,
        bodyweightKg: (json['bodyweightKg'] as num?)?.toDouble() ?? 0,
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        videoUrl: json['videoUrl'] as String?,
        status: json['status'] as String? ?? 'draft',
      );
}
