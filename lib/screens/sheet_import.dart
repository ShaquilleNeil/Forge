import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/program.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/sheet_import_service.dart';
import '../services/side_service.dart';
import '../services/strength_math.dart';
import '../services/tab_nav.dart';
import '../theme.dart';

enum _Step { connect, pick, preview }

/// Spreadsheet import: Google sign-in -> pick a spreadsheet from Drive ->
/// preview -> confirm -> import. A CSV file can be imported instead
/// (parsed as one week tab with the same A–I columns).
class SheetImportScreen extends StatefulWidget {
  const SheetImportScreen({super.key});

  @override
  State<SheetImportScreen> createState() => _SheetImportScreenState();
}

class _SheetImportScreenState extends State<SheetImportScreen> {
  final _auth = AuthService();
  final _importer = SheetImportService();
  final _firestore = FirestoreService();

  _Step _step = _Step.connect;
  http.Client? _client;
  List<SpreadsheetFileInfo> _files = [];
  SpreadsheetFileInfo? _selected;
  ImportPreview? _preview;
  bool _busy = false;
  String? _error;
  String _busyMessage = '';
  bool _isCsv = false;
  // The user's display units (A19): prior-close and top-single weights
  // in the preview are stored kg, shown via formatWeight in these units.
  String _units = 'kg';

  @override
  void initState() {
    super.initState();
    _loadUnits();
    _checkGoogleAccess();
  }

  Future<void> _loadUnits() async {
    final uid = _auth.currentUid;
    if (uid == null) return;
    try {
      final profile = await _firestore.getProfile(uid);
      if (!mounted || profile == null) return;
      setState(() => _units = profile.units);
    } catch (_) {
      // Units stay kg on a failed read — the preview still works.
    }
  }

  // ---------------------------------------------------------------
  // Step 1 — Google access
  // ---------------------------------------------------------------

