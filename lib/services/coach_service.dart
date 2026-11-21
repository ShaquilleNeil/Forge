import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/coach.dart';
import '../models/program.dart';

/// A one-time copy of a training program into the coach's own list.
/// The copy is a clean snapshot and the two are independent from then
/// on — editing one never touches the other. Dropped on purpose: the
/// meet plan (it is the coach's own meet, not the client's), the
/// sheet link (a copy must not re-link the sides through the sheet —
/// import the same sheet on the coach side to link it there), the
/// day moves (training-side scheduling), the sent-by stamp, and any
/// sent record. The weeks and days carry over verbatim. Pure, so it
/// is unit-testable.
Program coachCopyOf(
  Program source, {
  required String newId,
  required DateTime now,
}) =>
    Program(
      id: newId,
      userId: source.userId,
      name: source.name,
      description: source.description,
      weeks: source.weeks,
      meetPlan: null,
      isActive: false,
      createdAt: now,
      sourceSpreadsheetId: null,
      sourceModifiedTime: null,
      fromCoachUid: null,
      fromCoachName: null,
      dayMoves: const {},
      sentToClientIds: const [],
    );

/// Ids to deactivate when [newProgramId] becomes the active one: every
/// other program that is currently active. Pure, so it is unit-testable.
List<String> programsToDeactivate(
  List<Program> programs,
  String newProgramId,
) =>
    programs
        .where((p) => p.isActive && p.id != newProgramId)
        .map((p) => p.id)
        .toList();

/// Links newest first. Pure, so it is unit-testable.
///
/// The queries below deliberately have no orderBy: two equality filters
/// plus an orderBy needs a composite index in Firestore, and there is
/// none — the list is small, so sorting happens here instead.
List<CoachLink> sortCoachLinksNewestFirst(List<CoachLink> links) {
  final sorted = List<CoachLink>.from(links);
  sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return sorted;
}

/// The still-valid code with the latest expiry, if any. Pure, so it is
/// unit-testable. Used by [CoachService.getMyCode], which fetches by
/// client only — an expiry range filter plus an orderBy would need a
/// composite index that does not exist.
PairingCode? latestValidCode(List<PairingCode> codes) {
  PairingCode? best;
  for (final code in codes) {
    if (code.isExpired) continue;
    if (best == null || code.expiresAt.isAfter(best.expiresAt)) {
      best = code;
    }
  }
  return best;
}

