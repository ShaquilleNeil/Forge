/// Exercise from the library. [category] is one of
/// squat | bench | deadlift | accessory | conditioning.
class Exercise {
  final String id;
  final String name;
  final String category;
  final bool isMain;
  final bool defaultBar;

  const Exercise({
    required this.id,
    required this.name,
    this.category = 'accessory',
    this.isMain = false,
    this.defaultBar = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'isMain': isMain,
        'defaultBar': defaultBar,
      };

  /// Whether a free-text exercise name is a main lift — a squat, bench
  /// or deadlift variation ("Squat, beltless", "Comp bench", "Paused
  /// deadlift"). Used for imported programs, whose exercise ids are
  /// slugs of the sheet names and never match the built-in ids.
  /// Romanian and stiff-leg deadlifts are hinge accessories, not mains.
  static bool nameIsMain(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('romanian') || lower.contains('stiff')) return false;
    return lower.contains('squat') ||
        lower.contains('bench') ||
        lower.contains('deadlift');
  }

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'accessory',
        isMain: json['isMain'] as bool? ?? false,
        defaultBar: json['defaultBar'] as bool? ?? false,
      );
}

/// Built-in library shipped with v1 (seeded on first run by the
/// exercise-library screen agent; kept here so every screen agrees).
class BuiltInExercises {
  static const List<Exercise> all = [
    Exercise(id: 'squat', name: 'Squat', category: 'squat', isMain: true, defaultBar: true),
    Exercise(id: 'bench', name: 'Bench Press', category: 'bench', isMain: true, defaultBar: true),
    Exercise(id: 'deadlift', name: 'Deadlift', category: 'deadlift', isMain: true, defaultBar: true),
    Exercise(id: 'ohp', name: 'Overhead Press', category: 'accessory', defaultBar: true),
    Exercise(id: 'row', name: 'Barbell Row', category: 'accessory', defaultBar: true),
    Exercise(id: 'pullup', name: 'Pull-Up', category: 'accessory'),
    Exercise(id: 'rdl', name: 'Romanian Deadlift', category: 'accessory', defaultBar: true),
    Exercise(id: 'legpress', name: 'Leg Press', category: 'accessory'),
    Exercise(id: 'lunges', name: 'Lunges', category: 'accessory'),
    Exercise(id: 'dips', name: 'Dips', category: 'accessory'),
  ];
}
