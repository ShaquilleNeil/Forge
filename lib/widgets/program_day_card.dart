import 'package:flutter/material.dart';

import '../models/program.dart';
import '../services/program_progress.dart';
import '../theme.dart';

/// One day inside a program week on the detail page: title, a
/// one-line summary (counts + time, or "Rest day"), the first exercise
/// names, and — when expanded — every exercise with edit/remove plus
/// an Add exercise button.
///
/// Spacing is owned explicitly (named constants, never framework
/// defaults) — see the layout test in test/program_day_card_test.dart,
/// which measures the rendered gaps.
class ProgramDayCard extends StatelessWidget {
  const ProgramDayCard({
    super.key,
    required this.day,
    required this.isToday,
    required this.expanded,
    required this.units,
    required this.onToggle,
    required this.onRemoveDay,
    required this.onAddExercise,
    required this.onEditWeight,
    required this.onRemoveExercise,
  });

  final ProgramDay day;
  final bool isToday;
  final bool expanded;
  final String units;
  final VoidCallback onToggle;
  final VoidCallback onRemoveDay;
  final VoidCallback onAddExercise;

  /// (exercise index) -> edit that exercise's target weight.
  final void Function(int exIndex) onEditWeight;

  /// (exercise index) -> remove that exercise.
  final void Function(int exIndex) onRemoveExercise;

  /// Gap: day title -> summary line.
  static const double gapTitleToSummary = 6;

  /// Gap: summary line -> exercise names preview.
  static const double gapSummaryToNames = 4;

  /// Header block padding, vertical.
  static const double headerPaddingVertical = 14;

  /// Gap: last exercise row -> Add exercise button.
  static const double gapExercisesToAdd = 4;

  /// Padding under the Add exercise button, to the card edge.
  static const double addButtonBottomPadding = 16;

  @override
  Widget build(BuildContext context) {
    final names = dayPreviewNames(day);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: isToday
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ForgeTheme.radius),
              side: const BorderSide(color: ForgeTheme.accent),
            )
          : null,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(ForgeTheme.radius),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: headerPaddingVertical,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          day.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isToday)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: ForgeTheme.accentTint,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ForgeTheme.accentLight,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outlined,
                          color: ForgeTheme.muted,
                        ),
                        tooltip: 'Remove day',
                        onPressed: onRemoveDay,
                      ),
                      Icon(
                        expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: ForgeTheme.muted,
                      ),
                    ],
                  ),
                  const SizedBox(height: gapTitleToSummary),
                  Text(
                    '${isToday ? 'Today · ' : ''}${daySummaryLine(day)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: ForgeTheme.muted,
                    ),
                  ),
                  if (names.isNotEmpty) ...[
                    const SizedBox(height: gapSummaryToNames),
                    Text(
                      names,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ...day.exercises.asMap().entries.map((entry) {
                    final exIndex = entry.key;
                    final ex = entry.value;
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ex.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  exerciseSummary(ex, units),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: ForgeTheme.muted,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: ForgeTheme.muted,
                            ),
                            tooltip: 'Edit target weight',
                            onPressed: () => onEditWeight(exIndex),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: ForgeTheme.red.withValues(alpha: 0.7),
                            ),
                            tooltip: 'Remove exercise',
                            onPressed: () => onRemoveExercise(exIndex),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: gapExercisesToAdd),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onAddExercise,
                      icon: const Icon(Icons.add),
                      label: const Text('Add exercise'),
                    ),
                  ),
                  const SizedBox(height: addButtonBottomPadding),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
