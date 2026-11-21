import 'dart:async';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/user_profile.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/rest_notify_service.dart';
import '../theme.dart';
import '../widgets/side_pill.dart';
import '../widgets/text_field_dialog.dart';
import 'tutorial.dart';

/// Settings: units, bar weight, plate set, account, data export/import,
/// about. Preference changes are saved to the user's profile.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirestoreService _db = FirestoreService();
  final AuthService _auth = AuthService();
  bool _exporting = false;
  bool _writeBackBusy = false;

  Future<void> _savePreference(
    String uid,
    UserProfile? profile,
    UserProfile Function(UserProfile base) update,
  ) async {
    final base = profile ??
        UserProfile(uid: uid, displayName: _auth.currentUser?.email ?? '');
    try {
      await _db.saveProfile(update(base));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save setting: $e')),
        );
      }
    }
  }

  /// Builds a CSV of all workouts + sets and shares it. Falls back to
  /// showing the saved file path when sharing is unavailable.
  Future<void> _exportCsv(String uid) async {
    setState(() => _exporting = true);
    try {
      final workouts = await _db.getWorkouts(uid, limit: 500);
      final rows = <List<dynamic>>[
        ['date', 'exercise', 'set', 'weightKg', 'reps', 'rpe', 'barSpeed', 'videoUrl'],
      ];
      for (final session in workouts) {
        for (final set in session.sets) {
          rows.add([
            DateFormat('yyyy-MM-dd').format(session.date),
            set.name,
            set.setIndex + 1,
            set.weightKg,
            set.reps,
            set.rpe ?? '',
            set.barSpeed ?? '',
            set.videoUrl ?? '',
          ]);
        }
      }
      final csv = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/forge-workouts-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv',
      );
      await file.writeAsString(csv);
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/csv')],
            subject: 'Forge workout history',
            text: 'My Forge workout history (CSV).',
          ),
        );
      } catch (e) {
        // Share sheet unavailable — show the saved file path instead.
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Export saved'),
              content: Text(
                'Sharing is not available on this device, but your CSV was saved to:\n\n${file.path}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Write-back toggle. Turning it on needs two things: a program that
  /// came from a spreadsheet (so there is a sheet to write to), and the
  /// Sheets write scope — requested here, with Google's consent UI, so
  /// the extra permission appears at this point, never at sign-in.
  /// Turning it off just saves the preference.
  Future<void> _toggleWriteBack(
    String uid,
    UserProfile? profile,
    bool value,
  ) async {
    if (!value) {
      await _savePreference(
        uid,
        profile,
        (p) => p.copyWith(writeBackToSheet: false),
      );
      return;
    }
    setState(() => _writeBackBusy = true);
    try {
      final programs = await _db.getPrograms(uid);
      final hasLinkedSheet = programs.any(
        (p) => (p.sourceSpreadsheetId ?? '').isNotEmpty,
      );
      if (!hasLinkedSheet) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Import a spreadsheet first — write-back needs a sheet to write to.',
              ),
            ),
          );
        }
        return;
      }
      final granted = await _auth.requestWriteAccess();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Write access was not granted — write-back stays off.',
              ),
            ),
          );
        }
        return;
      }
      await _savePreference(
        uid,
        profile,
        (p) => p.copyWith(writeBackToSheet: true),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sheet write-back is on — finished workouts will update your spreadsheet.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not turn on write-back: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _writeBackBusy = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to use Forge.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    // Leave Settings at once — the Google + Firebase sign-out can
    // take a few seconds, and the user should not watch Settings
    // while it finishes (Nov 19). The messenger is captured before
    // the pop: this screen is gone by the time sign-out lands, so a
    // failure has to be reported on the app's own messenger.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    try {
      await _auth.signOut();
      // AuthGate's stream swaps home to the sign-in screen once the
      // Firebase sign-out lands.
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not sign out: $e')),
      );
    }
  }

  /// Deletes the account for good: two confirms, a fresh sign-in
  /// proof (Google chooser, or the password for email users), then
  /// the Cloud Function removes everything server-side and the app
  /// signs out. The user lands on login; nothing is left behind.
  Future<void> _deleteAccount() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and everything in '
          'it: your profile, programs, workouts, personal records, '
          'bodyweight entries, videos, coach links and pairing codes. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete my account'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Last chance'),
        content: const Text(
          'Once it is gone, it is gone — there is no way to get your '
          'training data back. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep my account'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes, delete everything'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;
    // Prove it is really them before anything is deleted.
    try {
      if (_auth.usesGoogle) {
        await _auth.reauthenticateWithGoogle();
      } else if (_auth.usesPassword) {
        final password = await _askPassword();
        if (password == null || !mounted) return;
        await _auth.reauthenticateWithPassword(password);
      } else {
        // No known sign-in method to re-check — refuse rather than
        // delete on a stale session alone.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not verify how you signed in. Sign out and '
              'sign in again, then retry.',
            ),
          ),
        );
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not verify you: $e')),
      );
      return;
    }
    if (!mounted) return;
    // Leave Settings at once, like sign-out: the function can take a
    // while, and the user should not watch Settings while it runs.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    try {
      await AccountService().deleteAccount();
      // AuthGate swaps to login once the local sign-out lands.
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete the account: $e')),
      );
    }
  }

  /// Asks for the account password (email users only). Returns null
  /// when cancelled.
  Future<String?> _askPassword() async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => TextFieldDialog(
        title: const Text('Enter your password'),
        labelText: 'Password',
        obscureText: true,
        keyboardType: TextInputType.visiblePassword,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        actions: (context, text) => [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(text()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUid;
    final email = _auth.currentUser?.email;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: Text('Sign in to change settings.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [
          SidePill(),
          SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<UserProfile?>(
        stream: _db.watchProfile(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load settings: ${snap.error}',
                  textAlign: TextAlign.center,
                  style: ForgeTheme.errorText,
                ),
              ),
            );
          }
          final profile = snap.data;
          final units = profile?.units ?? 'kg';
          final barWeightKg = profile?.barWeightKg ?? 20.0;
          final plateSet = profile?.plateSet ?? 'calibrated';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const _SectionHeader('Units'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Display units — weights are always stored in kilograms.',
                        style: ForgeTheme.bodyMuted,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'kg',
                              label: Text('Kilograms (kg)'),
                            ),
                            ButtonSegment(
                              value: 'lb',
                              label: Text('Pounds (lb)'),
                            ),
                          ],
                          selected: {units},
                          onSelectionChanged: (selected) => _savePreference(
                            uid,
                            profile,
                            (p) => p.copyWith(units: selected.first),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const _SectionHeader('Bar weight'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'The bar you lift with — used for plate maths.',
                        style: ForgeTheme.bodyMuted,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<double>(
                          segments: const [
                            ButtonSegment(value: 15.0, label: Text('15 kg')),
                            ButtonSegment(value: 20.0, label: Text('20 kg')),
                            ButtonSegment(value: 25.0, label: Text('25 kg')),
                          ],
                          selected: {barWeightKg},
                          onSelectionChanged: (selected) => _savePreference(
                            uid,
                            profile,
                            (p) => p.copyWith(barWeightKg: selected.first),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const _SectionHeader('Plate set'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Which plates are on the rack at your gym.',
                        style: ForgeTheme.bodyMuted,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'calibrated',
                              label: Text('Calibrated kg'),
                            ),
                            ButtonSegment(
                              value: 'gym',
                              label: Text('Gym lb'),
                            ),
                          ],
                          selected: {plateSet},
                          onSelectionChanged: (selected) => _savePreference(
                            uid,
                            profile,
                            (p) => p.copyWith(plateSet: selected.first),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const _SectionHeader('Rest timer'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rest between sets — the timer that starts after you log a set. In a superset it starts after the round, not between the two exercises.',
                        style: ForgeTheme.bodyMuted,
                      ),
                      const SizedBox(height: 8),
                      _RestStepperRow(
                        label: 'Main lifts',
                        seconds: profile?.restMainSec ?? 180,
                        onChanged: (value) => _savePreference(
                          uid,
                          profile,
                          (p) => p.copyWith(restMainSec: value),
                        ),
                      ),
                      const Divider(height: 24),
                      _RestStepperRow(
                        label: 'Accessories',
                        seconds: profile?.restAccessorySec ?? 90,
                        onChanged: (value) => _savePreference(
                          uid,
                          profile,
                          (p) => p.copyWith(restAccessorySec: value),
                        ),
                      ),
                      const Divider(height: 24),
                      _RestStepperRow(
                        label: 'Supersets',
                        seconds: profile?.restSupersetSec ?? 180,
                        onChanged: (value) => _savePreference(
                          uid,
                          profile,
                          (p) => p.copyWith(restSupersetSec: value),
                        ),
                      ),
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show timer in notifications'),
                        subtitle: const Text(
                          'Rest countdown in the notification shade '
                          '(Android) or as a Live Activity (iOS)',
                        ),
                        value: profile?.restNotifications ?? true,
                        onChanged: (value) => _savePreference(
                          uid,
                          profile,
                          (p) => p.copyWith(restNotifications: value),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Vibrate when rest ends'),
                        subtitle: const Text(
                          'Buzz when the rest timer hits zero',
                        ),
                        value: profile?.restVibrate ?? true,
                        onChanged: (value) => _savePreference(
                          uid,
                          profile,
                          (p) => p.copyWith(restVibrate: value),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Sound when rest ends'),
                        subtitle: const Text(
                          'Play a sound with the rest-done alert',
                        ),
                        value: profile?.restSound ?? true,
                        onChanged: (value) => _savePreference(
                          uid,
                          profile,
                          (p) => p.copyWith(restSound: value),
                        ),
                      ),
                      if (Platform.isAndroid) const _ExactAlarmRow(),
                    ],
                  ),
                ),
              ),
              const _SectionHeader('Spreadsheet'),
              Card(
                shape: (profile?.writeBackToSheet ?? false)
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(
                            color: ForgeTheme.accent),
                      )
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Write results to Google Sheet',
                        ),
                        subtitle: Text(
                          (profile?.writeBackToSheet ?? false)
                              ? 'On — finishing a workout updates your spreadsheet'
                              : 'Off — Forge only reads your spreadsheet',
                        ),
                        value: profile?.writeBackToSheet ?? false,
                        onChanged: _writeBackBusy
                            ? null
                            : (value) =>
                                _toggleWriteBack(uid, profile, value),
                      ),
                      const SizedBox(height: 8),
                      _writeBackLine(
                        Icons.upload_outlined,
                        'Writes: weight, RPE, bar speed and Status when you finish — plus new-best singles to Progress.',
                      ),
                      const SizedBox(height: 6),
                      _writeBackLine(
                        Icons.lock_outlined,
                        'Never changes: your prescription columns (weight, sets × reps, target RPE).',
                      ),
                      const SizedBox(height: 6),
                      _writeBackLine(
                        Icons.key_outlined,
                        'Needs: Google write access — asked when you turn this on.',
                      ),
                      if (_writeBackBusy)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
              const _SectionHeader('Account'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.account_circle_outlined,
                            color: ForgeTheme.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              email ?? 'Signed in',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(
                            context,
                          ).pushNamed('/profile-setup'),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit profile'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _signOut,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ForgeTheme.red,
                            side: const BorderSide(color: ForgeTheme.red),
                          ),
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text('Sign out'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _deleteAccount,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ForgeTheme.red,
                            side: const BorderSide(color: ForgeTheme.red),
                          ),
                          icon: const Icon(
                            Icons.delete_forever_outlined,
                            size: 18,
                          ),
                          label: const Text('Delete account'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const _SectionHeader('Coach'),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.people_outlined,
                    color: ForgeTheme.accent,
                  ),
                  title: const Text('My coach'),
                  subtitle: const Text(
                    'Show your code to a coach, or unlink one.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushNamed('/my-coach'),
                ),
              ),
              const _SectionHeader('Data'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.download_outlined,
                        color: ForgeTheme.accent,
                      ),
                      title: const Text('Export CSV'),
                      subtitle: const Text(
                        'All workouts and sets as a spreadsheet file.',
                      ),
                      trailing: _exporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _exporting ? null : () => _exportCsv(uid),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.upload_outlined,
                        color: ForgeTheme.accent,
                      ),
                      title: const Text('Import from spreadsheet'),
                      subtitle: const Text(
                        'Import past workouts from a Google Sheet.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          Navigator.of(context).pushNamed('/import'),
                    ),
                    const Divider(height: 1),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Import history: workouts imported from a spreadsheet appear in History with their original dates. Re-importing the same sheet will update those sessions rather than duplicating them.',
                        style: ForgeTheme.bodyMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const _SectionHeader('Help'),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.play_circle_outlined,
                    color: ForgeTheme.accent,
                  ),
                  title: const Text('Replay tutorial'),
                  subtitle: const Text(
                    'Walk through the first-run tour again.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(showTutorial(context, uid)),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.policy_outlined,
                    color: ForgeTheme.accent,
                  ),
                  title: const Text('Privacy policy'),
                  subtitle: const Text(
                    'What Forge collects, and what happens to it.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).pushNamed('/privacy-policy'),
                ),
              ),
              const _SectionHeader('About'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Forge v1.0.0',
                              style: ForgeTheme.titleMedium,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Private by default — your training data is visible only to you.',
                              style: ForgeTheme.bodyMuted,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: ForgeTheme.sectionLabel,
      ),
    );
  }
}