/// Coach-side Firestore: pairing codes, coach–client links, sending
/// programs. Client data itself (profile, workouts, records) stays in the
/// owner's users/{uid}/... paths and is read through [FirestoreService];
/// the rules let a linked coach read only profile / workouts / records.
class CoachService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _links =>
      _db.collection('coachLinks');
  CollectionReference<Map<String, dynamic>> get _codes =>
      _db.collection('pairingCodes');

  static String linkId(String coachUid, String clientUid) =>
      '${coachUid}_$clientUid';

  // ---- Pairing codes (client side) ----

  /// The client's still-valid code, if one exists.
  Future<PairingCode?> getMyCode(String clientUid) async {
    final snap = await _codes.where('clientUid', isEqualTo: clientUid).get();
    final codes =
        snap.docs.map((d) => PairingCode.fromJson(d.data())).toList();
    return latestValidCode(codes);
  }

  /// Creates a fresh code, replacing any previous one. Old codes are
  /// deleted so only one code is ever live per client.
  Future<PairingCode> createCode(String clientUid, String clientName) async {
    final old = await _codes.where('clientUid', isEqualTo: clientUid).get();
    final batch = _db.batch();
    for (final doc in old.docs) {
      batch.delete(doc.reference);
    }
    final code = PairingCodes.generate();
    final now = DateTime.now();
    final pairing = PairingCode(
      code: code,
      clientUid: clientUid,
      clientName: clientName,
      createdAt: now,
      expiresAt: now.add(PairingCodes.validity),
    );
    batch.set(_codes.doc(code), pairing.toJson());
    await batch.commit();
    return pairing;
  }

  // ---- Linking (coach side) ----

  /// Redeems a code (scanned QR or typed) and creates the link.
  /// The redemption itself runs server-side: the redeemPairingCode
  /// Cloud Function verifies the code exists, is unexpired, and is
  /// not the caller's own, then creates the link and deletes the
  /// code in one transaction — so a code is single-use by
  /// construction and no client can grant itself coach access.
  /// Throws [CoachCodeError] when the code is unknown or expired.
  Future<CoachLink> redeemCode(String coachUid, String rawCode) async {
    final code = PairingCodes.normalize(rawCode);
    if (code.isEmpty) {
      throw const CoachCodeError('That code does not look right. Check it and try again.');
    }
    final callable =
        FirebaseFunctions.instance.httpsCallable('redeemPairingCode');
    late final Map<String, dynamic> data;
    try {
      final result = await callable.call({'code': code});
      final raw = result.data;
      if (raw is! Map) {
        throw const CoachCodeError('Could not link that client. Check the code and try again.');
      }
      data = Map<String, dynamic>.from(raw);
    } on FirebaseFunctionsException catch (e) {
      throw CoachCodeError(_redeemMessage(e));
    }
    final clientUid = data['clientUid'] as String? ?? '';
    final createdMillis = data['createdAtMillis'] as int?;
    if (clientUid.isEmpty || clientUid == coachUid) {
      throw const CoachCodeError('No client found for that code. Ask them to show a fresh one.');
    }
    return CoachLink(
      id: data['id'] as String? ?? linkId(coachUid, clientUid),
      coachUid: data['coachUid'] as String? ?? coachUid,
      clientUid: clientUid,
      createdAt: createdMillis == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(createdMillis),
    );
  }

  /// Maps a redeemPairingCode failure to the message the coach sees.
  /// Unknown codes surface the function's own wording; anything
  /// unexpected falls back to the generic retry message.
  String _redeemMessage(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
      case 'failed-precondition':
      case 'invalid-argument':
      case 'unauthenticated':
        return e.message ??
            'Could not link that client. Check the code and try again.';
      default:
        return 'Could not link that client. Check the code and try again.';
    }
  }

  // ---- Links ----

  /// The coach's clients, newest link first.
  Stream<List<CoachLink>> watchMyClients(String coachUid) => _links
      .where('coachUid', isEqualTo: coachUid)
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map(
        (s) => sortCoachLinksNewestFirst(
          s.docs.map((d) => CoachLink.fromJson(d.data())).toList(),
        ),
      );

  /// Who coaches this client (usually one person).
  Stream<List<CoachLink>> watchMyCoaches(String clientUid) => _links
      .where('clientUid', isEqualTo: clientUid)
      .where('status', isEqualTo: 'active')
      .snapshots()
      .map(
        (s) => sortCoachLinksNewestFirst(
          s.docs.map((d) => CoachLink.fromJson(d.data())).toList(),
        ),
      );

  /// Either side can unlink. Deleting the doc revokes the coach's access.
  Future<void> unlink(String linkId) => _links.doc(linkId).delete();

  /// The coach opened this client's detail: the NEW badge goes away.
  Future<void> markClientViewed(String linkId) =>
      _links.doc(linkId).update({'lastViewedAt': Timestamp.now()});

  // ---- Sending a program ----

  /// Copies one of the coach's coaching programs into the client's
  /// program list, stamped with the coach. A sent program becomes the
  /// client's active one right away. Sending the same program again
  /// overwrites the earlier copy (same doc id). The send is also
  /// recorded on the coach's copy (sentToClientIds), so the coach
  /// list can show "Sent to N clients" — that record is best-effort:
  /// if it fails, the client still got the program.
  Future<void> sendProgram({
    required Program program,
    required String coachUid,
    required String coachName,
    required String clientUid,
  }) async {
    // A sent program becomes the client's active one right away: clear
    // the flag on their other active programs, then write the copy —
    // one batch, so the client never has two actives at once.
    final programsRef = _db
        .collection('users')
        .doc(clientUid)
        .collection('programs');
    final current = await programsRef
        .where('isActive', isEqualTo: true)
        .get();
    final active = current.docs
        .map((d) => Program.fromJson(d.data()))
        .toList();
    final batch = _db.batch();
    for (final id in programsToDeactivate(active, program.id)) {
      batch.update(programsRef.doc(id), {'isActive': false});
    }
    final copy = program.copyWith(
      userId: clientUid,
      fromCoachUid: coachUid,
      fromCoachName: coachName,
      isActive: true,
      createdAt: DateTime.now(),
    );
    batch.set(programsRef.doc(program.id), copy.toJson());
    await batch.commit();
    try {
      await _db
          .collection('users')
          .doc(coachUid)
          .collection('coachPrograms')
          .doc(program.id)
          .update({
        'sentToClientIds': FieldValue.arrayUnion([clientUid]),
      });
    } catch (_) {
      // Best-effort — see the doc comment above.
    }
  }
}

/// A pairing-code problem the UI can show as-is.
class CoachCodeError implements Exception {
  final String message;
  const CoachCodeError(this.message);
  @override
  String toString() => message;
}
