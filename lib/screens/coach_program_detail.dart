import 'package:flutter/material.dart';

import '../models/program.dart';
import '../theme.dart';

/// "3 × 8-10 · 120 kg · RPE 8" — the prescription as one line. Pure,
/// so it is unit-testable.
String formatPrescription(ProgramExercise exercise) {
  final reps = exercise.displayRepsText;
  final parts = <String>['${exercise.sets} × ${reps ?? ''}'.trim()];
  if (exercise.targetWeightKg != null) {
    parts.add('${exercise.targetWeightKg!.toStringAsFixed(0)} kg');
  }
  if (exercise.percentOf1rm != null) {
    parts.add('${exercise.percentOf1rm!.toStringAsFixed(0)}% 1RM');
  }
  if (exercise.targetRpe != null && exercise.targetRpe!.isNotEmpty) {
    parts.add('RPE ${exercise.targetRpe}');
  }
  return parts.join(' · ');
}

/// Read-only view of a program: weeks, days, and every exercise with
/// its sets, reps, weight and RPE. Used by the coach Programs list and
/// by a client's profile (their active program).
class CoachProgramDetailScreen extends StatefulWidget {
  final Program program;

  const CoachProgramDetailScreen({super.key, required this.program});

  @override
  State<CoachProgramDetailScreen> createState() =>
      _CoachProgramDetailScreenState();
}

class _CoachProgramDetailScreenState extends State<CoachProgramDetailScreen> {
  int _weekIndex = 0;

  @override
  Widget build(BuildContext context) {
    final program = widget.program;
    final weeks = program.weeks;
    final week = weeks.isEmpty
        ? null
        : weeks[_weekIndex.clamp(0, weeks.length - 1)];
    return Scaffold(
      appBar: AppBar(title: Text(program.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    program.name,
                    style: ForgeTheme.headlineMedium,
                  ),
                  if (program.description != null &&
                      program.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      program.description!,
                      style: ForgeTheme.bodyMuted,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '${weeks.length} weeks · '
                    '${weeks.fold<int>(0, (sum, w) => sum + w.days.length)} days'
                    '${program.isActive ? ' · active program' : ''}',
                    style: ForgeTheme.bodyMuted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (weeks.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'This program has no weeks yet.',
                  textAlign: TextAlign.center,
                  style: ForgeTheme.bodyMuted,
                ),
              ),
            )
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: weeks.asMap().entries.map((entry) {
                  final i = entry.key;
                  final w = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(w.title),
                      selected: i == _weekIndex,
                      selectedColor: ForgeTheme.card,
                      side: BorderSide(
                        color: i == _weekIndex
                            ? ForgeTheme.accent
                            : ForgeTheme.divider,
                      ),
                      labelStyle: TextStyle(
                        color: i == _weekIndex
                            ? ForgeTheme.accent
                            : ForgeTheme.text,
                        fontWeight: i == _weekIndex
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                      onSelected: (_) => setState(() => _weekIndex = i),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            if (week != null)
              ...week.days.map(
                (day) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            day.title,
                            style: ForgeTheme.titleMediumBold,
                          ),
                          const SizedBox(height: 8),
                          if (day.exercises.isEmpty)
                            const Text(
                              'Rest day.',
                              style: ForgeTheme.bodyMuted,
                            )
                          else
                            ...day.exercises.map(
                              (exercise) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (exercise.supersetGroup != null)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: ForgeTheme.accent,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          exercise.supersetGroup!,
                                          style: ForgeTheme.captionAccent,
                                        ),
                                      ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(exercise.name),
                                          if (exercise.notes.isNotEmpty)
                                            Text(
                                              exercise.notes,
                                              style: ForgeTheme.bodyMuted,
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      formatPrescription(exercise),
                                      style: ForgeTheme.bodyMuted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
