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
  // Sign out
  // ---------------------------------------------------------------------------

  /// Sign the current user out.
  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }
}
