import 'dart:math' as math;

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

import '../models/program.dart';
import '../models/record.dart';
import '../models/workout.dart';
import 'day_moves.dart';
import 'firestore_service.dart';
import 'strength_math.dart';

/// A spreadsheet found in the user's Drive.
class SpreadsheetFileInfo {
  final String id;
  final String name;
  final DateTime? modifiedTime;

  const SpreadsheetFileInfo({
    required this.id,
    required this.name,
    this.modifiedTime,
  });
}

/// Raw values fetched from a spreadsheet: title + one row grid per tab.
/// Each row is the A–Z cells as strings (empty string for a blank cell).
/// [truncatedTabs] names the tabs that hit the 100-row read cap (A25):
/// a tab that returns exactly 100 rows may have more below row 100,
/// which were never read — the preview warns about those tabs instead
/// of silently importing a partial sheet.
class FetchedSpreadsheet {
  final String title;
  final Map<String, List<List<String>>> tabs;
  final List<String> truncatedTabs;

  const FetchedSpreadsheet({
    required this.title,
    required this.tabs,
    this.truncatedTabs = const [],
  });
}

/// One row the parser could not interpret, for the preview screen.
class SkippedRow {
  final String tab;
  final int row; // 1-based sheet row number
  final String reason;

  /// The row's own content (exercise name or note text), shown in the
  /// preview instead of repeating the full reason sentence.
  final String? text;

  const SkippedRow({
    required this.tab,
    required this.row,
    required this.reason,
    this.text,
  });
}

/// Parsed "Sets x reps" cell: `3 x 10-12` -> (3, 10, 12).
/// Free-text prescriptions (`1 x 25-30 min`, `2 x 30 s/side`) keep
/// [repsText] as-is with null rep bounds.
typedef SetsReps = ({
  int sets,
  int? repsMin,
  int? repsMax,
  String? repsText,
});

/// Setup tab: program start, rounding increment, prior-close main lifts.
class SetupInfo {
  final DateTime? programStart;
  final double roundingKg;
  final Map<String, double> priorClose; // squat / bench / deadlift -> kg

  const SetupInfo({
    this.programStart,
    this.roundingKg = 2.5,
    this.priorClose = const {},
  });
}

/// Latest top single for one lift, from the Progress tab.
class TopSingle {
  final String lift; // 'squat' | 'bench' | 'deadlift'
  final double weightKg;
  final double? rpe;
  final String? speed;
  final String weekLabel; // e.g. 'W3' or 'Oct 17 close'

  const TopSingle({
    required this.lift,
    required this.weightKg,
    this.rpe,
    this.speed,
    required this.weekLabel,
  });
}

/// Everything the preview screen shows before the user confirms.
class ImportPreview {
  final String programName;
  final List<ProgramWeek> weeks;
  final Map<String, DateTime> weekStartDates; // keyed by week tab title
  final MeetPlan? meetPlan;
  final SetupInfo? setup;
  final Map<String, TopSingle> topSingles; // keyed by lift
  final List<SkippedRow> skippedRows;

  /// Tabs that hit the 100-row read cap during fetch (A25) — rows past
  /// 100 in these tabs were never read. Shown as a warning in the
  /// import preview; the CSV path never truncates, so it stays empty.
  final List<String> truncatedTabs;

  const ImportPreview({
    required this.programName,
    required this.weeks,
    this.weekStartDates = const {},
    this.meetPlan,
    this.setup,
    this.topSingles = const {},
    this.skippedRows = const [],
    this.truncatedTabs = const [],
  });

  int get weekCount => weeks.length;
  int get dayCount => weeks.fold(0, (n, w) => n + w.days.length);
  int get exerciseCount =>
      weeks.fold(0, (n, w) => n + w.days.fold(0, (m, d) => m + d.exercises.length));
}

/// Result of a confirmed import, for the success screen.
class ImportResult {
  final String programId;
  final String programName;
  final int weekCount;
  final int dayCount;
  final int exerciseCount;
  final int recordsCreated;
  final bool profileMainLiftsUpdated;
  final List<SkippedRow> skippedRows;

  const ImportResult({
    required this.programId,
    required this.programName,
    required this.weekCount,
    required this.dayCount,
    required this.exerciseCount,
    required this.recordsCreated,
    required this.profileMainLiftsUpdated,
    this.skippedRows = const [],
  });
}

/// One cell range to write back: actuals only — the lifted weight (B),
/// Actual RPE (F), Bar speed (G), Status (H). Columns A, C, D, E are
/// never in a range. [range] is A1 notation with the tab quoted, e.g.
/// `'W3 Nov 9'!F7:H7`; [values] is one row per range row.
class SheetCellUpdate {
  final String range;
  final List<List<String>> values;

  const SheetCellUpdate({required this.range, required this.values});
}

/// Result of planning a write-back: the ranges to write, plus anything
/// that could not be matched (reported, never written blind).
class WriteBackPlan {
  final List<SheetCellUpdate> updates;
  final List<String> skipped;

  const WriteBackPlan({this.updates = const [], this.skipped = const []});
}

/// Column positions in a week tab, mapped from the header row by name —
/// never fixed. Defaults match the layout with "Prev wk" (W1+): A
/// Exercise, B Weight, C Prev wk, D Sets x reps, E Target RPE,
/// F Actual RPE, G Bar speed, H Status, I Notes. A sheet with the
/// weight in C (or any other shift) just works, because the header row
/// names the columns — the first week tab ("Oct 19 Deload") already
/// proved the point: it has no "Prev wk" column, so "Sets x reps"
/// sits in C there and in D everywhere else. The import parser and
/// both write-backs all read through this one mapping.
class WeekColumns {
  final int weight;
  final int setsReps;
  final int targetRpe;
  final int actualRpe;
  final int barSpeed;
  final int status;
  final int notes;

  const WeekColumns({
    this.weight = 1,
    this.setsReps = 3,
    this.targetRpe = 4,
    this.actualRpe = 5,
    this.barSpeed = 6,
    this.status = 7,
    this.notes = 8,
  });

  WeekColumns copyWith({
    int? weight,
    int? setsReps,
    int? targetRpe,
    int? actualRpe,
    int? barSpeed,
    int? status,
    int? notes,
  }) =>
      WeekColumns(
        weight: weight ?? this.weight,
        setsReps: setsReps ?? this.setsReps,
        targetRpe: targetRpe ?? this.targetRpe,
        actualRpe: actualRpe ?? this.actualRpe,
        barSpeed: barSpeed ?? this.barSpeed,
        status: status ?? this.status,
        notes: notes ?? this.notes,
      );

  /// Maps the columns from one header row ("Exercise | Weight | ...").
  /// Any column the header does not name keeps its default.
  static WeekColumns fromHeader(List<String> headerRow) {
    var cols = const WeekColumns();
    for (var c = 0; c < headerRow.length; c++) {
      switch (headerRow[c].trim().toLowerCase()) {
        case 'weight (kg)':
        case 'weight':
          cols = cols.copyWith(weight: c);
        case 'sets x reps':
          cols = cols.copyWith(setsReps: c);
        case 'target rpe':
          cols = cols.copyWith(targetRpe: c);
        case 'actual rpe':
          cols = cols.copyWith(actualRpe: c);
        case 'bar speed':
          cols = cols.copyWith(barSpeed: c);
        case 'status':
          cols = cols.copyWith(status: c);
        case 'notes':
          cols = cols.copyWith(notes: c);
      }
    }
    return cols;
  }

