import 'package:shared_preferences/shared_preferences.dart';

/// The first-run tour's seen flag, stored in SharedPreferences.
/// Keyed by the account's uid: SharedPreferences lives on the
/// phone, not the account, so a global flag hid the tour from a
/// second account signed in on the same phone (Nov 19).
class TutorialService {
  /// 'forge_tutorial_seen_<uid>'.
  static String tutorialKey(String uid) => 'forge_tutorial_seen_$uid';

  Future<bool> isTutorialSeen(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(tutorialKey(uid)) ?? false;
  }

  Future<void> markTutorialSeen(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(tutorialKey(uid), true);
  }
}