/// One rest-duration row: label on the left, − / M:SS / + on the right.
/// Steps 30s, clamped to 0:30–10:00.
/// Exact-alarms status (Android 12+): the rest-done alert needs the
/// SCHEDULE_EXACT_ALARM permission to fire on time. When it is denied
/// the alert falls back to inexact (it may be a few minutes late), and
/// this row says so — with a button to allow it.
class _ExactAlarmRow extends StatefulWidget {
  const _ExactAlarmRow();

  @override
  State<_ExactAlarmRow> createState() => _ExactAlarmRowState();
}

class _ExactAlarmRowState extends State<_ExactAlarmRow> {
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: RestNotifyService.canScheduleExact(),
      builder: (context, snapshot) {
        final exact = snapshot.data ?? false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  exact ? Icons.check_circle : Icons.warning_amber,
                  size: 18,
                  color:
                      exact ? ForgeTheme.green : ForgeTheme.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    exact
                        ? 'Exact alarms: on — rest alerts fire on time.'
                        : 'Exact alarms: off — rest alerts may be a few '
                            'minutes late.',
                    style: ForgeTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (!exact) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _requesting
                    ? null
                    : () async {
                        setState(() => _requesting = true);
                        await RestNotifyService.requestExactAlarms();
                        if (mounted) setState(() => _requesting = false);
                      },
                child: const Text('Allow exact alarms'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _RestStepperRow extends StatelessWidget {
  final String label;
  final int seconds;
  final ValueChanged<int> onChanged;

  const _RestStepperRow({
    required this.label,
    required this.seconds,
    required this.onChanged,
  });

  static String _fmt(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: ForgeTheme.bodyLarge,
          ),
        ),
        IconButton(
          onPressed: seconds <= 30
              ? null
              : () => onChanged(seconds - 30 < 30 ? 30 : seconds - 30),
          icon: const Icon(Icons.remove),
          tooltip: 'Less rest',
        ),
        SizedBox(
          width: 64,
          child: Text(
            _fmt(seconds),
            textAlign: TextAlign.center,
            style: ForgeTheme.titleLarge,
          ),
        ),
        IconButton(
          onPressed: seconds >= 600
              ? null
              : () => onChanged(seconds + 30 > 600 ? 600 : seconds + 30),
          icon: const Icon(Icons.add),
          tooltip: 'More rest',
        ),
      ],
    );
  }
}

/// One of the three write-back explainer lines: icon + 14sp text.
Widget _writeBackLine(IconData icon, String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: ForgeTheme.muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: ForgeTheme.bodyMedium,
        ),
      ),
    ],
  );
}