  /// Maps the columns from a week tab's rows: the header row is the
  /// one whose first cell says 'exercise'. Defaults when no header
  /// row is found.
  static WeekColumns fromRows(List<List<String>> rows) {
    for (final row in rows) {
      if (row.isNotEmpty && row[0].trim().toLowerCase() == 'exercise') {
        return fromHeader(row);
      }
    }
    return const WeekColumns();
  }
}

/// Spreadsheet import: Google Drive/Sheets reads + pure parsers for the
/// Iron Ascent training-log layout, then writes via [FirestoreService].
///
/// No spreadsheet ID is ever hardcoded: the user picks a spreadsheet from
/// Drive at import time. The pure `parse*` methods are unit-testable and
/// take no Firebase dependency.
class SheetImportService {
  final FirestoreService? _firestoreOverride;

  SheetImportService({FirestoreService? firestoreService})
      : _firestoreOverride = firestoreService;

  // Lazily built so constructing this service in a unit test never touches
  // Firebase (only the pure parsers are tested there).
  FirestoreService get _firestore => _firestoreOverride ?? FirestoreService();

  static const String _spreadsheetMime =
      'application/vnd.google-apps.spreadsheet';

  // ------------------------------------------------------------------
  // Google API reads
  // ------------------------------------------------------------------

  /// Lists the user's spreadsheets, most recently modified first.
  Future<List<SpreadsheetFileInfo>> listSpreadsheets(
    http.Client client,
  ) async {
    final api = drive.DriveApi(client);
    final result = await api.files.list(
      q: "mimeType='$_spreadsheetMime'",
      orderBy: 'modifiedTime desc',
      pageSize: 25,
      $fields: 'files(id,name,modifiedTime)',
    );
    return (result.files ?? [])
        .where((f) => f.id != null)
        .map((f) => SpreadsheetFileInfo(
              id: f.id!,
              name: f.name ?? 'Untitled spreadsheet',
              modifiedTime: f.modifiedTime,
            ))
        .toList();
  }

  /// A spreadsheet's last-modified time, for the two-way sync check
  /// (sheet -> app). Null when the file cannot be read.
  Future<DateTime?> fetchSpreadsheetModifiedTime(
    http.Client client,
    String spreadsheetId,
  ) async {
    final api = drive.DriveApi(client);
    // files.get is typed as Object in googleapis 14 (it can also return
    // the file's bytes); with the default metadata download it is a
    // File, so the cast is safe.
    final file = await api.files.get(spreadsheetId, $fields: 'modifiedTime')
        as drive.File;
    return file.modifiedTime;
  }

  /// True when the sheet changed since the app last knew about it.
  /// [storedIso] is the modifiedTime stored on the program at the last
  /// import (or the last acknowledged change); [current] is the sheet's
  /// modifiedTime now. Null on either side means "no baseline to
  /// compare" — never a change, so a program imported before this
  /// feature baselines silently instead of prompting on first open.
  /// Pure, so it is unit-testable.
  static bool sheetChanged(String? storedIso, DateTime? current) {
    if (storedIso == null || current == null) return false;
    final stored = DateTime.tryParse(storedIso);
    if (stored == null) return false;
    return stored.millisecondsSinceEpoch !=
        current.millisecondsSinceEpoch;
  }

  /// 0-based indexes of the day-header rows in a week tab (a weekday
  /// header with nothing else on the row, after the 'exercise' header
  /// row). The Nth header starts day N. Shared by the write-back
  /// planner and the weight write-back.
  static List<int> _dayHeaderRows(List<List<String>> rows) {
    final headerRows = <int>[];
    var inTable = false;
    for (var i = 0; i < rows.length; i++) {
      final a = _cell(rows[i], 0).trim();
      if (a.toLowerCase() == 'exercise') {
        inTable = true;
        continue;
      }
      if (!inTable) continue;
      if (_isDayHeader(a) && _rowOthersEmpty(rows[i])) headerRows.add(i);
    }
    return headerRows;
  }

  /// 0-based row index of [exerciseName] inside [day]'s section of
  /// [week]'s tab in [fetched], or null when the tab, the day section,
  /// or the exercise row is missing. Same day-section rules as the
  /// write-back planner. Used by the weight write-back (app -> sheet).
  /// Pure, so it is unit-testable.
  static int? findExerciseRow({
    required FetchedSpreadsheet fetched,
    required ProgramWeek week,
    required ProgramDay day,
    required String exerciseName,
  }) {
    final rows = fetched.tabs[week.title];
    if (rows == null) return null;
    final headerRows = _dayHeaderRows(rows);
    final dayIndex = week.days.indexOf(day);
    if (dayIndex < 0 || dayIndex >= headerRows.length) return null;
    final sectionStart = headerRows[dayIndex] + 1;
    final sectionEnd = dayIndex + 1 < headerRows.length
        ? headerRows[dayIndex + 1]
        : rows.length;
    final key = exerciseName.trim().toLowerCase();
    for (var i = sectionStart; i < sectionEnd; i++) {
      final a = _cell(rows[i], 0).trim();
      if (a.isEmpty) continue;
      if (a.toLowerCase() == key) return i;
    }
    return null;
  }

  /// Plans a prescription-weight write-back: the new target weight into
  /// column B of the exercise's row in the week tab. Unlike the results
  /// write-back, a typed value in B IS overwritten — the app is now the
  /// source of the new number. A formula in B is never touched (it
  /// would delete the sheet's own calculation, e.g. his beltless squat
  /// B9). Returns null when the row cannot be found, the weight is not
  /// a real number to write, or the week tab is missing from
  /// [formulaTabs] — only the formula-visible read can tell a formula
  /// (=...) from a typed number, so without it writing is not safe.
  /// Pure, so it is unit-testable.
  static SheetCellUpdate? buildWeightWrite({
    required FetchedSpreadsheet fetched,
    required Map<String, List<List<String>>> formulaTabs,
    required ProgramWeek week,
    required ProgramDay day,
    required String exerciseName,
    required double weightKg,
  }) {
    if (weightKg <= 0) return null;
    final rowIndex = findExerciseRow(
      fetched: fetched,
      week: week,
      day: day,
      exerciseName: exerciseName,
    );
    if (rowIndex == null) return null;
    // The weight column comes from the tab's header row, not from a
    // fixed letter: a sheet with the weight in C writes to C.
    final rows = fetched.tabs[week.title];
    final cols =
        rows == null ? const WeekColumns() : WeekColumns.fromRows(rows);
    final formulaRows = formulaTabs[week.title];
    if (formulaRows == null || rowIndex >= formulaRows.length) return null;
    final weightCell = _cell(formulaRows[rowIndex], cols.weight).trim();
    if (weightCell.startsWith('=')) return null; // formula — never touch
    final sheetRow = rowIndex + 1;
    return SheetCellUpdate(
      range:
          '${_quoteTab(week.title)}!${_colLetter(cols.weight)}$sheetRow',
      values: [
        [_fmtNumber(weightKg)],
      ],
    );
  }