  Future<void> _checkGoogleAccess() async {
    setState(() {
      _busy = true;
      _busyMessage = 'Checking Google access…';
      _error = null;
    });
    // Not signed in yet: don't attempt authorization, just show Connect.
    if (_auth.currentUser == null) {
      setState(() {
        _busy = false;
        _step = _Step.connect;
      });
      return;
    }
    try {
      // Ask for Drive/Sheets access here, at import time — this is the
      // call that makes Google show the permissions screen.
      final granted = await _auth.requestReadAccess();
      if (!mounted) return;
      if (!granted) {
        setState(() {
          _busy = false;
          _step = _Step.connect;
          _error =
              'Drive and Sheets access is needed to import. Tap Connect and allow access when Google asks.';
        });
        return;
      }
      final client = await _auth.authenticatedGoogleClient();
      if (!mounted) return;
      if (client == null) {
        setState(() {
          _busy = false;
          _step = _Step.connect;
        });
        return;
      }
      _client = client;
      await _loadFiles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.connect;
        _error = 'Could not check Google access. Please try again.';
      });
    }
  }

  Future<void> _connectGoogle() async {
    setState(() {
      _busy = true;
      _busyMessage = 'Signing in with Google…';
      _error = null;
    });
    // Step 1 — sign-in only if not already signed in to Firebase.
    // If already signed in, go straight to authorization.
    if (_auth.currentUser == null) {
      try {
        await _auth.signInWithGoogle();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error =
              'Google sign-in was cancelled or failed. Please try again.';
        });
        return;
      }
    }
    // Step 2 — ask for Drive/Sheets access, on its own, so a failure
    // here can only mean the permissions screen (cancelled or failed).
    if (!mounted) return;
    setState(() => _busyMessage = 'Asking for Drive and Sheets access…');
    bool granted;
    try {
      granted = await _auth.requestReadAccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'The Drive and Sheets permission request was cancelled or failed. Tap Retry and allow access when Google asks.';
      });
      return;
    }
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _busy = false;
        _error =
            'Drive and Sheets access was not granted. Tap Retry and allow access when Google asks.';
      });
      return;
    }
    try {
      final client = await _auth.authenticatedGoogleClient();
      if (!mounted) return;
      if (client == null) {
        setState(() {
          _busy = false;
          _error =
              'Google sign-in worked, but Drive and Sheets access was not granted. Please sign in again and allow access to Drive and Sheets.';
        });
        return;
      }
      _client = client;
      await _loadFiles();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Google sign-in was cancelled or failed. Please try again and allow access to Drive and Sheets.';
      });
    }
  }

  // ---------------------------------------------------------------
  // Step 2 — pick a spreadsheet
  // ---------------------------------------------------------------

  Future<void> _loadFiles() async {
    final client = _client;
    if (client == null) {
      setState(() => _step = _Step.connect);
      return;
    }
    setState(() {
      _busy = true;
      _busyMessage = 'Loading your spreadsheets…';
      _error = null;
    });
    try {
      final files = await _importer.listSpreadsheets(client);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _files = files;
        _step = _Step.pick;
        if (files.isEmpty) {
          _error = 'No spreadsheets were found in your Google Drive.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _Step.pick;
        _error =
            'Could not list your spreadsheets. Check your connection and try again.';
      });
    }
  }

  Future<void> _fetchPreview() async {
    final client = _client;
    final selected = _selected;
    if (client == null || selected == null) return;
    setState(() {
      _busy = true;
      _busyMessage = 'Reading “${selected.name}”…';
      _error = null;
      _isCsv = false;
    });
    try {
      final fetched = await _importer.fetchSpreadsheet(client, selected.id);
      final preview = SheetImportService.previewSpreadsheet(fetched);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _preview = preview;
        _step = _Step.preview;
        if (preview.weeks.isEmpty) {
          _error =
              'That spreadsheet has no week tabs I can read. Check it uses the usual layout (Exercise | Weight | Sets x reps) and try again.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'Could not read that spreadsheet. Make sure it is shared with the Google account you signed in with, then try again.';
      });
    }
  }

  // ---------------------------------------------------------------
  // CSV fallback — one week tab, same A–I columns
  // ---------------------------------------------------------------

  Future<void> _pickCsv() async {
    setState(() => _error = null);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      final file = picked.firstOrNull;
      if (file == null) return; // user cancelled
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes);
      final rawRows = const CsvToListConverter().convert(text);
      final rows = rawRows
          .map((r) => r.map((c) => c?.toString() ?? '').toList())
          .toList();
      final title = file.name.replaceAll(RegExp(r'\.csv$', caseSensitive: false), '');
      final skipped = <SkippedRow>[];
      final week = SheetImportService.parseWeekTab(
        title.isEmpty ? 'Imported Week' : title,
        rows,
        skippedRows: skipped,
      );
      if (!mounted) return;
      setState(() {
        _isCsv = true;
        _preview = ImportPreview(
          programName: title.isEmpty ? 'Imported Program' : title,
          weeks: [week],
          skippedRows: skipped,
        );
        _step = _Step.preview;
        if (week.days.isEmpty) {
          _error =
              'That CSV has no days I can read. Check it uses the usual columns (Exercise | Weight | Sets x reps, first row is the header) and try again.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not read that CSV file. Please try another file.';
      });
    }
  }

  // ---------------------------------------------------------------
  // Step 4 — confirm import
  // ---------------------------------------------------------------

  Future<void> _confirmImport() async {
    final preview = _preview;
    final uid = _auth.currentUid;
    if (preview == null) return;
    if (uid == null) {
      setState(() {
        _error = 'You need to be signed in to import. Please sign in and try again.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _busyMessage = 'Importing “${preview.programName}”…';
      _error = null;
    });
    try {
      // On the coach side the import lands in the coaching list, not
      // the training list — the side decides the target collection.
      final isCoach = SideService.isCoach;
      final result = _isCsv
          ? await _importer.importParsed(
              uid: uid,
              preview: preview,
              coach: isCoach,
            )
          : await _importer.importToFirestore(
              uid: uid,
              spreadsheetId: _selected!.id,
              client: _client!,
              coach: isCoach,
            );
      if (!mounted) return;
      // Import done — back to the Today tab, where the imported program
      // is today's workout. The summary rides along as a SnackBar, which
      // survives the pop because it belongs to the root messenger.
      final skipped = result.skippedRows.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '“${result.programName}” imported — '
            '${result.weekCount} weeks · ${result.dayCount} days · '
            '${result.exerciseCount} exercises'
            '${skipped > 0 ? '\n$skipped rows skipped' : ''}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      // Training side lands on Today (0); coach side lands on Programs (2).
      goToTab.value = SideService.isCoach ? 2 : 0;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            'The import failed. Nothing was changed — please try again.';
      });
    }
  }

  void _retry() {
    switch (_step) {
      case _Step.connect:
        _checkGoogleAccess();
      case _Step.pick:
        _loadFiles();
      case _Step.preview:
        if (_isCsv) {
          _pickCsv();
        } else {
          _fetchPreview();
        }
    }
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Spreadsheet')),
      body: _busy
          ? _buildBusy()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStepHeader(),
                const SizedBox(height: 16),
                if (_error != null) _buildError(),
                switch (_step) {
                  _Step.connect => _buildConnect(),
                  _Step.pick => _buildPick(),
                  _Step.preview => _buildPreview(),
                },
              ],
            ),
    );
  }

  Widget _buildBusy() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_busyMessage),
          ],
        ),
      );

  Widget _buildStepHeader() {
    const labels = ['Connect', 'Pick', 'Preview'];
    final current = _step.index;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          _StepDot(number: i + 1, label: labels[i], active: i <= current),
          if (i < labels.length - 1)
            Expanded(
              child: Container(
                height: 2,
                color: i < current ? ForgeTheme.accent : ForgeTheme.divider,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildError() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ForgeTheme.card,
          border: Border.all(color: ForgeTheme.red),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: ForgeTheme.red),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!)),
            TextButton(onPressed: _retry, child: const Text('Retry')),
          ],
        ),
      );

  Widget _buildConnect() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            SideService.isCoach
                ? 'Forge reads the spreadsheet straight from Google Drive. '
                    'Sign in with Google and allow access to Drive and Sheets '
                    '(read-only). Forge never changes your spreadsheet.'
                : 'Forge reads your training log straight from Google Drive. '
                    'Sign in with Google and allow access to Drive and Sheets '
                    '(read-only). Forge never changes your spreadsheet.',
            style: ForgeTheme.bodyMuted,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _connectGoogle,
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          ),
        ],
      );

  Widget _buildPick() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose the spreadsheet to import. The newest ones are first.',
            style: ForgeTheme.bodyMuted,
          ),
          const SizedBox(height: 12),
          ..._files.map((file) {
            final selected = _selected?.id == file.id;
            return Card(
              color: selected ? ForgeTheme.card : ForgeTheme.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selected ? ForgeTheme.accent : ForgeTheme.divider,
                  width: selected ? 2 : 1,
                ),
              ),
              child: ListTile(
                leading: const Icon(Icons.table_chart, color: ForgeTheme.accent),
                title: Text(file.name),
                subtitle: file.modifiedTime == null
                    ? null
                    : Text(
                        'Modified ${DateFormat('MMM d, yyyy').format(file.modifiedTime!)}',
                        style: ForgeTheme.bodyMuted,
                      ),
                trailing: selected
                    ? const Icon(Icons.check_circle, color: ForgeTheme.accent)
                    : null,
                onTap: () => setState(() => _selected = file),
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _selected == null ? null : _fetchPreview,
            child: const Text('Preview import'),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('— or —', style: ForgeTheme.bodyMuted),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickCsv,
            icon: const Icon(Icons.upload_file),
            label: const Text('Or import a CSV file'),
          ),
        ],
      );

  Widget _buildPreview() {
    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WillImportCard(weeks: preview.weeks),
        const SizedBox(height: 12),
        // A25: tabs that hit the 100-row read cap — rows past 100 were
        // never read and are not in this preview. Warn here, before
        // the user confirms, instead of silently importing a partial
        // sheet.
        if (preview.truncatedTabs.isNotEmpty)
          _TruncatedWarningCard(tabs: preview.truncatedTabs),
        if (preview.truncatedTabs.isNotEmpty) const SizedBox(height: 12),
        _SummaryCard(
          title: preview.programName,
          lines: [
            '${preview.weekCount} weeks · ${preview.dayCount} days · ${preview.exerciseCount} exercises',
            if (preview.meetPlan != null) _meetSummary(preview.meetPlan!),
            if (preview.setup != null && preview.setup!.priorClose.isNotEmpty)
              'Prior close: ${_liftsSummary(preview.setup!.priorClose)}',
            if (preview.topSingles.isNotEmpty)
              'Latest top singles: ${_liftsSummary({for (final e in preview.topSingles.entries) e.key: e.value.weightKg})}',
          ],
        ),
        const SizedBox(height: 12),
        if (preview.meetPlan != null && preview.meetPlan!.attempts.isNotEmpty)
          _MeetCard(meetPlan: preview.meetPlan!),
        const SizedBox(height: 12),
        _SkippedCard(skipped: preview.skippedRows),
        const SizedBox(height: 16),
        Text(
          SideService.isCoach
              ? 'Importing replaces the weeks and meet plan of a coaching program with the same name. Your training records and profile lifts are untouched — this sheet is a program template for your clients, not your training log.'
              : 'Importing replaces the weeks and meet plan of a program with the same name, and refreshes your records from the latest top singles. Your profile lifts are only filled in when they are empty.',
          style: ForgeTheme.bodyMuted,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: preview.weeks.isEmpty ? null : _confirmImport,
          child: const Text('Import program'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _step = _Step.pick;
            _preview = null;
            _selected = null;
            _error = null;
          }),
          child: const Text('Back to spreadsheets'),
        ),
      ],
    );
  }

  String _meetSummary(MeetPlan plan) {
    final date = plan.date == null
        ? 'Meet'
        : 'Meet ${DateFormat('MMM d, yyyy').format(plan.date!)}';
    return '$date · ${plan.attempts.length} lifts planned';
  }

  String _liftsSummary(Map<String, double> lifts) {
    const labels = {'squat': 'Squat', 'bench': 'Bench', 'deadlift': 'Deadlift'};
    return [
      for (final e in lifts.entries)
        '${labels[e.key] ?? e.key} ${_formatWeight(e.value)}',
    ].join(' · ');
  }

  // Shared helper (A19): stored kg rendered in the user's units.
  String _formatWeight(double kg) => formatWeight(kg, _units);
}

