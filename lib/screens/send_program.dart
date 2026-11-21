import 'package:flutter/material.dart';

import '../models/coach.dart';
import '../models/program.dart';
import '../services/auth_service.dart';
import '../services/coach_service.dart';
import '../services/firestore_service.dart';
import '../theme.dart';
import '../widgets/side_pill.dart';

/// Coach side: pick one of your coaching programs and send it to a
/// client. It lands in their Program list marked "From Coach" and
/// becomes their active program right away.
class SendProgramScreen extends StatefulWidget {
  final CoachLink link;
  final String clientName;

  const SendProgramScreen({
    super.key,
    required this.link,
    required this.clientName,
  });

  @override
  State<SendProgramScreen> createState() => _SendProgramScreenState();
}

class _SendProgramScreenState extends State<SendProgramScreen> {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  final _coach = CoachService();
  List<Program> _programs = [];
  bool _loading = true;
  String? _sendingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _auth.currentUid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      // Coaching programs only — training programs are never
      // sendable (Nov 21: the two lists are fully separate).
      final programs = await _firestore.getCoachPrograms(uid);
      if (mounted) {
        setState(() {
          _programs = programs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send(Program program) async {
    final coachUid = _auth.currentUid;
    if (coachUid == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send "${program.name}"?'),
        content: Text(
          'It will appear in ${widget.clientName}\'s Program list, marked '
          'as from you, and become their active program right away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _sendingId = program.id);
    try {
      final profile = await _firestore.getProfile(coachUid);
      await _coach.sendProgram(
        program: program,
        coachUid: coachUid,
        coachName: profile?.displayName ?? 'Coach',
        clientUid: widget.link.clientUid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${program.name}" sent to ${widget.clientName}.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _sendingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send that program. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Send to ${widget.clientName}'),
        actions: const [
          SidePill(),
          SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.file_upload_outlined,
                      color: ForgeTheme.accent,
                    ),
                    title: const Text('Import from spreadsheet'),
                    subtitle: const Text(
                      'Bring in a program from Google Sheets first',
                      style: ForgeTheme.bodyMuted,
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: ForgeTheme.muted,
                    ),
                    onTap: () =>
                        Navigator.of(context).pushNamed('/import'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'YOUR PROGRAMS',
                  style: ForgeTheme.sectionLabel,
                ),
                const SizedBox(height: 8),
                if (_programs.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'You have no coaching programs yet. Build one '
                        'on the Programs tab, or import one from a '
                        'spreadsheet.',
                        style: ForgeTheme.bodyMuted,
                      ),
                    ),
                  )
                else
                  ..._programs.map((program) {
                    final sent = program.sentToClientIds.length;
                    return Card(
                      child: ListTile(
                        title: Text(program.name),
                        subtitle: Text(
                          '${program.weeks.length} weeks'
                          '${sent > 0 ? ' · sent to $sent ${sent == 1 ? 'client' : 'clients'}' : ''}',
                          style: ForgeTheme.bodyMuted,
                        ),
                        trailing: _sendingId == program.id
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.send_outlined,
                                color: ForgeTheme.accent),
                        onTap: _sendingId == null
                            ? () => _send(program)
                            : null,
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
