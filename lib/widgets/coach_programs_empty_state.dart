import 'package:flutter/material.dart';

import '../theme.dart';

/// Coach Programs empty state: the list starts empty and a program
/// only gets in when the coach puts it there — build one, import one
/// from a spreadsheet, or copy one from training (a one-time copy;
/// afterwards the two are independent).
///
/// Spacing is owned explicitly (named constants, never framework
/// defaults) — see the layout test in
/// test/coach_programs_empty_state_test.dart, which measures the
/// rendered gaps.
class CoachProgramsEmptyState extends StatelessWidget {
  const CoachProgramsEmptyState({
    super.key,
    required this.onBuild,
    required this.onImport,
    required this.onCopy,
  });

  final VoidCallback onBuild;
  final VoidCallback onImport;
  final VoidCallback onCopy;

  /// Gap: glyph -> title.
  static const double gapGlyphToTitle = 16;

  /// Gap: title -> body.
  static const double gapTitleToBody = 8;

  /// Gap: body -> first option.
  static const double gapBodyToOptions = 32;

  /// Gap: option -> option.
  static const double gapOptionToOption = 12;

  /// Option row padding, all sides.
  static const double optionPadding = 16;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 72),
        const Icon(
          Icons.calendar_view_week,
          size: 56,
          color: ForgeTheme.accent,
        ),
        const SizedBox(height: gapGlyphToTitle),
        const Text(
          'No coaching programs yet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: gapTitleToBody),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Coaching programs live here, separate from your training '
            'programs. Add one to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: ForgeTheme.muted),
          ),
        ),
        const SizedBox(height: gapBodyToOptions),
        _Option(
          icon: Icons.add,
          title: 'Build your own',
          subtitle: 'Start a blank program and add weeks and days',
          onTap: onBuild,
        ),
        const SizedBox(height: gapOptionToOption),
        _Option(
          icon: Icons.table_chart_outlined,
          title: 'Import from spreadsheet',
          subtitle: 'Same import as training — lands here, not there',
          onTap: onImport,
        ),
        const SizedBox(height: gapOptionToOption),
        _Option(
          icon: Icons.copy_outlined,
          title: 'Copy from training',
          subtitle:
              'One-time copy of a training program — afterwards they\'re independent',
          onTap: onCopy,
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ForgeTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(
            CoachProgramsEmptyState.optionPadding,
          ),
          child: Row(
            children: [
              Icon(icon, size: 24, color: ForgeTheme.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: ForgeTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: ForgeTheme.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
