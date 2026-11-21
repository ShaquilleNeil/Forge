import 'package:flutter/material.dart';

import '../theme.dart';

/// First-run empty state shared by Today and Program: a brand-new user
/// starts with nothing pre-loaded. Import is the primary action; the
/// template and a blank program are secondary. Nothing is created until
/// the user picks one of the three.
class ProgramEmptyState extends StatelessWidget {
  const ProgramEmptyState({
    super.key,
    required this.onImport,
    required this.onTemplate,
    required this.onBlank,
  });

  final VoidCallback onImport;
  final VoidCallback onTemplate;
  final VoidCallback onBlank;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.calendar_view_week_outlined,
          color: ForgeTheme.accent,
          size: 48,
        ),
        const SizedBox(height: 16),
        const Text(
          'No program yet',
          textAlign: TextAlign.center,
          style: ForgeTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Import your spreadsheet to load your program, start from the Simple Strength template, or build your own.',
          textAlign: TextAlign.center,
          style: ForgeTheme.bodyMuted,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onImport,
          child: const Text('Import from spreadsheet'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onTemplate,
          child: const Text('Use Simple Strength template'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onBlank,
          child: const Text('Build your own program'),
        ),
      ],
    );
  }
}