  /// Fetches a spreadsheet's tab titles, then values A1:Z100 per tab
  /// (values only, no formatting). Z, not I: a sheet whose columns
  /// shifted right of I still needs its header row read.
  /// A25: a tab that comes back with exactly 100 rows may have more
  /// below row 100 — the API only returns what the range asked for,
  /// and trailing empty rows are trimmed, so 100 rows means "at the
  /// cap". Those tabs are recorded in [FetchedSpreadsheet.truncatedTabs]
  /// so the preview can warn instead of silently importing a partial
  /// sheet.
  Future<FetchedSpreadsheet> fetchSpreadsheet(
    http.Client client,
    String spreadsheetId,
  ) async {
    final api = sheets.SheetsApi(client);
    final meta = await api.spreadsheets.get(spreadsheetId);
    final title = meta.properties?.title ?? 'Imported Program';
    final tabTitles = (meta.sheets ?? [])
        .map((s) => s.properties?.title ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    final tabs = <String, List<List<String>>>{};
    final truncatedTabs = <String>[];
    for (final tab in tabTitles) {
      final range = "'$tab'!A1:Z100";
      final values = await api.spreadsheets.values.get(spreadsheetId, range);
      final rows = _stringRows(values.values);
      if (rows.length >= 100) truncatedTabs.add(tab);
      tabs[tab] = rows;
    }
    return FetchedSpreadsheet(
      title: title,
      tabs: tabs,
      truncatedTabs: truncatedTabs,
    );
  }

  /// Reads the given tabs with formulas visible (valueRenderOption
  /// FORMULA): a formula cell comes back as its "=..." text instead of
  /// its computed value, so the write-back planner can tell a formula
  /// from a blank cell — a formula that evaluates to "" looks empty in
  /// the normal read, and writing over it would delete it. Only used
  /// for write-back planning, never for import.
  Future<Map<String, List<List<String>>>> fetchTabFormulas(
    http.Client client,
    String spreadsheetId,
    List<String> tabTitles,
  ) async {
    final api = sheets.SheetsApi(client);
    final out = <String, List<List<String>>>{};
    for (final tab in tabTitles) {
      final range = "'$tab'!A1:Z100";
      final values = await api.spreadsheets.values.get(
        spreadsheetId,
        range,
        valueRenderOption: 'FORMULA',
      );
      out[tab] = _stringRows(values.values);
    }
    return out;
  }

  static List<List<String>> _stringRows(List<List<Object?>>? values) {
    if (values == null) return [];
    return values
        .map((row) => row.map((c) => c?.toString() ?? '').toList())
        .toList();
  }

  // ------------------------------------------------------------------
  // Pure parsing
  // ------------------------------------------------------------------

  /// Week-tab start date from the "Week starting" row (row 2 in the real
  /// sheet). [year] fills in when the cell has no year ("Nov 9").
  static DateTime? parseWeekStartDate(
    List<List<String>> rows, {
    int year = 2026,
  }) {
    for (final row in rows) {
      if (_cell(row, 0).trim().toLowerCase() == 'week starting') {
        return _parseDate(_cell(row, 1), year: year);
      }
    }
    return null;
  }

  /// Parses one week tab into a [ProgramWeek].
  ///
  /// Layout: row 1 title, row 2 "Week starting", row 5 header
  /// (Exercise | Weight | Prev wk | Sets x reps | Target RPE | Actual RPE |
  /// Bar speed | Status | Notes), day header rows (text only in A, e.g.
  /// "Mon Nov 9 · D1 · Squat + bench volume · ~75 min" or "Fri Nov 13 ·
  /// Rest"), then exercise rows. Rows that cannot be interpreted are
  /// appended to [skippedRows] (with 1-based row numbers) instead of
  /// throwing.
  static ProgramWeek parseWeekTab(
    String title,
    List<List<String>> rows, {
    int weekIndex = 0,
    List<SkippedRow>? skippedRows,
  }) {
    final days = <ProgramDay>[];
    ProgramDay? currentDay;
    final exerciseCounts = <String, int>{};

    // Column positions come from the header row (see WeekColumns),
    // not fixed: the first week tab ("Oct 19 Deload") has no "Prev wk"
    // column, so "Sets x reps" sits in C there and in D everywhere
    // else — and a sheet with the weight in C just works.
    var cols = const WeekColumns();

    void addSkipped(int rowNumber, String reason, [String? text]) {
      skippedRows?.add(SkippedRow(
        tab: title,
        row: rowNumber,
        reason: reason,
        text: text,
      ));
    }

    ProgramDay newDay(String dayTitle, int index) {
      final day = ProgramDay(
        id: 'day_$index',
        title: dayTitle.trim(),
        dayIndex: index,
        exercises: [],
      );
      days.add(day);
      return day;
    }

    bool inTable = false;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNumber = i + 1;
      final a = _cell(row, 0).trim();
      final b = _cell(row, cols.weight).trim();
      final d = _cell(row, cols.setsReps).trim();
      final e = _cell(row, cols.targetRpe).trim();
      final notes = _cell(row, cols.notes).trim();
      final othersEmpty =
          row.skip(1).every((cell) => cell.trim().isEmpty);

      if (a.isEmpty && othersEmpty) continue; // blank row

      // Header row: marks the start of the exercise table, and maps
      // the columns by name (tabs differ: the first tab has no
      // "Prev wk" column, so everything after Weight shifts left).
      if (a.toLowerCase() == 'exercise') {
        cols = WeekColumns.fromHeader(row);
        inTable = true;
        continue;
      }
      if (!inTable) continue; // title / "Week starting" / wave note rows

      // Day header: text only in A, starting with a weekday
      // ("Mon Nov 9 · D1 · ...", "Fri Nov 13 · Rest").
      if (othersEmpty && _isDayHeader(a)) {
        currentDay = newDay(a, days.length);
        continue;
      }

      // Lone-A row: a note under a Rest day (e.g. "Full rest. A walk is
      // fine."). Any other lone-A row has no values to import, so it is
      // reported as skipped rather than silently attached or dropped.
      if (othersEmpty) {
        if (currentDay == null) {
          addSkipped(rowNumber, 'Note row "$a" has no day above it.', a);
        } else if (currentDay.exercises.isEmpty &&
            currentDay.title.contains('Rest')) {
          final updated = ProgramDay(
            id: currentDay.id,
            title: '${currentDay.title} — $a',
            dayIndex: currentDay.dayIndex,
            exercises: currentDay.exercises,
          );
          days[days.length - 1] = updated;
          currentDay = updated;
        } else {
          addSkipped(
            rowNumber,
            'Row "$a" has no weight, sets x reps, or target RPE.',
            a,
          );
        }
        continue;
      }

      // Exercise row: needs a name plus at least one prescription cell.
      if (a.isEmpty) {
        addSkipped(
          rowNumber,
          'Row has weight/sets values but no exercise name.',
          row
              .where((c) => c.trim().isNotEmpty)
              .join(' · '),
        );
        continue;
      }
      if (b.isEmpty && d.isEmpty && e.isEmpty) {
        addSkipped(
          rowNumber,
          'Exercise "$a" has no weight, sets x reps, or target RPE.',
          a,
        );
        continue;
      }

      currentDay ??= newDay('Day ${days.length + 1}', days.length);
      final parsed = parseSetsReps(d);
      final baseId = _slug(a);
      final count = (exerciseCounts[baseId] ?? 0) + 1;
      exerciseCounts[baseId] = count;
      final exerciseId = count == 1 ? baseId : '$baseId-$count';
      final superset = RegExp(r'Superset\s+([A-Za-z]\d+)', caseSensitive: false)
          .firstMatch(notes)
          ?.group(1);
      final exercise = ProgramExercise(
        exerciseId: exerciseId,
        name: a,
        sets: parsed.sets,
        repsMin: parsed.repsMin,
        repsMax: parsed.repsMax,
        repsText: parsed.repsText,
        targetWeightKg: _parseDouble(b),
        targetRpe: e.isEmpty ? null : e,
        notes: notes,
        supersetGroup: superset,
      );
      final exercises = List<ProgramExercise>.of(currentDay.exercises)
        ..add(exercise);
      final updated = ProgramDay(
        id: currentDay.id,
        title: currentDay.title,
        dayIndex: currentDay.dayIndex,
        exercises: exercises,
      );
      days[days.length - 1] = updated;
      currentDay = updated;
    }

    return ProgramWeek(
      id: _slug(title),
      title: title,
      weekIndex: weekIndex,
      days: days,
    );
  }

