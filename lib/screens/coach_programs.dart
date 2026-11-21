import 'package:flutter/material.dart';

import '../models/program.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/coach_service.dart';
import '../services/firestore_service.dart';
import '../services/program_factory.dart';
import '../services/program_progress.dart';
import '../services/side_service.dart';
import '../services/tab_nav.dart';
import '../theme.dart';
import '../widgets/coach_program_card.dart';
import '../widgets/coach_programs_empty_state.dart';
import '../widgets/side_pill.dart';
import '../widgets/text_field_dialog.dart';

/// The latest program this coach sent to the client, if any. Pure, so
/// it is unit-testable. A sent program becomes the client's active one
/// right away, but it stays findable here even after the client
/// switches to another program — the client profile shows it
/// separately from the active one.
Program? latestSentByMe(List<Program> programs, String coachUid) {
  Program? best;
  for (final program in programs) {
    if (program.fromCoachUid != coachUid) continue;
    if (best == null || program.createdAt.isAfter(best.createdAt)) {
      best = program;
    }
  }
  return best;
}

/// The coach's program with the given [id] — the active one when the
/// list has one. Pure, so it is unit-testable.
Program? findActiveProgram(List<Program> programs) {
  for (final program in programs) {
    if (program.isActive) return program;
  }
  return null;
}

/// Coach side: the coach's own coaching programs — a list fully
/// separate from training (Nov 21). Training programs never appear
/// here. A program only gets in when the coach puts it there: build
/// one, import one from a spreadsheet, or copy one from training (a
/// one-time copy; afterwards the two are independent). Tap one to
/// open its detail page, where it is edited on the coach side.
class CoachProgramsScreen extends StatefulWidget {
  const CoachProgramsScreen({super.key});

  @override
  State<CoachProgramsScreen> createState() => _CoachProgramsScreenState();
}

class _CoachProgramsScreenState extends State<CoachProgramsScreen> {
  final _firestore = FirestoreService();
  final _auth = AuthService();

  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    final profile = await _firestore.getProfile(uid);
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _saveCoachProgram(Program program) async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    try {
      await _firestore.saveCoachProgram(uid, program);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
      return;
    }
    if (!mounted) return;
    // A fresh coaching program opens straight onto its detail page.
    Navigator.of(context).pushNamed(
      '/program-detail',
      arguments: {'id': program.id, 'coach': true},
    );
  }

  Future<void> _showNewCoachProgramDialog() async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    // Captured by the choice buttons before they pop: the dialog owns
    // its controller, so the name is gone once it returns.
    var name = '';
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => TextFieldDialog(
        title: const Text('New coaching program'),
        labelText: 'Program name',
        initialValue: 'My program',
        body: const Text(
          'Start blank, or use the Simple Strength (3-day) template built from 1RMs.',
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
    final program = choice == 'template'
        ? buildTemplateProgram(
            uid: uid,
            name: name,
            mainLifts: _profile?.mainLifts ?? {},
          )
        : buildBlankProgram(uid: uid, name: name);
    await _saveCoachProgram(program);
  }

  /// The bridge (Nov 21): pick a training program, copy it once
  /// into the coaching list. The copy is a clean snapshot — no sheet
  /// link, no meet plan, no moves — and the two never sync again.
  Future<void> _showCopyFromTraining() async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    List<Program> training;
    try {
      training = await _firestore.getPrograms(uid);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load your training programs.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    var goToTraining = false;
    final picked = await showDialog<Program>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy from training'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'A one-time copy — afterwards the two are independent.',
                style: ForgeTheme.bodyMuted,
              ),
              const SizedBox(height: 16),
              if (training.isEmpty)
                const Text(
                  'No training programs to copy yet.',
                  style: ForgeTheme.bodyMuted,
                )
              else
                ...training.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          title: Text(p.name),
                          subtitle: Text(
                            coachProgramMetaLine(p),
                            style: ForgeTheme.bodyMuted,
                          ),
                          trailing: const Icon(
                            Icons.copy_outlined,
                            color: ForgeTheme.accent,
                          ),
                          onTap: () => Navigator.of(context).pop(p),
                        ),
                      ),
                    )),
            ],
          ),
        ),
        actions: [
          // No training programs yet: offer the way out instead of
          // a dead end — switch to the training side, Program tab.
          if (training.isEmpty)
            FilledButton(
              onPressed: () {
                goToTraining = true;
                Navigator.of(context).pop();
              },
              child: const Text('Go to training'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (goToTraining) {
      await SideService.set(SideService.training);
      goToTab.value = 1;
      return;
    }
    if (picked == null) return;
    final copy = coachCopyOf(
      picked,
      newId: newProgramId('prog'),
      now: DateTime.now(),
    );
    try {
      await _firestore.saveCoachProgram(uid, copy);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not copy that program. Try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '"${copy.name}" copied to your coaching programs.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Programs'),
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
        title: const Text('Programs'),
        actions: [
          const SidePill(),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New coaching program',
            onPressed: _showNewCoachProgramDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: StreamBuilder<List<Program>>(
        stream: _firestore.watchCoachPrograms(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not load your coaching programs. Try again.',
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
          final programs = snapshot.data ?? [];
          if (programs.isEmpty) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: CoachProgramsEmptyState(
                onBuild: _showNewCoachProgramDialog,
                onImport: () => Navigator.of(context).pushNamed('/import'),
                onCopy: _showCopyFromTraining,
              ),
            );
          }
          // Newest first. Coach programs are never active, so there
          // is no active-first ordering like the training list.
          programs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: programs.length,
            itemBuilder: (context, i) {
              final program = programs[i];
              return CoachProgramCard(
                program: program,
                onTap: () => Navigator.of(context).pushNamed(
                  '/program-detail',
                  arguments: {'id': program.id, 'coach': true},
                ),
              );
            },
          );
        },
      ),
    );
  }
}
