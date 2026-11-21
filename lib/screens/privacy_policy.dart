import 'package:flutter/material.dart';

import '../theme.dart';

/// The privacy policy, as shown in the app. Keep in sync with
/// public/privacy.html — the same text is published there for the
/// store listings.
const String kPrivacyEffectiveDate = 'November 19, 2026';
const String kPrivacyUrl = 'your-firebase-project-id.web.app/privacy.html';
const String kPrivacyContact = 'contact@example.com';

const List<({String title, String body})> kPrivacySections = [
  (
    title: 'What Forge is',
    body: 'Forge is a personal training log by S.Neil. '
        'It keeps your program, your workouts and your numbers in one '
        'place, and lets a coach you link review them.',
  ),
  (
    title: 'What we collect',
    body: 'Your account: your name and email address, from Google '
        'sign-in or the email you sign up with.\n\n'
        'Your profile: display name, units (kg or lbs), bar weight, '
        'plate set, rest times and main lifts.\n\n'
        'Your training data: programs, workouts, sets, reps, RPE, bar '
        'speed, bodyweight entries and personal records.\n\n'
        'Videos you attach to sets (at most 5 minutes each).\n\n'
        'Coach links and pairing codes, when you connect with a coach.\n\n'
        'Spreadsheets: when you import a training spreadsheet, or turn '
        'on sheet write-back, Forge reads — and, for write-back, writes '
        'to — the Google Sheet you pick. Only that sheet, and only '
        'when you ask.',
  ),
  (
    title: 'How we use it',
    body: 'Only to run the app: your log, your programs, your coach '
        'link, your write-back to your own sheet. Forge has no '
        'advertising, no analytics, and never sells your data.',
  ),
  (
    title: 'Where it is stored',
    body: 'Google Firebase (Firestore and Cloud Storage), in the '
        'developer\u2019s Firebase project. Your data stays in your '
        'own account inside that project.',
  ),
  (
    title: 'Who it is shared with',
    body: 'Nobody — except a coach you link. While linked, that coach '
        'can see your workouts and programs. You can unlink them at '
        'any time from My coach or Clients, and nothing else leaves '
        'your account.',
  ),
  (
    title: 'Your choices',
    body: 'Export your workouts as a CSV from Settings. Delete '
        'everything — your account, your programs, your workouts, your '
        'videos — from Settings → Delete account. Unlink a coach from '
        'My coach or Clients.',
  ),
  (
    title: 'Contact and changes',
    body: 'Questions or corrections: $kPrivacyContact.\n\n'
        'If this policy changes, the new version appears here.',
  ),
];

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text(
            'Effective $kPrivacyEffectiveDate',
            style: ForgeTheme.bodyMuted,
          ),
          const SizedBox(height: 16),
          for (final section in kPrivacySections) ...[
            Text(section.title, style: ForgeTheme.titleLarge),
            const SizedBox(height: 4),
            Text(section.body, style: ForgeTheme.bodyMedium),
            const SizedBox(height: 20),
          ],
          const Divider(height: 1),
          const SizedBox(height: 16),
          const Text(
            'This policy is also published at $kPrivacyUrl.',
            style: ForgeTheme.bodyMuted,
          ),
        ],
      ),
    );
  }
}