  /// Parses a "Sets x reps" cell.
  /// `3 x 10-12` -> (3, 10, 12); `1 x 1` -> (1, 1, 1);
  /// `1 x 25-30 min` / `2 x 30 s/side` -> sets only, repsText is the
  /// part after the "x" ("25-30 min" / "30 s/side"). The sets count
  /// lives in [sets], never inside [repsText] — the screens print
  /// "<sets> × <repsText>", so keeping the whole cell would print the
  /// sets twice ("2 × 2 x 8-10").
  static SetsReps parseSetsReps(String raw) {
    final text = raw.trim().replaceAll('×', 'x');
    if (text.isEmpty) return (sets: 1, repsMin: null, repsMax: null, repsText: null);
    final match = RegExp(r'^(\d+)\s*x\s*(.+)$', caseSensitive: false).firstMatch(text);
    if (match == null) {
      return (sets: 1, repsMin: null, repsMax: null, repsText: text);
    }
    final sets = int.tryParse(match.group(1)!) ?? 1;
    final inner = match.group(2)!.trim();
    final range = RegExp(r'^(\d+)\s*-\s*(\d+)$').firstMatch(inner);
    if (range != null) {
      return (
        sets: sets,
        repsMin: int.parse(range.group(1)!),
        repsMax: int.parse(range.group(2)!),
        repsText: inner,
      );
    }
    final single = int.tryParse(inner);
    if (single != null) {
      return (sets: sets, repsMin: single, repsMax: single, repsText: inner);
    }
    return (sets: sets, repsMin: null, repsMax: null, repsText: inner);
  }

  /// Parses the Setup tab: program start, rounding increment, and the
  /// prior-close main lifts (Squat / Bench / Deadlift rows under the
  /// "Prior close" label).
  static SetupInfo parseSetup(List<List<String>> rows) {
    DateTime? programStart;
    var roundingKg = 2.5;
    final priorClose = <String, double>{};
    var seenPriorClose = false;

    for (final row in rows) {
      final a = _cell(row, 0).trim();
      final b = _cell(row, 1).trim();
      final lower = a.toLowerCase();
      if (lower.contains('program start')) {
        programStart = _parseDate(b, year: 2026);
      } else if (lower.contains('rounding increment')) {
        roundingKg = _parseDouble(b.replaceAll('kg', '')) ?? 2.5;
      } else if (lower.contains('prior close')) {
        seenPriorClose = true;
      } else if (seenPriorClose) {
        final lift = _liftKey(a);
        // Only exact lift rows with a plain weight count: the percentages
        // table ("70%") and D1 loads ("Squat beltless") must not match.
        if (lift != null && !b.contains('%')) {
          final weight = _parseDouble(b);
          if (weight != null && weight >= 50) priorClose[lift] = weight;
        }
      }
    }
    return SetupInfo(
      programStart: programStart,
      roundingKg: roundingKg,
      priorClose: priorClose,
    );
  }

  /// Parses the Meet tab's "Attempt plan" table into a [MeetPlan].
  /// The "On the day" log below it is ignored (filled in on the day).
  static MeetPlan parseMeet(
    List<List<String>> rows, {
    int year = 2026,
  }) {
    DateTime? date;
    final attempts = <MeetAttempt>[];
    var inAttemptTable = false;

    for (final row in rows) {
      final a = _cell(row, 0).trim();
      final lower = a.toLowerCase();
      // Meet date from the tab title row, e.g. "Meet Jan 16".
      if (date == null) {
        final m = RegExp(r'([A-Za-z]{3,9})\s+(\d{1,2})').firstMatch(a);
        if (m != null) date = _monthDay(m.group(1)!, int.parse(m.group(2)!), year);
      }
      if (lower.contains('on the day')) break; // log table: not imported
      if (lower == 'lift' || lower.contains('attempt plan')) {
        inAttemptTable = true;
        continue;
      }
      if (!inAttemptTable) continue;
      final lift = _liftKey(a);
      if (lift == null) continue;
      attempts.add(MeetAttempt(
        lift: lift,
        projectedMaxKg: _parseDouble(_cell(row, 1)),
        openerKg: _parseDouble(_cell(row, 2)),
        secondKg: _parseDouble(_cell(row, 3)),
        thirdLowKg: _parseDouble(_cell(row, 4)),
        thirdHighKg: _parseDouble(_cell(row, 5)),
        lastWarmUpKg: _parseDouble(_cell(row, 6)),
      ));
    }
    return MeetPlan(date: date, attempts: attempts);
  }

  /// Parses the Progress tab's "D4 top singles" table: the latest
  /// non-empty row per lift (sheet order wins — later rows are newer).
  /// Returns one [TopSingle] per lift that has a weight, keyed by lift.
  static Map<String, TopSingle> parseProgress(List<List<String>> rows) {
    final latest = <String, TopSingle>{};
    var inTable = false;
    for (final row in rows) {
      final a = _cell(row, 0).trim();
      if (a.toLowerCase() == 'week') {
        inTable = true;
        continue;
      }
      if (!inTable || a.isEmpty) continue;
      if (a.toLowerCase().contains('d4 top singles')) continue;
      final lifts = ['squat', 'bench', 'deadlift'];
      final colBase = [1, 4, 7]; // weight col per lift; RPE +1, speed +2
      for (var k = 0; k < lifts.length; k++) {
        final weight = _parseDouble(_cell(row, colBase[k]));
        if (weight == null) continue;
        final rpeRaw = _cell(row, colBase[k] + 1).trim();
        latest[lifts[k]] = TopSingle(
          lift: lifts[k],
          weightKg: weight,
          rpe: _parseDouble(rpeRaw),
          speed: _cell(row, colBase[k] + 2).trim().isEmpty
              ? null
              : _cell(row, colBase[k] + 2).trim(),
          weekLabel: a,
        );
      }
    }
    return latest;
  }

