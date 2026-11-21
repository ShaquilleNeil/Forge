import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:http/http.dart' as http;

/// Auth: email + Google sign-in. Google sign-in requests Drive/Sheets
/// read-only scopes so the import service can read a spreadsheet the
/// user picks — no spreadsheet ID is ever hardcoded.
///
/// NOTE: google_sign_in 7.x API — `GoogleSignIn.instance` singleton,
/// `initialize(serverClientId: ...)` once (the Web client ID — Android
/// requires it), `authenticate()` (not `signIn()`), and scopes are
/// authorized separately via `authorizationClient.authorizationForScopes`.
/// Firebase sign-in needs only the idToken; there is no accessToken in 7.x.
class AuthService {
  /// Read scopes for import: Drive + Sheets read-only. These are the
  /// scopes _authorize() requests — authenticate() itself requests no
  /// scopes in google_sign_in 7.x, so asking here is what makes the
  /// permission screen appear.
  static const List<String> googleScopes = [
    drive.DriveApi.driveReadonlyScope,
    sheets.SheetsApi.spreadsheetsReadonlyScope,
  ];

  /// Scopes for sheet write-back: full Sheets access (implies read),
  /// Drive stays read-only — the app never writes to Drive itself.
  /// Requested only when the user turns the write-back setting on, so
  /// the extra consent appears at that point, not at sign-in.
  static const List<String> googleWriteScopes = [
    drive.DriveApi.driveReadonlyScope,
    sheets.SheetsApi.spreadsheetsScope,
  ];

  /// Web OAuth client ID (client_type 3 in google-services.json —
  /// verified 2026-11-15). Required by google_sign_in 7.x on Android:
  /// without it, authenticate() throws clientConfigurationError
  /// ("serverClientId must be provided on Android").
  static const _webClientId =
      '431438016884-bd0mr254rfm6dqcc65n6qn6ibg1os1ua.apps.googleusercontent.com';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _googleInitialized = false;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;

  Future<void> _initGoogle() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _googleInitialized = true;
  }

  Future<UserCredential> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<UserCredential> signUpWithEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  /// Google sign-in (7.x): basic sign-in only, idToken only — no
  /// scopeHint, no accessToken. Drive/Sheets scopes are NOT asked here;
  /// they are asked when actually needed: read scopes at Import
  /// (requestReadAccess) and the write scope when write-back is turned
  /// on (requestWriteAccess).
  Future<UserCredential?> signInWithGoogle() async {
    try {
      await _initGoogle();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken =
          account.authentication.idToken; // synchronous in 7.x, no await
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      return await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      debugPrint('GOOGLE SIGN-IN ERROR: $e');
      rethrow;
    }
  }

  /// Authorizes the Drive/Sheets read scopes for import. First tries a
  /// silent authorization; a null there is NOT a refusal, it just means
  /// the interactive permission screen has to be shown, so authorizeScopes
  /// is called — that is the call that shows the permission screen.
  /// Throws when the user declines or the request fails.
  Future<GoogleSignInClientAuthorization> _authorize() async {
    await _initGoogle();
    final client = GoogleSignIn.instance.authorizationClient;
    try {
      final existing = await client.authorizationForScopes(googleScopes);
      debugPrint('IMPORT AUTH: silent = ${existing != null}');
      if (existing != null) return existing;
      final granted = await client.authorizeScopes(googleScopes);
      debugPrint('IMPORT AUTH: interactive granted');
      return granted;
    } catch (e, st) {
      debugPrint('IMPORT AUTH ERROR: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  /// Asks Google for the Drive/Sheets read scopes (user consent UI when
  /// they have not been granted yet). Returns true when read access is
  /// held. Called when the user opens Import — never at sign-in, so the
  /// permissions screen appears at the moment the app needs the access.
  Future<bool> requestReadAccess() async {
    try {
      await _authorize();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Authenticated HTTP client for Google APIs (Sheets/Drive import).
  /// Returns null when the user has not authorized the Google scopes.
  /// Built from the authorization's accessToken, the same way as before.
  Future<http.Client?> authenticatedGoogleClient() async {
    final authz = await _authorize();
    return authz.authClient(scopes: googleScopes);
  }

  /// Silent-only read client: returns null when the read scopes are not
  /// already granted — it NEVER shows a consent screen. For background
  /// checks, like the sheet-change check when the Program screen opens,
  /// where a popup would be the wrong moment to ask. When it returns
  /// null the caller just skips the check.
  Future<http.Client?> authenticatedGoogleClientSilent() async {
    try {
      await _initGoogle();
      final existing = await GoogleSignIn
          .instance.authorizationClient
          .authorizationForScopes(googleScopes);
      if (existing == null) return null;
      return existing.authClient(scopes: googleScopes);
    } catch (_) {
      return null;
    }
  }

  /// Mirrors _authorize() for the write scopes: silent first, then
  /// the interactive permission screen. A null from
  /// authorizationForScopes is NOT a refusal — it just means
  /// authorizeScopes has to be called.
  ///
  /// This was the bug behind "Write access was not granted": the old
  /// requestWriteAccess() only did the silent check and never called
  /// authorizeScopes(), so the consent screen never appeared and the
  /// toggle always failed — the same bug the import flow had before
  /// its _authorize() fix.
  Future<GoogleSignInClientAuthorization> _authorizeWrite() async {
    await _initGoogle();
    final client = GoogleSignIn.instance.authorizationClient;
    try {
      final existing =
          await client.authorizationForScopes(googleWriteScopes);
      debugPrint('WRITEBACK AUTH: silent = ${existing != null}');
      if (existing != null) return existing;
      final granted = await client.authorizeScopes(googleWriteScopes);
      debugPrint('WRITEBACK AUTH: interactive granted');
      return granted;
    } catch (e, st) {
      debugPrint('WRITEBACK AUTH ERROR: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  /// Asks Google for the Sheets write scope (user consent UI when it
  /// has not been granted yet). Returns true when write access is held.
  /// Called when the write-back setting is turned on — never at sign-in.
  Future<bool> requestWriteAccess() async {
    try {
      await _authorizeWrite();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Authenticated HTTP client with the Sheets write scope, for
  /// write-back. Returns null when write access is not granted.
  Future<http.Client?> authenticatedGoogleWriteClient() async {
    try {
      final authz = await _authorizeWrite();
      return authz.authClient(scopes: googleWriteScopes);
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() async {
    await _initGoogle();
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  /// Whether the current user signed in with Google / with email.
  /// Used by the delete-account flow to pick how to re-authenticate.
  bool get usesGoogle =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'google.com') ??
      false;
  bool get usesPassword =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  /// Re-authenticates a Google user: shows the account chooser and
  /// proves it is really them. Throws when they cancel or it fails.
  /// Called before account deletion — a destructive action should
  /// never ride on a stale session alone.
  Future<void> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    await _initGoogle();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await user.reauthenticateWithCredential(credential);
  }

  /// Re-authenticates an email user with their password. Throws when
  /// the password is wrong.
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in.');
    final email = user.email;
    if (email == null) throw StateError('No email on this account.');
    final credential =
        EmailAuthProvider.credential(email: email, password: password);
    await user.reauthenticateWithCredential(credential);
  }
}
