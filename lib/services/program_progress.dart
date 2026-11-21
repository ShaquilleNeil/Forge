import 'package:intl/intl.dart';

import '../models/program.dart';
import '../models/workout.dart';
import 'day_moves.dart';
import 'strength_math.dart';

/// Progress of one program, from the same truth Today uses: a day is
/// done when a finished session covers it (`coversDay`). Rest days and
/// days with no exercises are not training days, so they never count
/// for or against progress.
class ProgramProgress {
  /// Training days with a finished session.
  final int doneDays;

  /// Training days in the whole program.
  final int totalDays;

  /// Weeks whose every training day is done (weeks with no training
  /// day never count as done).
  final int doneWeeks;

  /// Weeks in the program.
  final int totalWeeks;

  /// Index (in weekIndex order) of the week containing today, or the
  /// first week with a future day when today falls between weeks, or
  /// the last week when the program is over. Null when the program
  /// carries no dates at all.
  final int? currentWeekIndex;

  const ProgramProgress({
    required this.doneDays,
    required this.totalDays,
    required this.doneWeeks,
    required this.totalWeeks,
    required this.currentWeekIndex,
  });

  double get fraction =>
      totalDays == 0 ? 0 : doneDays / totalDays;
}

/// Whether a day counts toward progress: a real training day, not a
/// rest day and not an empty shell with no exercises.
bool isTrainingDay(ProgramDay day) =>
    !isRestDay(day) && day.exercises.isNotEmpty;

ProgramProgress programProgress(
  Program program,
  List<WorkoutSession> sessions, {
  DateTime? now,
}) {
  final finished = sessions.where((w) => w.status == 'completed');
  final weeks = [...program.weeks]
    ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
  var doneDays = 0;
  var totalDays = 0;
  var doneWeeks = 0;
  for (final week in weeks) {
    final training = week.days.where(isTrainingDay).toList();
    if (training.isEmpty) continue;
    var weekDone = true;
    for (final day in training) {
      totalDays++;
      final done = finished.any(
        (w) => w.coversDay(program.id, week.id, day.id),
      );
      if (done) {
        doneDays++;
      } else {
        weekDone = false;
      }
    }
    if (weekDone) doneWeeks++;
  }
  return ProgramProgress(
    doneDays: doneDays,
    totalDays: totalDays,
    doneWeeks: doneWeeks,
    totalWeeks: weeks.length,
    currentWeekIndex: currentWeekIndex(program, now ?? DateTime.now()),
  );
}

/// The week index (in weekIndex order) the program is on: the week
/// containing [today], else the first week with a future day, else the
/// last week when every dated day is past. Null when no day in the
/// program carries a date.
int? currentWeekIndex(Program program, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);
  final weeks = [...program.weeks]
    ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
  int? firstFuture;
  var sawDate = false;
  for (var i = 0; i < weeks.length; i++) {
    for (final d in weeks[i].days) {
      final date = ProgramDay.parseDate(d.title, program.createdAt.year);
      if (date == null) continue;
      sawDate = true;
      if (date == day) return i;
      if (date.isAfter(day) && firstFuture == null) firstFuture = i;
    }
  }
  if (!sawDate) return null;
  if (firstFuture != null) return firstFuture;
  return weeks.isEmpty ? null : weeks.length - 1;
}

/// "12 weeks · Week 6 of 12 · Meet Jan 16" — the parts that exist.
/// No current-week part when the program carries no dates, no meet
/// part when it has no meet plan.
String programMetaLine(Program program, ProgramProgress progress) {
  final parts = <String>[];
  final weeks = program.weeks.length;
  parts.add('$weeks ${weeks == 1 ? 'week' : 'weeks'}');
  final current = progress.currentWeekIndex;
  if (current != null && weeks > 0) {
    parts.add('Week ${current + 1} of $weeks');
  }
  final meet = program.meetPlan?.date;
  if (meet != null) {
    parts.add('Meet ${DateFormat('MMM d').format(meet)}');
  }
  return parts.join(' · ');
}

