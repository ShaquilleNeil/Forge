import 'package:flutter/material.dart';

import '../models/program.dart';
import '../models/user_profile.dart';
import '../models/workout.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/program_factory.dart';
import '../services/program_progress.dart';
import '../theme.dart';
import '../widgets/program_card.dart';
import '../widgets/program_empty_state.dart';
import '../widgets/side_pill.dart';
import '../widgets/text_field_dialog.dart';

/// Program list: one card per program. Tapping a card opens that
/// program on its own detail page. Creation (blank / template /
/// import) lives here; everything about one program lives on the
/// detail page.
class ProgramScreen extends StatefulWidget {
  const ProgramScreen({super.key});

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  final _firestore = FirestoreService();
  final _auth = AuthService();

  UserProfile? _profile;
  bool _handledRouteAction = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    // Deep link from Today's empty state: open the creation flow for the
    // path the user picked (template or blank) instead of just showing
    // the Program empty state again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_handledRouteAction || !mounted) return;
      _handledRouteAction = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, String>) {
        if (args['action'] == 'template') {
          _createFromTemplate();
        } else if (args['action'] == 'blank') {
          _createBlank();
        }
      }
    });
  }

  Future<void> _loadProfile() async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    final profile = await _firestore.getProfile(uid);
    if (mounted) setState(() => _profile = profile);
  }

  Future<bool> _save(Program program) async {
    final uid = _auth.currentUid;
    if (uid == null) return false;
    try {
      await _firestore.saveProgram(uid, program);
      return true;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
      return false;
    }
  }

  // ---------- Creation ----------

  Future<String?> _promptProgramName({required String initial}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => TextFieldDialog(
        title: const Text('Program name'),
        labelText: 'Program name',
        initialValue: initial,
        actions: (context, text) => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(text().trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<void> _createProgram(String choice, String name) async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    final program = choice == 'template'
        ? _buildTemplateProgram(uid: uid, name: name)
        : _buildBlankProgram(uid: uid, name: name);
    final ok = await _save(program);
    if (!ok || !mounted) return;
    // A fresh program opens straight onto its detail page.
    Navigator.of(context).pushNamed('/program-detail', arguments: program.id);
  }

  /// Empty-state path: template straight from the empty state.
  Future<void> _createFromTemplate() async {
    final name = await _promptProgramName(initial: 'Simple Strength');
    if (name == null) return;
    await _createProgram('template', name);
  }

  /// Empty-state path: blank program straight from the empty state.
  Future<void> _createBlank() async {
    final name = await _promptProgramName(initial: 'My program');
    if (name == null) return;
    await _createProgram('blank', name);
  }

  Future<void> _showNewProgramDialog() async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    // Captured by the choice buttons before they pop: the dialog owns
    // its controller, so the name is gone once it returns.
    var name = '';
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => TextFieldDialog(
        title: const Text('New program'),
        labelText: 'Program name',
        initialValue: 'My program',
        body: const Text(
          'Start blank, or use the Simple Strength (3-day) template built from your 1RMs.',
          style: ForgeTheme.bodyMuted,
        ),
        stackedActions: true,
        actions: (context, text) => [
          OutlinedButton(
            onPressed: () {
              name = text().trim();
              Navigator.of(context).pop('blank');
            },
            child: const Text('Blank program'),
          ),
          FilledButton(
            onPressed: () {
              name = text().trim();
              Navigator.of(context).pop('template');
            },
            child: const Text('Use template'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (choice == null || name.isEmpty) return;
    await _createProgram(choice, name);
  }

  Program _buildBlankProgram({required String uid, required String name}) =>
      buildBlankProgram(uid: uid, name: name);

  Program _buildTemplateProgram({required String uid, required String name}) =>
      buildTemplateProgram(
        uid: uid,
        name: name,
        mainLifts: _profile?.mainLifts ?? {},
      );

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Program'),
          actions: [
            const SidePill(),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
            ),
          ],
        ),
        body: const Center(child: Text('You are not signed in.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Program'),
        actions: [
          const SidePill(),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New program',
            onPressed: _showNewProgramDialog,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import from spreadsheet',
            onPressed: () => Navigator.of(context).pushNamed('/import'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: StreamBuilder<List<Program>>(
        stream: _firestore.watchPrograms(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('Could not load your programs. Try again.'),
            );
          }
          final programs = snapshot.data ?? [];
          if (programs.isEmpty) return _emptyState(context);
          // Active program first, then newest first.
          programs.sort((a, b) {
            if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
            return b.createdAt.compareTo(a.createdAt);
          });
          // Finished sessions feed every card's progress bar (one
          // stream for the whole list; a 12-week program holds ~50
          // sessions, so the limit covers a full year of training).
          return StreamBuilder<List<WorkoutSession>>(
            stream: _firestore.watchWorkouts(uid, limit: 500),
            builder: (context, workoutsSnapshot) {
              if (workoutsSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (workoutsSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Could not load workout progress. Try again.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final sessions = workoutsSnapshot.data ?? [];
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: programs.length,
                itemBuilder: (context, index) {
                  final program = programs[index];
                  return ProgramCard(
                    program: program,
                    progress: programProgress(program, sessions),
                    onTap: () => Navigator.of(context).pushNamed(
                      '/program-detail',
                      arguments: program.id,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 40),
          ProgramEmptyState(
            onImport: () => Navigator.of(context).pushNamed('/import'),
            onTemplate: _createFromTemplate,
            onBlank: _createBlank,
          ),
        ],
      ),
    );
  }
}
