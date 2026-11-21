import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/user_profile.dart';
import 'screens/clients.dart';
import 'screens/coach_programs.dart';
import 'screens/exercise_library.dart';
import 'screens/history.dart';
import 'screens/my_coach.dart';
import 'screens/privacy_policy.dart';
import 'screens/profile_setup.dart';
import 'screens/program.dart';
import 'screens/program_detail.dart';
import 'screens/progress.dart';
import 'screens/runner.dart';
import 'screens/scan_client.dart';
import 'screens/settings.dart';
import 'screens/sheet_import.dart';
import 'screens/splash_signin.dart';
import 'screens/today.dart';
import 'screens/tutorial.dart';
import 'services/active_session.dart';
import 'services/firestore_service.dart';
import 'services/live_activity_service.dart';
import 'services/rest_notify_service.dart';
import 'services/side_service.dart';
import 'services/tab_nav.dart';
import 'services/tutorial_service.dart';
import 'theme.dart';
import 'widgets/mini_workout_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await SideService.load();
  await RestNotifyService.init();
  // Configures the rest countdown's foreground service (Android);
  // the service itself starts per rest. Inert on iOS.
  RestNotifyService.initForegroundTask();
  // iOS only; a no-op on Android. The Live Activity's widget
  // extension target is added in Xcode (ios/LIVE_ACTIVITY_SETUP.md).
  await LiveActivityService.init();
  runApp(const ForgeApp());
}

class ForgeApp extends StatelessWidget {
  const ForgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Forge',
      theme: ForgeTheme.dark,
      home: const AuthGate(),
      routes: {
        '/signin': (_) => const SplashSignInScreen(),
        '/profile-setup': (_) => const ProfileSetupScreen(),
        '/today': (_) => const TodayScreen(),
        '/program': (_) => const ProgramScreen(),
        '/program-detail': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          // Training passes a plain program id (String); the coach
          // side passes {'id': ..., 'coach': true}.
          if (args is Map) {
            return ProgramDetailScreen(
              programId: args['id'] as String? ?? '',
              isCoach: args['coach'] == true,
            );
          }
          return ProgramDetailScreen(programId: args as String? ?? '');
        },
        '/runner': (_) => const RunnerScreen(),
        '/library': (_) => const ExerciseLibraryScreen(),
        '/history': (_) => const HistoryScreen(),
        '/progress': (_) => const ProgressScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/import': (_) => const SheetImportScreen(),
        '/my-coach': (_) => const MyCoachScreen(),
        '/privacy-policy': (_) => const PrivacyPolicyScreen(),
        '/scan': (_) => const ScanClientScreen(),
      },
    );
  }
}

/// Signed in -> profile check -> AppShell, otherwise -> sign-in screen.
///
/// The profile check lives here (not in the sign-in screen): after a
/// sign-in the auth stream swaps the tree to the app before the
/// sign-in screen's own profile read finishes, so a push from there
/// races disposal and a fresh user never sees setup.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return _SignedInHome(uid: snapshot.data!.uid);
        }
        return const SplashSignInScreen();
      },
    );
  }
}

/// Signed-in home: a user with a profile gets the app shell; a user
/// without one (fresh sign-in) gets profile setup, which asks whether
/// they train, coach, or both. The setup screen saves the profile and
/// this stream swaps to the shell on its own.
class _SignedInHome extends StatelessWidget {
  const _SignedInHome({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UserProfile?>(
      stream: FirestoreService().watchProfile(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('Could not load your profile. Check your connection.'),
            ),
          );
        }
        if (snapshot.data != null) return const AppShell();
        return const ProfileSetupScreen();
      },
    );
  }
}

/// Bottom nav, two sides:
/// training — Today, Program, center + (Start workout), History, Progress.
/// coach — Clients, center + (Scan a client code), Programs.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  Timer? _sessionTimer;

  List<Widget> get _pages => SideService.isCoach
      ? const [
          ClientsScreen(),
          SizedBox.shrink(), // center + scans a client code, not a tab
          CoachProgramsScreen(),
        ]
      : const [
          TodayScreen(),
          ProgramScreen(),
          SizedBox.shrink(), // center + opens the runner, not a tab
          HistoryScreen(),
          ProgressScreen(),
        ];

  @override
  void initState() {
    super.initState();
    goToTab.addListener(_onGoToTab);
    SideService.current.addListener(_onSideChanged);
    // First run only: the tour shows once, right after setup, and
    // never again (Settings can replay it).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowTour());
    });
    // Keep the mini workout bar and the center nav icon live: the
    // runner persists the session on every change, and the elapsed /
    // rest times are computed from the wall clock.
    ActiveSession.refresh();
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => ActiveSession.refresh(),
    );
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    goToTab.removeListener(_onGoToTab);
    SideService.current.removeListener(_onSideChanged);
    super.dispose();
  }

  /// First run only: shows the tour when this account has never
  /// seen it. The flag is per account — a second account on the
  /// same phone gets the tour too (Nov 19).
  Future<void> _maybeShowTour() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (await TutorialService().isTutorialSeen(uid)) return;
    if (!mounted) return;
    await showTutorial(context, uid);
  }

  /// Switching sides always lands on the side's home tab.
  void _onSideChanged() {
    if (mounted) setState(() => _index = 0);
  }

  /// A screen above the shell (e.g. the import screen) asked for a tab.
  /// The center + index is never a tab, so it is ignored.
  void _onGoToTab() {
    final tab = goToTab.value;
    goToTab.value = -1; // consume
    if (tab < 0 || tab >= _pages.length) return;
    final centerIndex = SideService.isCoach ? 1 : 2;
    if (tab == centerIndex) return;
    if (tab != _index) setState(() => _index = tab);
  }

  void _onTap(int index) {
    if (SideService.isCoach) {
      if (index == 1) {
        Navigator.of(context).pushNamed('/scan');
        return;
      }
      setState(() => _index = index);
      return;
    }
    if (index == 2) {
      Navigator.of(context).pushNamed('/runner');
      return;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final isCoach = SideService.isCoach;
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      // The mini workout bar sits above the nav while a session is
      // active. The runner is a pushed route over the shell, so the
      // bar is naturally hidden on the runner itself.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniWorkoutBar(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _onTap,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: isCoach
                ? const [
                    NavigationDestination(
                        icon: Icon(Icons.people), label: 'Clients'),
                    NavigationDestination(
                      icon: Icon(
                        Icons.add_circle,
                        size: 32,
                        color: ForgeTheme.accent,
                      ),
                      label: 'Scan',
                    ),
                    NavigationDestination(
                        icon: Icon(Icons.calendar_view_week),
                        label: 'Programs'),
                  ]
                : const [
                    NavigationDestination(
                        icon: Icon(Icons.today), label: 'Today'),
                    NavigationDestination(
                        icon: Icon(Icons.calendar_view_week),
                        label: 'Program'),
                    NavigationDestination(
                      icon: CenterWorkoutIcon(),
                      label: 'Workout',
                    ),
                    NavigationDestination(
                        icon: Icon(Icons.history), label: 'History'),
                    NavigationDestination(
                        icon: Icon(Icons.show_chart), label: 'Progress'),
                  ],
          ),
        ],
      ),
    );
  }
}