/// "8 weeks · 24 days" — the coach-side meta line. No week-of, no
/// meet: a coaching program is not trained, so neither applies.
String coachProgramMetaLine(Program program) {
  final weeks = program.weeks.length;
  final days =
      program.weeks.fold<int>(0, (sum, w) => sum + w.days.length);
  return '$weeks ${weeks == 1 ? 'week' : 'weeks'} · '
      '$days ${days == 1 ? 'day' : 'days'}';
}

/// "5 of 12 days done", or "Not started yet" when nothing is done.
/// Empty when the program has no training days at all.
String progressLabel(ProgramProgress progress) {
  if (progress.totalDays == 0) return '';
  if (progress.doneDays == 0) return 'Not started yet';
  return '${progress.doneDays} of ${progress.totalDays} days done';
}

/// Estimated length of a day: 10 minutes of setup plus ~3 minutes
/// per set. Mirrors the estimate Today shows (was `_estimatedMinutes`
/// there — the formula lives here now so both screens agree).
int estimatedMinutesForDay(ProgramDay day) {
  final sets = day.exercises.fold<int>(0, (sum, e) => sum + e.sets);
  return 10 + sets * 3;
}

/// "4 exercises · 16 sets · ~75 min". Rest days say so; empty days
/// say they have nothing yet.
String daySummaryLine(ProgramDay day) {
  if (isRestDay(day)) return 'Rest day';
  if (day.exercises.isEmpty) return 'No exercises yet';
  final sets = day.exercises.fold<int>(0, (sum, e) => sum + e.sets);
  final n = day.exercises.length;
  return '$n ${n == 1 ? 'exercise' : 'exercises'} · '
      '$sets ${sets == 1 ? 'set' : 'sets'} · '
      '~${estimatedMinutesForDay(day)} min';
}

/// The first two exercise names, with " · …" when there are more.
/// Empty when the day has no exercises.
String dayPreviewNames(ProgramDay day) {
  if (day.exercises.isEmpty) return '';
  final names = day.exercises.take(2).map((e) => e.name).toList();
  final shown = names.join(' · ');
  return day.exercises.length > 2 ? '$shown · …' : shown;
}

/// The in-app Simple Strength template marks itself with this
/// description (set in `_buildTemplateProgram`). It is the only
/// marker the template leaves behind.
bool isTemplateProgram(Program program) =>
    program.description == 'Simple Strength (3-day)';

/// "3 × 8-10 · 120 kg · RPE 8" — sets, reps, weight (or %1RM) and RPE.
/// [units] is 'kg' or 'lb'.
String exerciseSummary(ProgramExercise ex, String units) {
  final parts = <String>['${ex.sets} × ${repsLabel(ex)}'];
  if (ex.targetWeightKg != null) {
    parts.add(_fmtWeight(ex.targetWeightKg!, units));
  } else if (ex.percentOf1rm != null) {
    parts.add('${(ex.percentOf1rm! * 100).round()}% 1RM');
  }
  if (ex.targetRpe != null && ex.targetRpe!.isNotEmpty) {
    parts.add('RPE ${ex.targetRpe}');
  }
  return parts.join(' · ');
}

String _fmtWeight(double kg, String units) {
  if (units == 'lb') return '${StrengthMath.kgToLb(kg).round()} lb';
  if (kg == kg.roundToDouble()) return '${kg.round()} kg';
  return '${kg.toStringAsFixed(1)} kg';
}

String repsLabel(ProgramExercise ex) {
  final text = ex.displayRepsText;
  if (text != null && text.isNotEmpty) return text;
  if (ex.repsMin != null && ex.repsMax != null) {
    if (ex.repsMin == ex.repsMax) return '${ex.repsMin}';
    return '${ex.repsMin}–${ex.repsMax}';
  }
  if (ex.repsMin != null) return '${ex.repsMin}';
  return '—';
}
