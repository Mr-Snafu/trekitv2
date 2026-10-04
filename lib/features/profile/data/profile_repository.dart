import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../domain/profile_state.dart';

class ProfileRepository {
  ProfileRepository({FirebaseAuth? auth, http.Client? httpClient})
    : _auth = auth ?? FirebaseAuth.instance,
      _httpClient = httpClient ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _httpClient;

  Future<ProfileState> getState() async {
    final result = await _call('getProfileState');
    return ProfileState.fromCallable(
      Map<Object?, Object?>.from(result! as Map),
    );
  }

  Future<ProfileState> update(ProfileState state) async {
    final result = await _call('updateProfile', {
      'displayName': state.displayName,
      'bio': state.bio,
      'notifyCircleRequests': state.notifyCircleRequests,
      'notifyAdventureActivity': state.notifyAdventureActivity,
      'allowCircleRequests': state.allowCircleRequests,
    });
    await _auth.currentUser?.reload();
    return ProfileState.fromCallable(
      Map<Object?, Object?>.from(result! as Map),
    );
  }

  Future<Map<String, dynamic>> exportMyData() async {
    final result = await _call('exportMyData');
    return Map<String, dynamic>.from(result! as Map);
  }

  Future<Object?> _call(
    String functionName, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) {
      throw const ProfileServiceException('Sign in to continue.');
    }
    final response = await _httpClient.post(
      Uri.parse(
        'https://us-central1-trekit-10e88.cloudfunctions.net/$functionName',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'data': data}),
    );
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ProfileServiceException(
        'The Profile service is temporarily unavailable.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw ProfileServiceException(
        error?['message'] as String? ?? 'The request could not be completed.',
      );
    }
    return decoded['data'] ?? decoded['result'];
  }
}

class ProfileServiceException implements Exception {
  const ProfileServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
