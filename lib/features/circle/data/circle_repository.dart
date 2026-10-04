import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../domain/circle_state.dart';

class CircleRepository {
  CircleRepository({FirebaseAuth? auth, http.Client? httpClient})
    : _auth = auth ?? FirebaseAuth.instance,
      _httpClient = httpClient ?? http.Client();

  final FirebaseAuth _auth;
  final http.Client _httpClient;

  Future<CircleState> getState() async {
    final result = await _call('getCircleState');
    return CircleState.fromCallable(Map<Object?, Object?>.from(result! as Map));
  }

  Future<void> sendRequest(String trekId) =>
      _call('sendCircleRequest', {'trekId': trekId});

  Future<void> accept(String userId) =>
      _call('acceptCircleRequest', {'userId': userId});

  Future<void> decline(String userId) =>
      _call('declineCircleRequest', {'userId': userId});

  Future<void> remove(String userId) =>
      _call('removeCircleMember', {'userId': userId});

  Future<void> block(String userId) =>
      _call('blockCircleMember', {'userId': userId});

  Future<void> unblock(String userId) =>
      _call('unblockCircleMember', {'userId': userId});

  Future<Object?> _call(
    String functionName, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) {
      throw const CircleServiceException('Sign in to continue.');
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
      throw const CircleServiceException(
        'The Circle service is temporarily unavailable.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw CircleServiceException(
        error?['message'] as String? ?? 'The request could not be completed.',
      );
    }
    return decoded['data'] ?? decoded['result'];
  }
}

class CircleServiceException implements Exception {
  const CircleServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
