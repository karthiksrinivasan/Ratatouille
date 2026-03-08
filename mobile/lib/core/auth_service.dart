import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Wrapper around Firebase Auth providing sign-in, sign-out, and token access.
class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth;

  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance {
    // Listen for auth state changes and notify consumers.
    _auth.authStateChanges().listen((_) => notifyListeners());
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// The currently signed-in user, or `null`.
  User? get currentUser => _auth.currentUser;

  /// Whether a user is currently signed in.
  bool get isSignedIn => currentUser != null;

  /// Whether the current user is anonymous (guest).
  bool get isAnonymous => currentUser?.isAnonymous ?? true;

  /// Display name of the current user.
  String? get displayName => currentUser?.displayName;

  /// Email of the current user.
  String? get email => currentUser?.email;

  /// Stream of auth state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ---------------------------------------------------------------------------
  // Token
  // ---------------------------------------------------------------------------

  /// Return the current user's Firebase ID token, or `null` if signed out.
  ///
  /// The token is automatically refreshed if it has expired.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  // ---------------------------------------------------------------------------
  // Sign in
  // ---------------------------------------------------------------------------

  /// Sign in with email and password.
  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    notifyListeners();
    return credential;
  }

  /// Create a new account with email and password.
  Future<UserCredential> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    notifyListeners();
    return credential;
  }

  /// Sign in anonymously (useful for quick hackathon demos).
  Future<UserCredential> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    notifyListeners();
    return credential;
  }

  // ---------------------------------------------------------------------------
  // Account linking (anonymous → permanent)
  // ---------------------------------------------------------------------------

  /// Link the current anonymous account to email/password credentials.
  /// Preserves the existing UID so all Firestore data stays associated.
  Future<UserCredential> linkEmailPassword({
    required String email,
    required String password,
  }) async {
    final user = currentUser;
    if (user == null) throw FirebaseAuthException(code: 'no-user', message: 'No user signed in');
    final credential = EmailAuthProvider.credential(email: email, password: password);
    final result = await user.linkWithCredential(credential);
    notifyListeners();
    return result;
  }

  // ---------------------------------------------------------------------------
  // Password reset
  // ---------------------------------------------------------------------------

  /// Send a password reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  // ---------------------------------------------------------------------------
  // Profile updates
  // ---------------------------------------------------------------------------

  /// Update the current user's display name.
  Future<void> updateDisplayName(String name) async {
    final user = currentUser;
    if (user == null) return;
    await user.updateDisplayName(name);
    await user.reload();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Account deletion
  // ---------------------------------------------------------------------------

  /// Delete the current user's account.
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) return;
    await user.delete();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Sign out
  // ---------------------------------------------------------------------------

  /// Sign the current user out.
  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }
}
