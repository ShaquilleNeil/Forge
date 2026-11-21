import 'package:cloud_functions/cloud_functions.dart';

import 'auth_service.dart';

/// Account deletion: calls the deleteAccount Cloud Function, which
/// removes everything the account owns server-side (Firestore docs
/// under users/{uid}, coach links and pairing codes that name the
/// user, top-level submissions, Storage videos, then the Auth user
/// itself), and then signs out locally so AuthGate lands on login.
///
/// The function is idempotent and deletes Auth last, so a failed run
/// can simply be retried — the user stays signed in until it
/// succeeds. One exception: if the success response is lost after
/// Auth is already deleted, a retry fails `unauthenticated` — the
/// account is already gone, so "sign in and retry" can never work.
/// That case is handled below by signing out locally and telling
/// the user how to tell whether the deletion already went through
/// (try signing in: if it fails, the account is gone).
class AccountService {
  final AuthService _auth = AuthService();

  Future<void> deleteAccount() async {
    final callable =
        FirebaseFunctions.instance.httpsCallable('deleteAccount');
    try {
      await callable.call();
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated') {
        // Either the session expired before anything was deleted, or
        // the deletion already succeeded and the lost response is
        // the only reason this looks like a failure. Signing out is
        // right in both cases: if the account still exists, the
        // user can sign back in and retry; if it does not, the
        // sign-in attempt itself proves the deletion went through.
        try {
          await _auth.signOut();
        } catch (_) {
          // Local sign-out is best-effort here; the message below
          // still tells the user what to do next.
        }
        throw StateError(
          'You have been signed out. Your account may already have '
          'been deleted — try signing in: if sign-in fails, the '
          'deletion already went through; if you can sign in, '
          'retry deleting your account.',
        );
      }
      throw StateError(_readableMessage(e));
    }
    await _auth.signOut();
  }

  String _readableMessage(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'The delete function is not deployed yet. '
            'Run firebase deploy --only functions and retry.';
      default:
        return e.message ?? 'Could not delete the account: ${e.code}.';
    }
  }
}
