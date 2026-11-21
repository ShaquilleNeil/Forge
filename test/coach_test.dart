import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge/models/coach.dart';
import 'package:forge/models/program.dart';
import 'package:forge/services/coach_service.dart';

void main() {
  group('PairingCodes.generate', () {
    test('a code is 6 characters from the unambiguous alphabet', () {
      final code = PairingCodes.generate(Random(42));
      expect(code.length, PairingCodes.length);
      for (final ch in code.split('')) {
        expect(PairingCodes.alphabet.contains(ch), isTrue);
      }
    });

    test('different seeds give different codes', () {
      expect(
        PairingCodes.generate(Random(1)) != PairingCodes.generate(Random(2)),
        isTrue,
      );
    });

    test('the alphabet has no look-alike characters', () {
      for (final ch in ['0', 'O', '1', 'I', 'L']) {
        expect(PairingCodes.alphabet.contains(ch), isFalse);
      }
    });
  });

  group('PairingCodes.display / normalize', () {
    test('display prefixes the code', () {
      expect(PairingCodes.display('7K2Q9X'), 'FORGE-7K2Q9X');
    });

    test('normalize accepts the bare code, the display form and a scan', () {
      expect(PairingCodes.normalize('7K2Q9X'), '7K2Q9X');
      expect(PairingCodes.normalize('FORGE-7K2Q9X'), '7K2Q9X');
      expect(PairingCodes.normalize('forge-7k2q9x'), '7K2Q9X');
      expect(PairingCodes.normalize('  forge 7k2q9x '), '7K2Q9X');
    });

    test('normalize rejects anything that is not a code', () {
      expect(PairingCodes.normalize('hello'), '');
      expect(PairingCodes.normalize('FORGE-123'), '');
      expect(PairingCodes.normalize(''), '');
    });
  });

  group('PairingCode', () {
    test('isExpired follows the expiry time', () {
      final now = DateTime.now();
      final live = PairingCode(
        code: '7K2Q9X',
        clientUid: 'client-1',
        clientName: 'Maya',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
      );
      expect(live.isExpired, isFalse);
      expect(live.display, 'FORGE-7K2Q9X');

      final dead = PairingCode(
        code: '7K2Q9X',
        clientUid: 'client-1',
        clientName: 'Maya',
        createdAt: now.subtract(const Duration(days: 2)),
        expiresAt: now.subtract(const Duration(days: 1)),
      );
      expect(dead.isExpired, isTrue);
    });

    test('toJson / fromJson round-trip', () {
      final code = PairingCode(
        code: '7K2Q9X',
        clientUid: 'client-1',
        clientName: 'Maya',
        createdAt: DateTime(2026, 11, 16, 19, 0),
        expiresAt: DateTime(2026, 11, 17, 19, 0),
      );
      final restored = PairingCode.fromJson(code.toJson());
      expect(restored.code, '7K2Q9X');
      expect(restored.clientUid, 'client-1');
      expect(restored.clientName, 'Maya');
      expect(restored.expiresAt, DateTime(2026, 11, 17, 19, 0));
    });
  });

  group('CoachLink', () {
    test('toJson / fromJson round-trip keeps the viewed time', () {
      final link = CoachLink(
        id: 'coach-1_client-1',
        coachUid: 'coach-1',
        clientUid: 'client-1',
        createdAt: DateTime(2026, 11, 16, 19, 0),
        lastViewedAt: DateTime(2026, 11, 16, 20, 0),
      );
      final restored = CoachLink.fromJson(link.toJson());
      expect(restored.id, 'coach-1_client-1');
      expect(restored.coachUid, 'coach-1');
      expect(restored.clientUid, 'client-1');
      expect(restored.lastViewedAt, DateTime(2026, 11, 16, 20, 0));
    });

    test('fromJson tolerates Timestamp fields from Firestore', () {
      final restored = CoachLink.fromJson({
        'id': 'coach-1_client-1',
        'coachUid': 'coach-1',
        'clientUid': 'client-1',
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 16, 19, 0)),
        'lastViewedAt': null,
        'status': 'active',
      });
      expect(restored.createdAt, DateTime(2026, 11, 16, 19, 0));
      expect(restored.lastViewedAt, isNull);
    });
  });

  group('Program fromCoach fields', () {
    test('a sent program keeps its coach stamp through JSON', () {
      final program = Program(
        id: 'prog-1',
        userId: 'client-1',
        name: 'Iron Ascent',
        createdAt: DateTime(2026, 11, 16),
        fromCoachUid: 'coach-1',
        fromCoachName: 'Alex',
        isActive: false,
      );
      final restored = Program.fromJson(program.toJson());
      expect(restored.fromCoachUid, 'coach-1');
      expect(restored.fromCoachName, 'Alex');
      expect(restored.isActive, isFalse);
    });

    test('copyWith can stamp a program as sent', () {
      final program = Program(
        id: 'prog-1',
        userId: 'coach-1',
        name: 'Iron Ascent',
        createdAt: DateTime(2026, 11, 16),
        isActive: true,
      );
      final sent = program.copyWith(
        userId: 'client-1',
        fromCoachUid: 'coach-1',
        fromCoachName: 'Alex',
        isActive: false,
      );
      expect(sent.userId, 'client-1');
      expect(sent.fromCoachUid, 'coach-1');
      expect(sent.isActive, isFalse);
      expect(sent.name, 'Iron Ascent');
    });
  });

  group('latestValidCode', () {
    PairingCode code(String id, DateTime expires) => PairingCode(
          code: id,
          clientUid: 'c1',
          clientName: 'Test',
          createdAt: DateTime(2026, 11, 16, 12),
          expiresAt: expires,
        );

    test('picks the still-valid code with the latest expiry', () {
      final now = DateTime.now();
      final codes = [
        code('OLD', now.subtract(const Duration(hours: 1))),
        code('A', now.add(const Duration(hours: 1))),
        code('B', now.add(const Duration(hours: 2))),
      ];
      expect(latestValidCode(codes)?.code, 'B');
    });

    test('ignores expired codes entirely', () {
      final now = DateTime.now();
      final codes = [
        code('OLD', now.subtract(const Duration(hours: 1))),
      ];
      expect(latestValidCode(codes), isNull);
    });

    test('empty list gives null', () {
      expect(latestValidCode([]), isNull);
    });
  });

  group('sortCoachLinksNewestFirst', () {
    CoachLink link(String id, DateTime created) => CoachLink(
          id: id,
          coachUid: 'coach1',
          clientUid: 'client-$id',
          createdAt: created,
          lastViewedAt: null,
        );

    test('orders newest first', () {
      final links = [
        link('a', DateTime(2026, 11, 14)),
        link('b', DateTime(2026, 11, 16)),
        link('c', DateTime(2026, 11, 15)),
      ];
      final sorted = sortCoachLinksNewestFirst(links);
      expect(sorted.map((l) => l.id).toList(), ['b', 'c', 'a']);
    });

    test('does not mutate the input list', () {
      final links = [
        link('a', DateTime(2026, 11, 14)),
        link('b', DateTime(2026, 11, 16)),
      ];
      sortCoachLinksNewestFirst(links);
      expect(links.map((l) => l.id).toList(), ['a', 'b']);
    });
  });

  group('programsToDeactivate', () {
    Program program(String id, {bool active = false}) => Program(
          id: id,
          userId: 'u1',
          name: id,
          createdAt: DateTime(2026, 11, 16),
          isActive: active,
        );

    test('deactivates other active programs', () {
      final programs = [
        program('a', active: true),
        program('b', active: true),
      ];
      expect(programsToDeactivate(programs, 'c'), ['a', 'b']);
    });

    test('skips the new program itself', () {
      final programs = [
        program('a', active: true),
        program('new', active: true),
      ];
      expect(programsToDeactivate(programs, 'new'), ['a']);
    });

    test('empty when nothing is active', () {
      expect(programsToDeactivate([program('a')], 'new'), isEmpty);
    });
  });
}
