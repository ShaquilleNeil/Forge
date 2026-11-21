import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bodyweight.dart';
import '../models/program.dart';
import '../models/record.dart';
import '../models/submission.dart';
import '../models/user_profile.dart';
import '../models/workout.dart';

/// Firestore CRUD. Every path is owner-scoped under users/{uid}/...
/// plus a top-level `submissions` collection (owner uid stored on the doc,
/// rules enforce owner-only access).
class FirestoreService {
  // Lazily resolved (not a field initializer) so a test subclass can
  // override the CRUD methods without ever touching Firebase.
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid, String name) =>
      _db.collection('users').doc(uid).collection(name);

  DocumentReference<Map<String, dynamic>> _profileDoc(String uid) =>
      _db.collection('users').doc(uid).collection('profile').doc('main');

  // ---- Profile ----
  // Merge, not overwrite (A8/A9): a profile save from the setup form
  // or a single Settings toggle must never wipe fields it does not
  // own — rest timers, write-back, alert prefs. A plain set() reset
  // them to defaults on every profile edit.
  Future<void> saveProfile(UserProfile profile) => _profileDoc(profile.uid)
      .set(profile.toJson(), SetOptions(merge: true));

  Future<UserProfile?> getProfile(String uid) async {
    final snap = await _profileDoc(uid).get();
    if (!snap.exists || snap.data() == null) return null;
    return UserProfile.fromJson(snap.data()!);
  }

  Stream<UserProfile?> watchProfile(String uid) =>
      _profileDoc(uid).snapshots().map((s) =>
          s.exists && s.data() != null ? UserProfile.fromJson(s.data()!) : null);

  // ---- Programs ----
  Future<void> saveProgram(String uid, Program program) =>
      _col(uid, 'programs').doc(program.id).set(program.toJson());

  Future<void> deleteProgram(String uid, String programId) =>
      _col(uid, 'programs').doc(programId).delete();

  Future<List<Program>> getPrograms(String uid) async {
    final snap = await _col(uid, 'programs').get();
    return snap.docs.map((d) => Program.fromJson(d.data())).toList();
  }

  Stream<List<Program>> watchPrograms(String uid) =>
      _col(uid, 'programs').snapshots().map(
            (s) => s.docs.map((d) => Program.fromJson(d.data())).toList(),
          );

  /// Sets [programId] active and clears the flag on every other
  /// program, in one transaction (A21): the old read-then-batch could
  /// race with a concurrent activation and leave two actives, and
  /// Today then picked arbitrarily. cloud_firestore transactions
  /// cannot query, so the refs come from a plain collection read and
  /// every doc is re-read inside the transaction — a concurrent
  /// activation touching any of them makes Firestore retry this
  /// transaction, and the write set (active iff id == programId) is
  /// deterministic, so the retry lands the same single active.
  /// Residual: a program doc created mid-flight already active (only
  /// a coach send creates one that way) is outside this transaction's
  /// read set; that path deactivates actives at its own query time.
  Future<void> setActiveProgram(String uid, String programId) async {
    final programs = _col(uid, 'programs');
    final snap = await programs.get();
    final refs = snap.docs.map((d) => d.reference).toList();
    await _db.runTransaction((tx) async {
      for (final ref in refs) {
        await tx.get(ref);
        tx.update(ref, {'isActive': ref.id == programId});
      }
    });
  }

  // ---- Coach programs ----
  // A second, fully separate program list for the coach side
  // (Nov 21): coaching programs live in `coachPrograms`, training
  // programs in `programs`. Nothing crosses over except an explicit
  // one-time copy (see coachCopyOf) or an import done on the coach
  // side. Coach programs are never active — active is a training
  // concept — and they are strictly owner-only (see firestore.rules).

  Future<void> saveCoachProgram(String uid, Program program) =>
      _col(uid, 'coachPrograms').doc(program.id).set(program.toJson());

  Future<void> deleteCoachProgram(String uid, String programId) =>
      _col(uid, 'coachPrograms').doc(programId).delete();

  Future<List<Program>> getCoachPrograms(String uid) async {
    final snap = await _col(uid, 'coachPrograms').get();
    return snap.docs.map((d) => Program.fromJson(d.data())).toList();
  }

  Stream<List<Program>> watchCoachPrograms(String uid) =>
      _col(uid, 'coachPrograms').snapshots().map(
            (s) => s.docs.map((d) => Program.fromJson(d.data())).toList(),
          );

  // ---- Workouts ----
  Future<void> saveWorkout(String uid, WorkoutSession session) =>
      _col(uid, 'workouts').doc(session.id).set(session.toJson());

  Future<void> deleteWorkout(String uid, String sessionId) =>
      _col(uid, 'workouts').doc(sessionId).delete();

  Future<List<WorkoutSession>> getWorkouts(String uid, {int limit = 50}) async {
    final snap = await _col(uid, 'workouts')
        .orderBy('date', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => WorkoutSession.fromJson(d.data())).toList();
  }

  Stream<List<WorkoutSession>> watchWorkouts(String uid, {int limit = 50}) =>
      _col(uid, 'workouts')
          .orderBy('date', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => WorkoutSession.fromJson(d.data())).toList());

  // ---- Records (PRs) ----
  Future<void> saveRecord(String uid, Record record) => _col(uid, 'records')
      .doc(record.exerciseId)
      .set(record.toJson());

  Future<Map<String, Record>> getRecords(String uid) async {
    final snap = await _col(uid, 'records').get();
    return {
      for (final d in snap.docs)
        d.id: Record.fromJson(d.data()),
    };
  }

  Stream<Map<String, Record>> watchRecords(String uid) =>
      _col(uid, 'records').snapshots().map((s) => {
            for (final d in s.docs) d.id: Record.fromJson(d.data()),
          });

  // ---- Bodyweight ----
  Future<void> saveBodyweight(String uid, BodyweightEntry entry) =>
      _col(uid, 'bodyweight').doc(entry.id).set(entry.toJson());

  Future<List<BodyweightEntry>> getBodyweight(String uid,
      {int limit = 200}) async {
    final snap = await _col(uid, 'bodyweight')
        .orderBy('date', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => BodyweightEntry.fromJson(d.data())).toList();
  }

  // ---- Submissions (Rank bridge, drafts only in v1) ----
  /// Writes to the user's subcollection AND the top-level collection
  /// (same doc id, owner uid on the doc) so Rank can query by owner later.
  Future<void> saveSubmission(String uid, Submission submission) async {
    final batch = _db.batch();
    batch.set(
      _col(uid, 'submissions').doc(submission.id),
      submission.toJson(),
    );
    batch.set(
      _db.collection('submissions').doc(submission.id),
      submission.toJson(),
    );
    await batch.commit();
  }

  Future<List<Submission>> getSubmissions(String uid) async {
    final snap = await _col(uid, 'submissions')
        .orderBy('date', descending: true)
        .get();
    return snap.docs.map((d) => Submission.fromJson(d.data())).toList();
  }

  Future<void> deleteSubmission(String uid, String submissionId) async {
    final batch = _db.batch();
    batch.delete(_col(uid, 'submissions').doc(submissionId));
    batch.delete(_db.collection('submissions').doc(submissionId));
    await batch.commit();
  }
}
