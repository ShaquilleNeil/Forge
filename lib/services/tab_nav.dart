import 'package:flutter/foundation.dart';

/// Requests the AppShell bottom nav to switch tabs, from a screen that
/// sits above the shell (e.g. the import screen sends the user back to
/// the Today tab after a successful import). The shell listens and
/// consumes the request by resetting it to -1. -1 means "no request".
final goToTab = ValueNotifier<int>(-1);