  // ------------------------------------------------------------------
  // Preview + import orchestration
  // ------------------------------------------------------------------

  /// Program name from a spreadsheet title: "Iron Ascent Training Log"
  /// becomes "Iron Ascent".
  static String programNameFromTitle(String title) {
    var name = title.trim();
    const suffix = ' training log';
    if (name.toLowerCase().endsWith(suffix)) {
      name = name.substring(0, name.length - suffix.length).trim();
    }
    return name.isEmpty ? 'Imported Program' : name;
  }

  /// Turns fetched spreadsheet data into a preview (pure, no Firebase).
  /// Week tabs are tabs containing the Exercise header; Setup / Meet /
  /// Progress tabs are parsed by role, not by title, so a renamed tab
  /// still works.
  static ImportPreview previewSpreadsheet(FetchedSpreadsheet fetched) {
    final skipped = <SkippedRow>[];
    final weeks = <ProgramWeek>[];
    final weekStartDates = <String, DateTime>{};
    SetupInfo? setup;
    MeetPlan? meetPlan;
    Map<String, TopSingle> topSingles = {};

    // Setup first: its year anchors the week start dates.
    final setupRows = _findTab(fetched, ['setup']);
    if (setupRows != null) setup = parseSetup(setupRows);
    final year = setup?.programStart?.year ?? 2026;

    for (final entry in fetched.tabs.entries) {
      final tabTitle = entry.key;
      final rows = entry.value;
      final lower = tabTitle.toLowerCase();
      if (lower == 'setup' || lower.contains('progress')) {
        if (lower.contains('progress')) {
          topSingles = parseProgress(rows);
        }
        continue;
      }
      if (lower.contains('meet')) {
        meetPlan = parseMeet(rows, year: year);
        continue;
      }
      if (!_hasExerciseHeader(rows)) continue; // not a week tab
      final start = parseWeekStartDate(rows, year: year);
      if (start != null) weekStartDates[tabTitle] = start;
      weeks.add(parseWeekTab(
        tabTitle,
        rows,
        weekIndex: weeks.length,
        skippedRows: skipped,
      ));
    }

    return ImportPreview(
      programName: programNameFromTitle(fetched.title),
      weeks: weeks,
      weekStartDates: weekStartDates,
      meetPlan: meetPlan,
      setup: setup,
      topSingles: topSingles,
      skippedRows: skipped,
      truncatedTabs: fetched.truncatedTabs,
    );
  }

  /// Full flow: fetch -> parse -> write. Returns the import summary.
  /// [coach] writes to the coach's own program list instead of the
  /// training list — an import done on the coach side lands there and
  /// never shows up in training.
  Future<ImportResult> importToFirestore({
    required String uid,
    required String spreadsheetId,
    required http.Client client,
    bool coach = false,
  }) async {
    final fetched = await fetchSpreadsheet(client, spreadsheetId);
    // The sheet's modifiedTime at import: the baseline the two-way
    // sync check compares against on the next Program open.
    final modifiedTime =
        await fetchSpreadsheetModifiedTime(client, spreadsheetId);
    return importParsed(
      uid: uid,
      preview: previewSpreadsheet(fetched),
      spreadsheetId: spreadsheetId,
      sourceModifiedTime: modifiedTime?.toIso8601String(),
      coach: coach,
    );
  }

  /// Merges a fresh sheet parse onto the program already stored, if
  /// any. The sheet owns the weeks and the meet plan; everything the
  /// app owns stays: the id, description, active flag, created date,
  /// the sheet link — and the moved days. A re-import must never
  /// silently un-move a day: updating a number in the sheet used to
  /// rebuild the program without its moves, so a moved or mixed day
  /// snapped back to its scheduled date (Nov 18). A move whose day
  /// no longer exists in the new weeks is kept verbatim — it is
  /// inert (daysForDate only looks up days that exist) and comes
  /// back if the day returns. A coach import never activates the
  /// program — coach programs are never active. Pure, so it is
  /// unit-testable.
  static Program mergeImportedProgram({
    required String uid,
    required ImportPreview preview,
    Program? existing,
    required bool isFirstProgram,
    String? spreadsheetId,
    String? sourceModifiedTime,
    bool coach = false,
  }) {
    return Program(
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      userId: uid,
      name: preview.programName,
      description: existing?.description,
      weeks: preview.weeks,
      meetPlan: preview.meetPlan,
      isActive: coach ? false : (existing?.isActive ?? isFirstProgram),
      createdAt: existing?.createdAt ?? DateTime.now(),
      dayMoves: existing?.dayMoves ?? const {},
      sourceSpreadsheetId: spreadsheetId ?? existing?.sourceSpreadsheetId,
      sourceModifiedTime: sourceModifiedTime ?? existing?.sourceModifiedTime,
      // A11: the coach-sent stamp survives a re-import — the sheet
      // owns the weeks, not the attribution. Dropping these wiped
      // the "Sent by" label on every re-import of a coach-sent program.
      fromCoachUid: existing?.fromCoachUid,
      fromCoachName: existing?.fromCoachName,
      sentToClientIds: existing?.sentToClientIds ?? const [],
    );
  }

