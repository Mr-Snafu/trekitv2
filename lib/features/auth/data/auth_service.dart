import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AuthService {
  AuthService({FirebaseAuth? auth, http.Client? httpClient})
    : _auth = auth ?? FirebaseAuth.instance,
      _httpClient = httpClient ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _httpClient;

  Stream<User?> get userChanges => _auth.userChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.sendEmailVerification();
    return credential;
  }

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<bool> refreshEmailVerification() async {
    await _auth.currentUser?.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> deleteAccount() async {
    final token = await _auth.currentUser?.getIdToken(true);
    if (token == null) {
      throw const AccountServiceException(
        code: 'unauthenticated',
        message: 'Sign in again to delete your account.',
      );
    }

    final response = await _httpClient.post(
      Uri.parse(
        'https://us-central1-trekit-10e88.cloudfunctions.net/deleteAccount',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'data': <String, Object?>{}}),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw AccountServiceException(
        code: (error?['status'] as String? ?? 'unknown')
            .toLowerCase()
            .replaceAll('_', '-'),
        message:
            error?['message'] as String? ?? 'The account could not be deleted.',
      );
    }

    await _auth.signOut();
  }

  Future<void> signOut() => _auth.signOut();
}

class AccountServiceException implements Exception {
  const AccountServiceException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => message;
}
