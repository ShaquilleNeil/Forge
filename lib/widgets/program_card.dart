import 'package:flutter/material.dart';

import '../models/program.dart';
import '../services/program_progress.dart';
import '../theme.dart';

/// One program on the Program list: name, Active/Template pill, one
/// line of meta, a progress bar, and a sheet marker when it came from
/// a spreadsheet. Tapping opens the program's detail page.
///
/// Spacing is owned explicitly (named constants, never framework
/// defaults) — see the layout test in test/program_card_test.dart,
/// which measures the rendered gaps.
class ProgramCard extends StatelessWidget {
  const ProgramCard({
    super.key,
    required this.program,
    required this.progress,
    required this.onTap,
  });

  final Program program;
  final ProgramProgress progress;
  final VoidCallback onTap;

  /// Gap: name row -> meta line.
  static const double gapNameToMeta = 8;

  /// Gap: meta line -> progress bar.
  static const double gapMetaToBar = 10;

  /// Gap: progress bar -> progress label.
  static const double gapBarToLabel = 6;

  /// Gap: progress label -> sheet line.
  static const double gapLabelToSheet = 10;

  /// Card padding, all sides.
  static const double cardPadding = 16;

  @override
  Widget build(BuildContext context) {
    final label = progressLabel(progress);
    final showBar = progress.totalDays > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: program.isActive
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ForgeTheme.radius),
              side: const BorderSide(color: ForgeTheme.green),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ForgeTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      program.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (program.isActive)
                    const _Pill(
                      label: 'Active',
                      background: ForgeTheme.green,
                      foreground: ForgeTheme.scaffoldBg,
                    )
                  else if (isTemplateProgram(program))
                    const _Pill(
                      label: 'Template',
                      background: ForgeTheme.raised,
                      foreground: ForgeTheme.muted,
                    ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    color: ForgeTheme.muted,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: gapNameToMeta),
              Text(
                programMetaLine(program, progress),
                style: const TextStyle(
                  fontSize: 13,
                  color: ForgeTheme.muted,
                ),
              ),
              if (showBar) ...[
                const SizedBox(height: gapMetaToBar),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 6,
                    backgroundColor: ForgeTheme.raised,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      ForgeTheme.accent,
                    ),
                  ),
                ),
                const SizedBox(height: gapBarToLabel),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: ForgeTheme.muted,
                  ),
                ),
              ],
              if (program.sourceSpreadsheetId != null) ...[
                SizedBox(
                  height: showBar ? gapLabelToSheet : gapMetaToBar,
                ),
                const Row(
                  children: [
                    Icon(
                      Icons.table_chart_outlined,
                      size: 14,
                      color: ForgeTheme.muted,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Linked to Google Sheet',
                      style: TextStyle(
                        fontSize: 12,
                        color: ForgeTheme.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
