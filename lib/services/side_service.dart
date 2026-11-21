import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which side of Forge the app shows: the lifter's own training, or the
/// coach side (clients). The small pill at the top right switches it;
/// profile setup picks the starting side. Stored on-device, not in the
/// profile — it is an app preference, not training data.
class SideService {
  static const String _key = 'forge_side';
  static const String training = 'training';
  static const String coach = 'coach';

  static final ValueNotifier<String> current =
      ValueNotifier<String>(training);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == coach) current.value = coach;
  }

  static Future<void> set(String side) async {
    if (side != training && side != coach) return;
    current.value = side;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, side);
  }

  static bool get isCoach => current.value == coach;
}