  /// Writes an already-parsed preview (Sheets path and CSV path share it).
  /// Re-import replaces the program's weeks and meet plan but keeps its id;
  /// records are refreshed from the Progress tab; prior-close lifts are
  /// offered to the profile only when its main lifts are empty.
  /// The spreadsheet id is stored on the program so write-back knows
  /// which sheet to write to; a CSV re-import (no id) keeps the old one.
  /// A coach import ([coach] true) writes to the coach's own list and
  /// touches nothing else: the sheet is a program template for
  /// clients, not the coach's training log, so no records are created
  /// and the profile lifts are left alone.
  Future<ImportResult> importParsed({
    required String uid,
    required ImportPreview preview,
    String? spreadsheetId,
    String? sourceModifiedTime,
    bool coach = false,
  }) async {
    final existing = coach
        ? await _firestore.getCoachPrograms(uid)
        : await _firestore.getPrograms(uid);
    // A14: match on the spreadsheet id first — it is stable across
    // renames, so a program renamed in-app still merges instead of
    // duplicating. Name match is only the fallback for imports with
    // no id (CSV) or programs imported before the id was stored.
    Program? found;
    if (spreadsheetId != null && spreadsheetId.isNotEmpty) {
      final byId =
          existing.where((p) => p.sourceSpreadsheetId == spreadsheetId);
      if (byId.isNotEmpty) found = byId.first;
    }
    if (found == null) {
      final byName = existing.where(
        (p) => p.name.toLowerCase() == preview.programName.toLowerCase(),
      );
      if (byName.isNotEmpty) found = byName.first;
    }

    final program = mergeImportedProgram(
      uid: uid,
      preview: preview,
      existing: found,
      isFirstProgram: existing.isEmpty,
      spreadsheetId: spreadsheetId,
      sourceModifiedTime: sourceModifiedTime,
      coach: coach,
    );
    if (coach) {
      await _firestore.saveCoachProgram(uid, program);
    } else {
      await _firestore.saveProgram(uid, program);
    }

    // Records from the Progress tab's latest singles per lift —
    // training only. A coach import must not write the client's
    // numbers into the coach's own records.
    var recordsCreated = 0;
    if (!coach) {
      // A15: keep the max — re-importing an older sheet version must
      // never downgrade a true PR. The stored record wins on weight
      // (and keeps its date/setId/video); the sheet single only wins
      // when it is heavier, as the runner's finish-time PR check
      // already does.
      final storedRecords = await _firestore.getRecords(uid);
      const liftOrder = ['squat', 'bench', 'deadlift'];
      for (final lift in liftOrder) {
        final single = preview.topSingles[lift];
        if (single == null) continue;
        final stored = storedRecords[lift];
        final newE1rm = StrengthMath.e1rm(single.weightKg, 1);
        final bestWeightKg =
            math.max(stored?.bestWeightKg ?? 0, single.weightKg);
        final bestE1rmKg = math.max(stored?.bestE1rmKg ?? 0, newE1rm);
        final storedWins =
            stored != null && stored.bestWeightKg >= single.weightKg;
        await _firestore.saveRecord(
          uid,
          Record(
            exerciseId: lift,
            bestWeightKg: bestWeightKg,
            bestE1rmKg: bestE1rmKg,
            date: storedWins
                ? stored.date
                : _resolveSingleDate(single, preview),
            setId: storedWins ? stored.setId : null,
            videoUrl: storedWins ? stored.videoUrl : null,
          ),
        );
        recordsCreated++;
      }
    }

    // Prior-close lifts -> profile main lifts, only when they are empty
    // — and only for a training import, for the same reason as above.
    var profileUpdated = false;
    final priorClose = preview.setup?.priorClose ?? {};
    if (!coach && priorClose.isNotEmpty) {
      final profile = await _firestore.getProfile(uid);
      if (profile != null) {
        final hasLifts = ['squat', 'bench', 'deadlift']
            .any((lift) => (profile.mainLifts[lift] ?? 0) > 0);
        if (!hasLifts) {
          await _firestore.saveProfile(profile.copyWith(
            mainLifts: Map<String, double>.from(priorClose),
          ));
          profileUpdated = true;
        }
      }
    }

    return ImportResult(
      programId: program.id,
      programName: program.name,
      weekCount: preview.weekCount,
      dayCount: preview.dayCount,
      exerciseCount: preview.exerciseCount,
      recordsCreated: recordsCreated,
      profileMainLiftsUpdated: profileUpdated,
      skippedRows: preview.skippedRows,
    );
  }

  // ------------------------------------------------------------------
  // Write-back (actuals only, never prescription)
  // ------------------------------------------------------------------

