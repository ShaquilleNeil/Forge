/// One manual bodyweight entry (v1: manual only, no Health sync).
class BodyweightEntry {
  final String id;
  final DateTime date;
  final double weightKg;

  const BodyweightEntry({
    required this.id,
    required this.date,
    required this.weightKg,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'weightKg': weightKg,
      };

  factory BodyweightEntry.fromJson(Map<String, dynamic> json) =>
      BodyweightEntry(
        id: json['id'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        weightKg: (json['weightKg'] as num?)?.toDouble() ?? 0,
      );
}
