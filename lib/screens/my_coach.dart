import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/coach.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/coach_service.dart';
import '../services/firestore_service.dart';
import '../theme.dart';
import '../widgets/side_pill.dart';

/// "My coach" — the client side of pairing. Shows the QR and code the
/// client shows (or sends) to a coach, and who is currently linked.
/// Nothing is shared until the client shows or sends this code.
class MyCoachScreen extends StatefulWidget {
  const MyCoachScreen({super.key});

  @override
  State<MyCoachScreen> createState() => _MyCoachScreenState();
}

class _MyCoachScreenState extends State<MyCoachScreen> {
  final _auth = AuthService();
  final _firestore = FirestoreService();
  final _coach = CoachService();

  PairingCode? _code;
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  Future<void> _loadCode() async {
    final uid = _auth.currentUid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final code = await _coach.getMyCode(uid);
      if (mounted) setState(() => _code = code);
    } catch (_) {
      // No code yet is not an error — the screen offers to make one.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _makeCode() async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final profile = await _firestore.getProfile(uid);
      final code = await _coach.createCode(
        uid,
        profile?.displayName ?? 'A lifter',
      );
      if (mounted) setState(() => _code = code);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not make a code. Try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _shareCode() async {
    final code = _code;
    if (code == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Coach me on Forge — my pairing code is ${code.display}. '
            'It expires in 24 hours, and I can unlink you anytime.',
      ),
    );
  }

  Future<void> _unlink(CoachLink link, String coachName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Unlink $coachName?'),
        content: const Text(
          'They will lose access to your workouts and videos right away. '
          'You can link them again later with a new code.',
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
    try {
      await _coach.unlink(link.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not unlink. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My coach'),
        actions: const [
          SidePill(),
          SizedBox(width: 4),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('You are not signed in.'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_code == null) ...[
                        const Text(
                          'Show this to your coach',
                          style: ForgeTheme.titleLargeBold,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your coach scans the code once and can then see your '
                          'finished workouts, sets and videos — and send you '
                          'programs. Nothing is shared until you show or send it.',
                          style: ForgeTheme.bodyMuted,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _working ? null : _makeCode,
                          child: _working
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Generate my code'),
                        ),
                      ] else ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Text(
                                  'Show this to your coach',
                                  style: ForgeTheme.titleMediumBold,
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: ForgeTheme.text,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: QrImageView(
                                    data: _code!.display,
                                    version: QrVersions.auto,
                                    size: 200,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SelectableText(
                                  _code!.display,
                                  style: ForgeTheme.codeDisplay,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Expires ${DateFormat.MMMd().add_jm().format(_code!.expiresAt)}',
                                  style: ForgeTheme.bodyMuted,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _shareCode,
                                        icon: const Icon(Icons.share_outlined),
                                        label: const Text('Share code'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed:
                                            _working ? null : _makeCode,
                                        icon: const Icon(
                                            Icons.refresh_outlined),
                                        label: const Text('New code'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: ForgeTheme.errorText,
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Text(
                        'LINKED COACHES',
                        style: ForgeTheme.sectionLabel,
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<List<CoachLink>>(
                        stream: _coach.watchMyCoaches(uid),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child:
                                  Center(child: CircularProgressIndicator()),
                            );
                          }
                          final links = snapshot.data ?? [];
                          if (links.isEmpty) {
                            return const Card(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text(
                                  'No coach linked yet. When you show your '
                                  'code to a coach, they appear here — and you '
                                  'can unlink them anytime.',
                                  style: ForgeTheme.bodyMuted,
                                ),
                              ),
                            );
                          }
                          return Column(
                            children: links
                                .map((link) => _CoachRow(
                                      link: link,
                                      onUnlink: _unlink,
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _CoachRow extends StatelessWidget {
  final CoachLink link;
  final void Function(CoachLink link, String coachName) onUnlink;

  const _CoachRow({required this.link, required this.onUnlink});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserProfile?>(
      future: FirestoreService().getProfile(link.coachUid),
      builder: (context, snapshot) {
        final name = snapshot.data?.displayName ?? 'Coach';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: ForgeTheme.accent,
              foregroundColor: ForgeTheme.scaffoldBg,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: ForgeTheme.avatarInitial,
              ),
            ),
            title: Text(name),
            subtitle: Text(
              'Linked ${DateFormat.MMMd().format(link.createdAt)}',
              style: ForgeTheme.bodyMuted,
            ),
            trailing: TextButton(
              onPressed: () => onUnlink(link, name),
              child: const Text('Unlink'),
            ),
          ),
        );
      },
    );
  }
}
