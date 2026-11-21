import '../models/program.dart';
import '../models/workout.dart';

/// Moving and mixing program days — pure helpers, unit-tested in
/// test/day_moves_test.dart.
///
/// A move never rewrites the program: the weeks and days stay where
/// they are. A move is a record on the program, [Program.dayMoves],
/// from a day key ("weekId:dayId") to the date the day was moved to.
/// The day shows on its new date until a session covering it
/// finishes; finishing deletes the record, so the day goes back to
/// its own slot, marked done by that session.
///
/// A day slot is one day as it appears on a date: the week + day,
/// plus the date it moved FROM (null when it is on its scheduled
/// date).
typedef DaySlot = ({
  ProgramWeek week,
  ProgramDay day,
  DateTime? movedFrom,
});

/// "weekId:dayId" — the key a move record and a mixed session use
/// for one program day.
String dayKey(String weekId, String dayId) => '$weekId:$dayId';

/// Splits a day key back into its week and day ids. Null when the
/// key has no separator.
({String weekId, String dayId})? parseDayKey(String key) {
  final at = key.indexOf(':');
  if (at < 0) return null;
  return (
    weekId: key.substring(0, at),
    dayId: key.substring(at + 1),
  );
}

/// "yyyy-MM-dd" — the stored form of a move target date.
String formatMoveDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Parses a stored move target date. Null when it is not a date.
DateTime? parseMoveDate(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// A rest day is one whose title says so — the same rule Today uses.
bool isRestDay(ProgramDay day) =>
    day.title.toLowerCase().contains('rest');

/// The date a day is scheduled on, from its title ("Mon Oct 19 · …").
/// Null when the title carries no date.
DateTime? scheduledDate(ProgramDay day, int year) =>
    ProgramDay.parseDate(day.title, year);

/// The date a day effectively falls on: its move target when it was
/// moved, else its scheduled date. Null when it has neither.
DateTime? effectiveDate(Program program, ProgramDay day) {
  final key = _keyFor(program, day);
  final target = key == null
      ? null
      : parseMoveDate(program.dayMoves[key] ?? '');
  return target ?? scheduledDate(day, program.createdAt.year);
}

/// The slot for one known day: its week + day, plus the date it
/// moved FROM (null when it is on its scheduled date).
DaySlot slotFor(Program program, ProgramWeek week, ProgramDay day) {
  final target = parseMoveDate(
    program.dayMoves[dayKey(week.id, day.id)] ?? '',
  );
  return (
    week: week,
    day: day,
    movedFrom:
        target == null ? null : scheduledDate(day, program.createdAt.year),
  );
}

/// Finds a day's week id inside [program]. Null when the day is not
/// in the program (a stale key).
String? _weekIdFor(Program program, ProgramDay day) {
  for (final week in program.weeks) {
    for (final d in week.days) {
      if (identical(d, day) || d.id == day.id) return week.id;
    }
  }
  return null;
}

String? _keyFor(Program program, ProgramDay day) {
  final weekId = _weekIdFor(program, day);
  if (weekId == null) return null;
  return dayKey(weekId, day.id);
}

/// Every day that falls on [date]: days scheduled on it that were not
/// moved away, plus days moved onto it. Moved-in days come first
/// (oldest scheduled date first — the missed day runs before the
/// day it joins), then the day(s) scheduled on the date. When a
/// training day is present, rest days on the same date are dropped —
/// the workout wins the day.
List<DaySlot> daysForDate(Program program, DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final movedIn = <(DateTime?, int, DaySlot)>[];
  final scheduled = <(int, DaySlot)>[];
  final weeks = [...program.weeks]
    ..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
  for (final week in weeks) {
    final days = [...week.days]
      ..sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
    for (final d in days) {
      final key = dayKey(week.id, d.id);
      final target = parseMoveDate(program.dayMoves[key] ?? '');
      final scheduledOn = scheduledDate(d, program.createdAt.year);
      final effective = target ?? scheduledOn;
      if (effective != day) continue;
      final slot = (week: week, day: d, movedFrom: target == null
          ? null
          : scheduledOn);
      if (target != null) {
        movedIn.add((scheduledOn, d.dayIndex, slot));
      } else {
        scheduled.add((d.dayIndex, slot));
      }
    }
  }
  movedIn.sort((a, b) {
    final byDate = _compareNullableDate(a.$1, b.$1);
    if (byDate != 0) return byDate;
    return a.$2.compareTo(b.$2);
  });
  scheduled.sort((a, b) => a.$1.compareTo(b.$1));
  final slots = [
    for (final m in movedIn) m.$3,
    for (final s in scheduled) s.$2,
  ];
  if (slots.any((s) => !isRestDay(s.day))) {
    return slots.where((s) => !isRestDay(s.day)).toList();
  }
  return slots;
}

int _compareNullableDate(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

/// Records a move: [day] now falls on [target]. Returns the updated
/// program; the original is untouched.
Program moveDay(
  Program program,
  ProgramWeek week,
  ProgramDay day,
  DateTime target,
) {
  final moves = Map<String, String>.from(program.dayMoves);
  moves[dayKey(week.id, day.id)] = formatMoveDate(target);
  return program.copyWith(dayMoves: moves);
}

/// Deletes the move records for [keys] — the "goes back" step. A day
/// whose move is deleted falls on its scheduled date again, and the
/// session that covered it marks it done there. Returns the updated
/// program; the original is untouched.
Program consumeMoves(Program program, Iterable<String> keys) {
  final moves = Map<String, String>.from(program.dayMoves);
  var changed = false;
  for (final key in keys) {
    if (moves.remove(key) != null) changed = true;
  }
  if (!changed) return program;
  return program.copyWith(dayMoves: moves);
}

/// Whether any training day in the program is still uncompleted.
/// Rest days never count. Today uses this to tell "no workout on
/// this date" (uncompleted days still exist elsewhere) apart from
/// "the whole program is done".
bool hasUncompletedDays(
  Program program,
  List<WorkoutSession> completed,
) {
  for (final week in program.weeks) {
    for (final day in week.days) {
      if (isRestDay(day)) continue;
      final done = completed.any(
        (w) => w.coversDay(program.id, week.id, day.id),
      );
      if (!done) return true;
    }
  }
  return false;
}

/// Strips the date prefix from a day title ("Mon Oct 19 · D1 · …"
/// becomes "D1 · …") for mixed-session titles.
String stripDatePrefix(String title) => title.replaceFirst(
      RegExp(
        r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+[A-Za-z]{3}\s+\d{1,2}\s+·\s+',
        caseSensitive: false,
      ),
      '',
    );
