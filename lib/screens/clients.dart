import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/coach.dart';
import '../models/user_profile.dart';
import '../models/workout.dart';
import '../services/auth_service.dart';
import '../services/coach_service.dart';
import '../services/firestore_service.dart';
import '../theme.dart';
import '../widgets/side_pill.dart';
import 'client_detail.dart';

/// Coach home: the clients linked to this coach. Each row shows the
/// client's total, their last finished workout, and a NEW badge when they
/// have logged a workout since the coach last opened them.
class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = AuthService().currentUid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients'),
        actions: [
          const SidePill(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('You are not signed in.'))
          : StreamBuilder<List<CoachLink>>(
              stream: CoachService().watchMyClients(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Could not load your clients. Try again.'),
                  );
                }
                final links = snapshot.data ?? [];
                if (links.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.people_outlined,
                          size: 56,
                          color: ForgeTheme.muted,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No clients yet',
                          textAlign: TextAlign.center,
                          style: ForgeTheme.titleLargeBold,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ask a client to show their code in Forge, then '
                          'scan it — or type the code in by hand.',
                          textAlign: TextAlign.center,
                          style: ForgeTheme.bodyMuted,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pushNamed('/scan'),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan a client code'),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: links.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _ClientCard(link: links[i]),
                );
              },
            ),
    );
  }
}

class _ClientCard extends StatefulWidget {
  final CoachLink link;

  const _ClientCard({required this.link});

  @override
  State<_ClientCard> createState() => _ClientCardState();
}

class _ClientCardState extends State<_ClientCard> {
  final _firestore = FirestoreService();
  UserProfile? _profile;
  WorkoutSession? _latest;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile =
          await _firestore.getProfile(widget.link.clientUid);
      final workouts = await _firestore.getWorkouts(
        widget.link.clientUid,
        limit: 1,
      );
      if (mounted) {
        setState(() {
          _profile = profile;
          _latest = workouts.isEmpty ? null : workouts.first;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _total {
    final lifts = _profile?.mainLifts ?? {};
    return (lifts['squat'] ?? 0) +
        (lifts['bench'] ?? 0) +
        (lifts['deadlift'] ?? 0);
  }

  bool get _hasNew {
    final latest = _latest;
    if (latest == null) return false;
    final viewed = widget.link.lastViewedAt;
    if (viewed == null) return true;
    return latest.date.isAfter(viewed);
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?.displayName ?? 'Client';
    return Card(
      child: ListTile(
        onTap: _loading
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClientDetailScreen(
                      link: widget.link,
                      profile: _profile,
                    ),
                  ),
                );
              },
        leading: CircleAvatar(
          backgroundColor: ForgeTheme.accent,
          foregroundColor: ForgeTheme.scaffoldBg,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: ForgeTheme.avatarInitial,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: ForgeTheme.titleMediumBold,
              ),
            ),
            if (_hasNew)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: ForgeTheme.green,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'NEW WORKOUT',
                  style: ForgeTheme.captionOnAccent,
                ),
              ),
          ],
        ),
        subtitle: _loading
            ? const Text('Loading…',
                style: ForgeTheme.bodyMuted)
            : Text(
                _latest == null
                    ? 'Total ${_total.toStringAsFixed(0)} kg · no workouts yet'
                    : 'Total ${_total.toStringAsFixed(0)} kg · last workout '
                        '${DateFormat.MMMd().format(_latest!.date)}',
                style: ForgeTheme.bodyMuted,
              ),
        trailing: const Icon(Icons.chevron_right, color: ForgeTheme.muted),
      ),
    );
  }
}