  /// Plans the write-back for a finished session: which cells change and
  /// which exercises could not be matched. Pure — no Firebase, no HTTP —
  /// so it is unit-testable.
  ///
  /// A mixed session writes each day's sets to that day's own rows:
  /// day 2's RPE / speed / status land on day 2's section, day 3's on
  /// day 3's — each set carries the day it came from, so the split is
  /// exact even when both days have the same exercise.
  ///
  /// Week-tab rows: Actual RPE, Bar speed, Status on the matching
  /// exercise row, plus the weight. RPE, bar speed and weight come from
  /// the heaviest completed set; Status is Done when every prescribed
  /// set was completed, Partial otherwise. The columns come from the
  /// tab's header row (see [WeekColumns]) — a sheet with the weight in
  /// C writes to C.
  /// **Only-if-empty: a target cell is written only when it is
  /// currently blank** — a value already typed in, or a formula, is
  /// never overwritten. The check is per cell, not per row, so a filled
  /// RPE still leaves the speed and status cells open. [formulaTabs] is
  /// the same tabs read with formulas visible (see [fetchTabFormulas]);
  /// without it, occupancy is judged from the formatted read, where a
  /// formula only shows its computed value. Columns A, C, D, E are
  /// never in a range.
  ///
  /// Progress tab: only for D4 days, and only a single that beats the
  /// logged best for that week is recorded (weight, RPE, speed) — that
  /// "only if better" rule stays, because the tab's job is tracking
  /// improving bests. A cell that holds a formula is never overwritten.
  static WriteBackPlan buildWriteBack({
    required FetchedSpreadsheet fetched,
    Map<String, List<List<String>>>? formulaTabs,
    required Program program,
    required WorkoutSession session,
  }) {
    final updates = <SheetCellUpdate>[];
    final skipped = <String>[];

    // Every day this session covers: the primary day plus any
    // mixed-in days. A mixed session writes each day's sets to that
    // day's own rows — day 2's RPE / speed / status land on day 2's
    // section, day 3's on day 3's — each in its own week tab when the
    // move crossed a week. Sets saved before moves existed carry no
    // day tag and belong to the primary day.
    final covered = <({
      ProgramWeek week,
      ProgramDay day,
      List<SessionSet> sets,
    })>[];
    ProgramWeek? findWeek(String? weekId) {
      for (final w in program.weeks) {
        if (w.id == weekId) return w;
      }
      return null;
    }

    ProgramDay? findDay(ProgramWeek week, String? dayId) {
      for (final d in week.days) {
        if (d.id == dayId) return d;
      }
      return null;
    }

    final primaryWeek = findWeek(session.weekId);
    final primaryDay =
        primaryWeek == null ? null : findDay(primaryWeek, session.dayId);
    if (primaryDay != null) {
      covered.add((
        week: primaryWeek!,
        day: primaryDay,
        sets: session.sets
            .where((s) => (s.dayId ?? session.dayId) == primaryDay.id)
            .toList(),
      ));
    }
    for (final key in session.mixedDayKeys) {
      final parsed = parseDayKey(key);
      if (parsed == null) continue;
      final week = findWeek(parsed.weekId);
      final day = week == null ? null : findDay(week, parsed.dayId);
      if (day == null) continue;
      covered.add((
        week: week!,
        day: day,
        sets: session.sets.where((s) => s.dayId == day.id).toList(),
      ));
    }
    if (covered.isEmpty) {
      skipped.add('Session day is not part of the imported program.');
      return WriteBackPlan(updates: updates, skipped: skipped);
    }

    for (final c in covered) {
      final week = c.week;
      final day = c.day;
      final rows = fetched.tabs[week.title];
      if (rows == null) {
        skipped.add(
          'Week tab "${week.title}" is not in the spreadsheet.',
        );
        continue;
      }
      // Column positions come from the tab's header row (see
      // WeekColumns) — a sheet with the weight in C writes to C.
      final weekCols = WeekColumns.fromRows(rows);

    // Day sections: the Nth day header row starts day N (same rules as
    // the parser — a weekday header with nothing else on the row).
    final headerRows = _dayHeaderRows(rows);
    final dayIndex = week.days.indexOf(day);
    if (dayIndex < 0 || dayIndex >= headerRows.length) {
      skipped.add('Day "${day.title}" was not found in "${week.title}".');
      continue;
    }
    final sectionStart = headerRows[dayIndex] + 1;
    final sectionEnd = dayIndex + 1 < headerRows.length
        ? headerRows[dayIndex + 1]
        : rows.length;

    // Completed sets grouped by exercise name — this day's sets only.
    final byExercise = <String, List<SessionSet>>{};
    final displayName = <String, String>{};
    for (final set in c.sets) {
      if (!set.completed) continue;
      final key = set.name.trim().toLowerCase();
      (byExercise[key] ??= []).add(set);
      displayName[key] = set.name.trim();
    }

    for (final entry in byExercise.entries) {
      final sets = entry.value;
      int? rowIndex;
      for (var i = sectionStart; i < sectionEnd; i++) {
        final a = _cell(rows[i], 0).trim();
        if (a.isEmpty) continue;
        if (a.toLowerCase() == entry.key) {
          rowIndex = i;
          break;
        }
      }
      if (rowIndex == null) {
        skipped.add(
          'Exercise "${displayName[entry.key]}" was not found in "${week.title}" — not written back.',
        );
        continue;
      }
      var prescribed = 0;
      for (final ex in day.exercises) {
        if (ex.name.trim().toLowerCase() == entry.key) prescribed = ex.sets;
      }
      // Heaviest completed set carries the RPE / bar speed.
      var top = sets.first;
      for (final s in sets) {
        if (s.weightKg > top.weightKg ||
            (s.weightKg == top.weightKg && s.setIndex > top.setIndex)) {
          top = s;
        }
      }
      final row = rows[rowIndex];
      // Occupancy for this row: the formula-visible read if we have it
      // (a formula evaluating to "" still counts as occupied), else the
      // formatted read (a formula then only shows its computed value).
      final formulaRows = formulaTabs?[week.title];
      final formulaRow =
          formulaRows != null && rowIndex < formulaRows.length
              ? formulaRows[rowIndex]
              : null;
      bool occupied(int col) {
        final seen =
            formulaRow == null ? _cell(row, col) : _cell(formulaRow, col);
        return seen.trim().isNotEmpty;
      }

      final newH = prescribed > 0 && sets.length >= prescribed
          ? 'Done'
          : 'Partial';
      // Column index -> value to write. Null means the session has no
      // value for that cell (no RPE / no bar speed on the top set, or
      // a bodyweight set with no weight to record).
      final candidates = <int, String?>{
        // Weight column (from the header row): the heaviest completed
        // set's weight — only when it is blank. A formula or a typed
        // value there is never overwritten, so the prescription stays
        // intact.
        weekCols.weight:
            top.weightKg > 0 ? _fmtNumber(top.weightKg) : null,
        weekCols.actualRpe:
            top.rpe == null ? null : _fmtNumber(top.rpe!),
        weekCols.barSpeed: top.barSpeed == null || top.barSpeed!.isEmpty
            ? null
            : top.barSpeed!,
        weekCols.status: newH,
      };
      final toWrite = <int, String>{};
      var leftAlone = false;
      for (final candidate in candidates.entries) {
        if (candidate.value == null) continue;
        if (occupied(candidate.key)) {
          leftAlone = true;
          continue;
        }
        toWrite[candidate.key] = candidate.value!;
      }
      if (toWrite.isEmpty) {
        if (leftAlone) {
          skipped.add(
            '"${displayName[entry.key]}" already had its actuals filled '
            'in — left alone.',
          );
        }
        continue;
      }
      // Group contiguous columns into one range each, so a filled RPE
      // still leaves G:H open and a filled speed splits F and H apart.
      // Hoisted here: the local function below captures them, and a
      // captured nullable loses its earlier null-check promotion.
      final weekTitle = week.title;
      final sheetRow = rowIndex + 1;
      final cols = toWrite.keys.toList()..sort();
      var start = cols.first;
      var prev = cols.first;
      void flush(int end) {
        final range =
            '${_quoteTab(weekTitle)}!${_colLetter(start)}$sheetRow'
            ':${_colLetter(end)}$sheetRow';
        final values = [
          for (var c = start; c <= end; c++) toWrite[c]!,
        ];
        updates.add(SheetCellUpdate(range: range, values: [values]));
      }

      for (var i = 1; i < cols.length; i++) {
        if (cols[i] == prev + 1) {
          prev = cols[i];
        } else {
          flush(prev);
          start = cols[i];
          prev = cols[i];
        }
      }
      flush(prev);
    }

    } // for (final c in covered)

    // Progress tab: only when a covered day is a D4 day, and only a
    // single that beats the logged best for that week is recorded.
    for (final c in covered) {
      if (c.day.title.toLowerCase().contains('d4')) {
        _planProgressUpdates(
          fetched,
          formulaTabs,
          c.week,
          session,
          updates,
          skipped,
        );
      }
    }

    return WriteBackPlan(updates: updates, skipped: skipped);
  }