/// Warning shown in the import preview when one or more tabs hit the
/// 100-row read cap (A25): only the first 100 rows were read, so rows
/// past 100 are not in the preview and would not be imported.
class _TruncatedWarningCard extends StatelessWidget {
  final List<String> tabs;

  const _TruncatedWarningCard({required this.tabs});

  @override
  Widget build(BuildContext context) {
    final names = tabs.map((t) => '“$t”').join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_outlined,
              color: ForgeTheme.warning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Only the first 100 rows of $names were read — '
                'rows past 100 are not in this preview and will not '
                'be imported.',
                style: ForgeTheme.warningText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int number;
  final String label;
  final bool active;

  const _StepDot({required this.number, required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: active ? ForgeTheme.accent : ForgeTheme.card,
          child: Text(
            '$number',
            style: TextStyle(
              color:
                  active ? ForgeTheme.scaffoldBg : ForgeTheme.muted,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? ForgeTheme.text : ForgeTheme.muted,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _SummaryCard({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...lines.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(line),
                )),
          ],
        ),
      ),
    );
  }
}

class _MeetCard extends StatelessWidget {
  final MeetPlan meetPlan;

  const _MeetCard({required this.meetPlan});

  @override
  Widget build(BuildContext context) {
    final date = meetPlan.date == null
        ? 'Meet day'
        : 'Meet day: ${DateFormat('MMM d, yyyy').format(meetPlan.date!)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(date, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...meetPlan.attempts.map((a) {
              String fmt(double? v) => v == null
                  ? '—'
                  : (v == v.truncateToDouble() ? '${v.toInt()}' : '$v');
              final third = a.thirdLowKg == null
                  ? '—'
                  : (a.thirdHighKg != null && a.thirdHighKg != a.thirdLowKg
                      ? '${fmt(a.thirdLowKg)}–${fmt(a.thirdHighKg)}'
                      : fmt(a.thirdLowKg));
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${a.lift[0].toUpperCase()}${a.lift.substring(1)}: '
                  '${fmt(a.openerKg)} / ${fmt(a.secondKg)} / $third kg'
                  '${a.lastWarmUpKg != null ? ' · last warm-up ${fmt(a.lastWarmUpKg)} kg' : ''}',
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// What the import will bring in: one collapsible row per week with
/// day and exercise counts; expanding a week lists its days.
class _WillImportCard extends StatelessWidget {
  final List<ProgramWeek> weeks;

  const _WillImportCard({required this.weeks});

  @override
  Widget build(BuildContext context) {
    final dayCount = weeks.fold(0, (n, w) => n + w.days.length);
    final exCount = weeks.fold(
      0,
      (n, w) => n + w.days.fold(0, (m, d) => m + d.exercises.length),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Will be imported',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${weeks.length} weeks · $dayCount days · $exCount exercises',
              style: ForgeTheme.bodyMuted,
            ),
            ...weeks.asMap().entries.map((entry) {
              final i = entry.key;
              final w = entry.value;
              final wEx = w.days
                  .fold(0, (n, d) => n + d.exercises.length);
              return ExpansionTile(
                initiallyExpanded: i == 0,
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '${w.title} · ${w.days.length} days · $wEx exercises',
                ),
                children: w.days
                    .map(
                      (d) => Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Expanded(child: Text(d.title)),
                            Text(
                              '${d.exercises.length} exercises',
                              style: ForgeTheme.bodyMuted,
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _SkippedCard extends StatefulWidget {
  final List<SkippedRow> skipped;

  const _SkippedCard({required this.skipped});

  @override
  State<_SkippedCard> createState() => _SkippedCardState();
}

class _SkippedCardState extends State<_SkippedCard> {
  /// The reason template with the row's own quoted text removed, so
  /// rows skipped for the same cause group together.
  String _normalizeReason(String reason) {
    var r = reason
        .replaceAll(RegExp(r'"[^"]*"'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    r = r.replaceFirst(RegExp(r'^(Row|Exercise|Note row)\s+'), '');
    if (r.isEmpty) return reason;
    return r[0].toUpperCase() + r.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final skipped = widget.skipped;
    if (skipped.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Skipped rows: none',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Every row was understood.',
                style: ForgeTheme.bodyMuted,
              ),
            ],
          ),
        ),
      );
    }
    final normalized =
        skipped.map((s) => _normalizeReason(s.reason)).toList();
    final counts = <String, int>{};
    for (final n in normalized) {
      counts[n] = (counts[n] ?? 0) + 1;
    }
    final majority = counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    final mixed = counts.length > 1;
    return Card(
      child: ExpansionTile(
        // A row skipped for a different reason opens expanded, with a
        // warning, so it is not buried under the common case.
        initiallyExpanded: mixed,
        leading: mixed
            ? const Icon(
                Icons.warning_amber_outlined,
                color: ForgeTheme.accent,
              )
            : null,
        title: Text(
          mixed
              ? '${skipped.length} rows skipped'
              : '${skipped.length} rows skipped · $majority',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        children: _rowsByTab(skipped, normalized, majority),
      ),
    );
  }

  List<Widget> _rowsByTab(
    List<SkippedRow> skipped,
    List<String> normalized,
    String majority,
  ) {
    final tabs = <String>[];
    for (final s in skipped) {
      if (!tabs.contains(s.tab)) tabs.add(s.tab);
    }
    final out = <Widget>[];
    for (final tab in tabs) {
      final rows = <SkippedRow>[];
      final norms = <String>[];
      for (var i = 0; i < skipped.length; i++) {
        if (skipped[i].tab == tab) {
          rows.add(skipped[i]);
          norms.add(normalized[i]);
        }
      }
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '$tab · ${rows.length} ${rows.length == 1 ? 'row' : 'rows'}',
            style: ForgeTheme.bodyMediumSemibold,
          ),
        ),
      );
      for (var j = 0; j < rows.length; j++) {
        final s = rows[j];
        final differs = norms[j] != majority;
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'row ${s.row} — ${s.text ?? s.reason}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ForgeTheme.bodyMuted,
                ),
                if (differs)
                  Text(
                    s.reason,
                    style: const TextStyle(color: ForgeTheme.accent),
                  ),
              ],
            ),
          ),
        );
      }
    }
    return out;
  }
}
