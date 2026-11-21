import 'package:flutter/material.dart';

import '../models/program.dart';
import '../services/program_progress.dart';
import '../theme.dart';

/// One coaching program on the coach Programs list: name, Template
/// pill when it is the template, one line of meta, and whether it has
/// been sent to any clients. No progress bar — a coaching program is
/// not trained. Tapping opens the program's detail page (coach side).
///
/// Spacing is owned explicitly (named constants, never framework
/// defaults) — see the layout test in test/coach_program_card_test.dart,
/// which measures the rendered gaps.
class CoachProgramCard extends StatelessWidget {
  const CoachProgramCard({
    super.key,
    required this.program,
    required this.onTap,
  });

  final Program program;
  final VoidCallback onTap;

  /// Gap: name row -> meta line.
  static const double gapNameToMeta = 8;

  /// Gap: meta line -> sent line.
  static const double gapMetaToSent = 6;

  /// Gap: sent line -> sheet line.
  static const double gapSentToSheet = 10;

  /// Card padding, all sides.
  static const double cardPadding = 16;

  @override
  Widget build(BuildContext context) {
    final sent = program.sentToClientIds.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                  if (isTemplateProgram(program))
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
                coachProgramMetaLine(program),
                style: const TextStyle(
                  fontSize: 13,
                  color: ForgeTheme.muted,
                ),
              ),
              const SizedBox(height: gapMetaToSent),
              Text(
                sent == 0
                    ? 'Not sent yet'
                    : 'Sent to $sent ${sent == 1 ? 'client' : 'clients'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: sent == 0 ? ForgeTheme.muted : ForgeTheme.green,
                ),
              ),
              if (program.sourceSpreadsheetId != null) ...[
                const SizedBox(height: gapSentToSheet),
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
