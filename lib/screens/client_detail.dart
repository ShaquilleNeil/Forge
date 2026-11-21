import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/coach.dart';
import '../models/program.dart';
import '../models/user_profile.dart';
import '../models/workout.dart';
import '../services/coach_service.dart';
import '../services/firestore_service.dart';
import '../theme.dart';
import '../widgets/side_pill.dart';
import 'client_workout.dart';
import 'coach_program_detail.dart';
import 'coach_programs.dart';
import 'send_program.dart';

/// Coach view of one client: their total, finished workouts (read-only),
/// and the way to send them a program. Opening this screen clears the
/// NEW badge for the client.
class ClientDetailScreen extends StatefulWidget {
  final CoachLink link;
  final UserProfile? profile;

  const ClientDetailScreen({
    super.key,
    required this.link,
    this.profile,
  });

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  final _firestore = FirestoreService();
  final _coach = CoachService();
  List<WorkoutSession> _workouts = [];
  Program? _activeProgram;
  Program? _sentProgram;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _coach.markClientViewed(widget.link.id);
    _load();
  }

  Future<void> _load() async {
    try {
      final workouts = await _firestore.getWorkouts(
        widget.link.clientUid,
        limit: 20,
      );
      final programs = await _firestore.getPrograms(widget.link.clientUid);
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (mounted) {
        setState(() {
          _workouts = workouts;
          _activeProgram = findActiveProgram(programs);
          _sentProgram = myUid == null
              ? null
              : latestSentByMe(programs, myUid);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _total {
    final lifts = widget.profile?.mainLifts ?? {};
    return (lifts['squat'] ?? 0) +
        (lifts['bench'] ?? 0) +
        (lifts['deadlift'] ?? 0);
  }

  Future<void> _unlink() async {
    final name = widget.profile?.displayName ?? 'this client';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unlink $name?'),
        content: const Text(
          'You will lose access to their workouts and videos right away. '
          'They can link you again later with a new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _coach.unlink(widget.link.id);
    if (mounted) Navigator.of(context).pop();
  }

  String _programSummary(Program program) =>
      '${program.weeks.length} weeks · '
      '${program.weeks.fold<int>(0, (sum, w) => sum + w.days.length)} days';

  Widget _programCard(Program program, {required String status}) {
    return Card(
      child: ListTile(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CoachProgramDetailScreen(program: program),
            ),
          );
        },
        title: Text(program.name),
        subtitle: Text(
          status,
          style: ForgeTheme.bodyMuted,
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: ForgeTheme.muted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.profile?.displayName ?? 'Client';
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          const SidePill(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: ForgeTheme.accent,
                              foregroundColor: ForgeTheme.scaffoldBg,
                              radius: 24,
                              child: Text(
                                name.isNotEmpty
                                    ? name[0].toUpperCase()
                                    : '?',
                                style: ForgeTheme.avatarInitialLarge,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: ForgeTheme.titleLargeBold,
                                  ),
                                  Text(
                                    'Total ${_total.toStringAsFixed(0)} kg · '
                                    'linked ${DateFormat.MMMd().format(widget.link.createdAt)}',
                                    style: ForgeTheme.bodyMuted,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => SendProgramScreen(
                                        link: widget.link,
                                        clientName: name,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.send_outlined),
                                label: const Text('Send program'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _unlink,
                                icon: const Icon(Icons.link_off_outlined),
                                label: const Text('Unlink'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'CURRENT PROGRAM',
                  style: ForgeTheme.sectionLabel,
                ),
                const SizedBox(height: 8),
                if (_activeProgram == null && _sentProgram == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No active program. Send them one with the '
                        'button above.',
                        style: ForgeTheme.bodyMuted,
                      ),
                    ),
                  )
                else ...[
                  if (_activeProgram != null)
                    _programCard(
                      _activeProgram!,
                      status: _programSummary(_activeProgram!),
                    ),
                  if (_sentProgram != null &&
                      _sentProgram!.id != _activeProgram?.id)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _programCard(
                        _sentProgram!,
                        status:
                            'Sent by you · not active yet — they set it '
                            'active from their Programs tab.',
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'FINISHED WORKOUTS',
                  style: ForgeTheme.sectionLabel,
                ),
                const SizedBox(height: 8),
                if (_workouts.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No finished workouts yet. When they finish a '
                        'workout, it shows up here with every set and video.',
                        style: ForgeTheme.bodyMuted,
                      ),
                    ),
                  )
                else
                  ..._workouts.map((session) => Card(
                        child: ListTile(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ClientWorkoutScreen(
                                  session: session,
                                  clientName: name,
                                ),
                              ),
                            );
                          },
                          title: Text(session.title),
                          subtitle: Text(
                            '${DateFormat.MMMd().format(session.date)} · '
                            '${session.sets.where((s) => s.completed).length} sets · '
                            '${session.totalVolumeKg.toStringAsFixed(0)} kg',
                            style:
                                ForgeTheme.bodyMuted,
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: ForgeTheme.muted,
                          ),
                        ),
                      )),
              ],
            ),
    );
  }
}
