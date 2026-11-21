import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/program.dart';
import 'package:forge/models/record.dart';
import 'package:forge/models/user_profile.dart';
import 'package:forge/services/firestore_service.dart';
import 'package:forge/services/sheet_import_service.dart';

// A11/A14/A15/A25: re-import merge behaviour, tested through the pure
// merge function and through importParsed against an in-memory fake
// FirestoreService (injected via the firestoreService override, so no
// Firebase is touched — the service's db handle is lazy for exactly
// this reason).
class FakeFirestoreService extends FirestoreService {
  final Map<String, Program> programs = {};
  final Map<String, Program> coachPrograms = {};
  final Map<String, Record> records = {};
  UserProfile? profile;

  @override
  Future<List<Program>> getPrograms(String uid) async =>
      programs.values.toList();

  @override
  Future<List<Program>> getCoachPrograms(String uid) async =>
      coachPrograms.values.toList();

  @override
  Future<void> saveProgram(String uid, Program program) async {
    programs[program.id] = program;
  }

  @override
  Future<void> saveCoachProgram(String uid, Program program) async {
    coachPrograms[program.id] = program;
  }

  @override
  Future<Map<String, Record>> getRecords(String uid) async =>
      Map<String, Record>.of(records);

  @override
  Future<void> saveRecord(String uid, Record record) async {
    records[record.exerciseId] = record;
  }

  @override
  Future<UserProfile?> getProfile(String uid) async => profile;

  @override
  Future<void> saveProfile(UserProfile p) async {
    profile = p;
  }
}

Program _program({
  required String id,
  required String name,
  String? spreadsheetId,
  String? fromCoachUid,
  String? fromCoachName,
  List<String> sentToClientIds = const [],
}) =>
    Program(
      id: id,
      userId: 'u1',
      name: name,
      createdAt: DateTime(2026, 11, 9),
      sourceSpreadsheetId: spreadsheetId,
      fromCoachUid: fromCoachUid,
      fromCoachName: fromCoachName,
      sentToClientIds: sentToClientIds,
    );