  static void _planProgressUpdates(
    FetchedSpreadsheet fetched,
    Map<String, List<List<String>>>? formulaTabs,
    ProgramWeek week,
    WorkoutSession session,
    List<SheetCellUpdate> updates,
    List<String> skipped,
  ) {
    MapEntry<String, List<List<String>>>? progressTab;
    for (final entry in fetched.tabs.entries) {
      if (entry.key.toLowerCase().contains('progress')) {
        progressTab = entry;
        break;
      }
    }
    if (progressTab == null) {
      skipped.add(
        'No Progress tab in the spreadsheet — top singles not written back.',
      );
      return;
    }
    final rows = progressTab.value;
    final tabTitle = progressTab.key;
    var headerIndex = -1;
    for (var i = 0; i < rows.length; i++) {
      if (_cell(rows[i], 0).trim().toLowerCase() == 'week') {
        headerIndex = i;
        break;
      }
    }
    if (headerIndex < 0) {
      skipped.add(
        'Progress tab has no "Week" header — top singles not written back.',
      );
      return;
    }
    final weekToken = RegExp(r'^W\d+', caseSensitive: false)
        .firstMatch(week.title.trim())
        ?.group(0);
    if (weekToken == null) {
      skipped.add(
        'Week "${week.title}" has no W-number — top singles not written back.',
      );
      return;
    }
    var rowIndex = -1;
    for (var i = headerIndex + 1; i < rows.length; i++) {
      if (_cell(rows[i], 0).trim().toLowerCase() ==
          weekToken.toLowerCase()) {
        rowIndex = i;
        break;
      }
    }
    if (rowIndex < 0) {
      skipped.add(
        'No "$weekToken" row in Progress — top singles not written back.',
      );
      return;
    }
    const lifts = ['squat', 'bench', 'deadlift'];
    const colBase = [1, 4, 7]; // weight col per lift; RPE +1, speed +2
    final row = rows[rowIndex];
    // The formula-visible read for this Progress row, if we have it: a
    // cell holding a formula is protected even when the new single
    // beats the logged best.
    final formulaRows = formulaTabs?[tabTitle];
    final formulaRow = formulaRows != null && rowIndex < formulaRows.length
        ? formulaRows[rowIndex]
        : null;
    bool holdsFormula(int col) =>
        formulaRow != null &&
        _cell(formulaRow, col).trim().startsWith('=');
    for (var k = 0; k < lifts.length; k++) {
      SessionSet? best;
      for (final s in session.sets) {
        if (!s.completed || s.reps != 1) continue;
        final isLift = s.exerciseId == lifts[k] ||
            s.name.trim().toLowerCase() == lifts[k];
        if (!isLift) continue;
        if (best == null || s.weightKg > best.weightKg) best = s;
      }
      if (best == null) continue;
      if (holdsFormula(colBase[k]) ||
          holdsFormula(colBase[k] + 1) ||
          holdsFormula(colBase[k] + 2)) {
        skipped.add(
          'Progress "$weekToken" ${lifts[k]} holds a formula — left alone.',
        );
        continue;
      }
      // Only a single that beats the logged best for that week is
      // recorded — a lighter single must never overwrite a PR.
      final existing = _parseDouble(_cell(row, colBase[k]));
      if (existing != null && best.weightKg <= existing) continue;
      final weight = _fmtNumber(best.weightKg);
      final rpe = best.rpe == null
          ? _cell(row, colBase[k] + 1)
          : _fmtNumber(best.rpe!);
      final speed = best.barSpeed == null || best.barSpeed!.isEmpty
          ? _cell(row, colBase[k] + 2)
          : best.barSpeed!;
      final current = [
        _cell(row, colBase[k]),
        _cell(row, colBase[k] + 1),
        _cell(row, colBase[k] + 2),
      ];
      final next = [weight, rpe, speed];
      if (next.join('|') == current.join('|')) continue;
      final colLetter = _colLetter(colBase[k]);
      final colEnd = _colLetter(colBase[k] + 2);
      updates.add(SheetCellUpdate(
        range:
            '${_quoteTab(tabTitle)}!$colLetter${rowIndex + 1}:$colEnd${rowIndex + 1}',
        values: [next],
      ));
    }
  }

  /// Writes a planned write-back in one batchUpdate call. Actuals only —
  /// the plan never contains prescription columns.
  Future<void> writeBack({
    required http.Client client,
    required String spreadsheetId,
    required WriteBackPlan plan,
  }) async {
    if (plan.updates.isEmpty) return;
    final api = sheets.SheetsApi(client);
    await api.spreadsheets.values.batchUpdate(
      sheets.BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: plan.updates
            .map((u) => sheets.ValueRange(
                  range: u.range,
                  values: u.values
                      .map((row) => row.map((c) => c as Object).toList())
                      .toList(),
                ))
            .toList(),
      ),
      spreadsheetId,
    );
  }

  DateTime _resolveSingleDate(TopSingle single, ImportPreview preview) {
    final label = single.weekLabel.trim();
    // Week labels ("W3") match the week tab that starts with that label.
    final weekMatch = preview.weekStartDates.entries.where(
      (e) => e.key.startsWith(label) || label.startsWith(e.key),
    );
    if (weekMatch.isNotEmpty) return weekMatch.first.value;
    // "Oct 17 close" style labels carry their own month/day.
    final parsed = _parseDate(label, year: preview.setup?.programStart?.year ?? 2026);
    if (parsed != null) return parsed;
    return preview.setup?.programStart ?? DateTime.now();
  }

  // ------------------------------------------------------------------
  // Small helpers
  // ------------------------------------------------------------------

  static List<List<String>>? _findTab(
    FetchedSpreadsheet fetched,
    List<String> keywords,
  ) {
    for (final entry in fetched.tabs.entries) {
      final lower = entry.key.toLowerCase();
      if (keywords.any(lower.contains)) return entry.value;
    }
    return null;
  }

  static bool _hasExerciseHeader(List<List<String>> rows) =>
      rows.any((r) => _cell(r, 0).trim().toLowerCase() == 'exercise');

  static String _cell(List<String> row, int index) =>
      index < row.length ? row[index] : '';

  /// 0-based column index -> A1 letter (0 -> A, 5 -> F, 7 -> H).
  static String _colLetter(int col) =>
      String.fromCharCode('A'.codeUnitAt(0) + col);

  /// True when columns B–I are all blank (a lone-A row, e.g. a day
  /// header or a rest-day note).
  static bool _rowOthersEmpty(List<String> row) {
    for (var i = 1; i <= 8; i++) {
      if (_cell(row, i).trim().isNotEmpty) return false;
    }
    return true;
  }

  /// A1-notation tab quoting: single quotes, doubled inside the name.
  static String _quoteTab(String title) =>
      "'${title.replaceAll("'", "''")}'";

  /// 9.0 -> '9'; 156.8 -> '156.8'. Sheet cells read as plain numbers.
  static String _fmtNumber(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(1);
  }

  /// 'Squat' -> 'squat'; 'Squat beltless' / 'Comp bench' -> null.
  static String? _liftKey(String text) {
    final lower = text.trim().toLowerCase();
    if (lower == 'squat' || lower == 'bench' || lower == 'deadlift') {
      return lower;
    }
    return null;
  }

  static bool _isDayHeader(String text) {
    if (RegExp(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b').hasMatch(text)) return true;
    return text.contains('·') &&
        (text.contains('Rest') || RegExp(r'\bD\d+\b').hasMatch(text));
  }

  static double? _parseDouble(String? raw) {
    if (raw == null) return null;
    final text = raw.trim().replaceAll(',', '');
    if (text.isEmpty || text == '—' || text == '-') return null;
    return double.tryParse(text);
  }

  static const Map<String, int> _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static DateTime? _monthDay(String monthText, int day, int year) {
    final month = _months[monthText.trim().toLowerCase().substring(
          0,
          monthText.trim().length >= 3 ? 3 : monthText.trim().length,
        )];
    if (month == null || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  /// Parses "Nov 9", "Oct 19, 2026", "2026-10-19". [year] fills in when
  /// the text has no year. Returns null when nothing parses.
  static DateTime? _parseDate(String raw, {int year = 2026}) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;
    final withYear =
        RegExp(r'([A-Za-z]{3,9})\s+(\d{1,2}),?\s+(\d{4})').firstMatch(text);
    if (withYear != null) {
      return _monthDay(
        withYear.group(1)!,
        int.parse(withYear.group(2)!),
        int.parse(withYear.group(3)!),
      );
    }
    final withoutYear = RegExp(r'([A-Za-z]{3,9})\s+(\d{1,2})').firstMatch(text);
    if (withoutYear != null) {
      return _monthDay(
        withoutYear.group(1)!,
        int.parse(withoutYear.group(2)!),
        year,
      );
    }
    return null;
  }

  static String _slug(String text) {
    final slug = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'item' : slug;
  }
}