void main() {
  group('mergeImportedProgram keeps the coach stamp (A11)', () {
    test('fromCoachUid / fromCoachName / sentToClientIds survive', () {
      const preview = ImportPreview(programName: 'Iron Ascent', weeks: []);
      final merged = SheetImportService.mergeImportedProgram(
        uid: 'u1',
        preview: preview,
        existing: _program(
          id: 'p1',
          name: 'Iron Ascent',
          fromCoachUid: 'coach1',
          fromCoachName: 'Coach Alex',
          sentToClientIds: ['client1', 'client2'],
        ),
        isFirstProgram: false,
      );
      expect(merged.fromCoachUid, 'coach1');
      expect(merged.fromCoachName, 'Coach Alex');
      expect(merged.sentToClientIds, ['client1', 'client2']);
    });

    test('no existing program means no stamp', () {
      const preview = ImportPreview(programName: 'Iron Ascent', weeks: []);
      final merged = SheetImportService.mergeImportedProgram(
        uid: 'u1',
        preview: preview,
        isFirstProgram: true,
      );
      expect(merged.fromCoachUid, isNull);
      expect(merged.fromCoachName, isNull);
      expect(merged.sentToClientIds, isEmpty);
    });
  });

  group('importParsed matches by spreadsheet id (A14)', () {
    test('a rename still merges onto the same program', () async {
      final fake = FakeFirestoreService();
      fake.programs['p1'] = _program(
        id: 'p1',
        name: 'Old Name',
        spreadsheetId: 'sheet-1',
      );
      final service = SheetImportService(firestoreService: fake);
      final result = await service.importParsed(
        uid: 'u1',
        preview: const ImportPreview(programName: 'New Name', weeks: []),
        spreadsheetId: 'sheet-1',
      );
      expect(result.programId, 'p1');
      expect(fake.programs.length, 1);
      expect(fake.programs['p1']!.name, 'New Name');
      expect(fake.programs['p1']!.sourceSpreadsheetId, 'sheet-1');
    });

    test('name fallback still works when there is no spreadsheet id',
        () async {
      final fake = FakeFirestoreService();
      fake.programs['p1'] = _program(id: 'p1', name: 'Iron Ascent');
      final service = SheetImportService(firestoreService: fake);
      final result = await service.importParsed(
        uid: 'u1',
        preview:
            const ImportPreview(programName: 'iron ascent', weeks: []),
      );
      expect(result.programId, 'p1');
      expect(fake.programs.length, 1);
    });

    test('no id match and no name match creates a new program', () async {
      final fake = FakeFirestoreService();
      fake.programs['p1'] = _program(
        id: 'p1',
        name: 'Old Name',
        spreadsheetId: 'sheet-1',
      );
      final service = SheetImportService(firestoreService: fake);
      final result = await service.importParsed(
        uid: 'u1',
        preview: const ImportPreview(programName: 'Other', weeks: []),
        spreadsheetId: 'sheet-2',
      );
      expect(result.programId, isNot('p1'));
      expect(fake.programs.length, 2);
    });
  });

  group('importParsed keeps the max PR (A15)', () {
    test('a lower sheet single never downgrades the stored PR', () async {
      final fake = FakeFirestoreService();
      fake.records['squat'] = Record(
        exerciseId: 'squat',
        bestWeightKg: 200,
        bestE1rmKg: 200,
        date: DateTime(2026, 11, 1),
        setId: 'session1:0',
      );
      final service = SheetImportService(firestoreService: fake);
      await service.importParsed(
        uid: 'u1',
        preview: const ImportPreview(
          programName: 'Iron Ascent',
          weeks: [],
          topSingles: {
            'squat': TopSingle(
              lift: 'squat',
              weightKg: 190,
              weekLabel: 'W3',
            ),
          },
        ),
        spreadsheetId: 'sheet-1',
      );
      final kept = fake.records['squat']!;
      expect(kept.bestWeightKg, 200);
      expect(kept.bestE1rmKg, 200);
      expect(kept.date, DateTime(2026, 11, 1));
      expect(kept.setId, 'session1:0');
    });

    test('a heavier sheet single replaces the stored PR', () async {
      final fake = FakeFirestoreService();
      fake.records['squat'] = Record(
        exerciseId: 'squat',
        bestWeightKg: 180,
        bestE1rmKg: 180,
        date: DateTime(2026, 11, 1),
      );
      final service = SheetImportService(firestoreService: fake);
      await service.importParsed(
        uid: 'u1',
        preview: const ImportPreview(
          programName: 'Iron Ascent',
          weeks: [],
          topSingles: {
            'squat': TopSingle(
              lift: 'squat',
              weightKg: 190,
              weekLabel: 'W3',
            ),
          },
        ),
        spreadsheetId: 'sheet-1',
      );
      expect(fake.records['squat']!.bestWeightKg, 190);
      expect(fake.records['squat']!.bestE1rmKg, 190);
    });

    test('bestWeightKg and bestE1rmKg keep their max independently',
        () async {
      final fake = FakeFirestoreService();
      // Stored best came from a multi-rep set: lower top weight, but
      // a higher estimated 1RM.
      fake.records['bench'] = Record(
        exerciseId: 'bench',
        bestWeightKg: 115,
        bestE1rmKg: 130,
        date: DateTime(2026, 11, 1),
      );
      final service = SheetImportService(firestoreService: fake);
      await service.importParsed(
        uid: 'u1',
        preview: const ImportPreview(
          programName: 'Iron Ascent',
          weeks: [],
          topSingles: {
            'bench': TopSingle(
              lift: 'bench',
              weightKg: 120,
              weekLabel: 'W3',
            ),
          },
        ),
        spreadsheetId: 'sheet-1',
      );
      expect(fake.records['bench']!.bestWeightKg, 120);
      expect(fake.records['bench']!.bestE1rmKg, 130);
    });
  });

  group('row-100 cap is reported, not silent (A25)', () {
    test('previewSpreadsheet carries truncatedTabs from the fetch', () {
      final preview = SheetImportService.previewSpreadsheet(
        const FetchedSpreadsheet(
          title: 'Iron Ascent Training Log',
          tabs: {
            'W1 Oct 26': [
              ['Exercise', 'Weight (kg)'],
            ],
          },
          truncatedTabs: ['W1 Oct 26'],
        ),
      );
      expect(preview.truncatedTabs, ['W1 Oct 26']);
    });

    test('truncatedTabs defaults to empty', () {
      const preview = ImportPreview(programName: 'X', weeks: []);
      expect(preview.truncatedTabs, isEmpty);
    });
  });
}
