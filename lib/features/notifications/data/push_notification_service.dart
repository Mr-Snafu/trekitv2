import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum BrowserPushStatus { unsupported, notEnabled, enabled, blocked }

class PushNotificationService {
  PushNotificationService({
    FirebaseAuth? auth,
    FirebaseMessaging? messaging,
    http.Client? httpClient,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _messaging = messaging ?? FirebaseMessaging.instance,
       _httpClient = httpClient ?? http.Client();

  static const _vapidKey =
      'BLQjH88PbnadNtYWvc-esPVpVOYd-PlzKVqIrFdotCotzpM88t95C4X2-Toi9JAomxIdWyAXytoj1qkYD3aCKvs';

  final FirebaseAuth _auth;
  final FirebaseMessaging _messaging;
  final http.Client _httpClient;
  StreamSubscription<String>? _tokenRefreshSubscription;

  Stream<RemoteMessage> get foregroundMessages => FirebaseMessaging.onMessage;

  Future<BrowserPushStatus> getStatus() async {
    if (!kIsWeb || !await _messaging.isSupported()) {
      return BrowserPushStatus.unsupported;
    }
    final settings = await _messaging.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => BrowserPushStatus.enabled,
      AuthorizationStatus.denied => BrowserPushStatus.blocked,
      _ => BrowserPushStatus.notEnabled,
    };
  }

  Future<BrowserPushStatus> initializeSilently() async {
    final status = await getStatus();
    if (status == BrowserPushStatus.enabled) {
      await _registerCurrentToken();
      _listenForTokenRefresh();
    }
    return status;
  }

  Future<BrowserPushStatus> enable() async {
    if (!kIsWeb || !await _messaging.isSupported()) {
      return BrowserPushStatus.unsupported;
    }
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return settings.authorizationStatus == AuthorizationStatus.denied
          ? BrowserPushStatus.blocked
          : BrowserPushStatus.notEnabled;
    }
    await _registerCurrentToken();
    _listenForTokenRefresh();
    return BrowserPushStatus.enabled;
  }

  Future<BrowserPushStatus> disable() async {
    if (!kIsWeb || !await _messaging.isSupported()) {
      return BrowserPushStatus.unsupported;
    }
    final token = await _messaging.getToken(
      vapidKey: _vapidKey,
      serviceWorkerScriptPath: 'push/firebase-messaging-sw.js',
    );
    if (token != null) {
      await _call('unregisterPushDevice', {'token': token});
    }
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;
    await _messaging.deleteToken();
    return BrowserPushStatus.notEnabled;
  }

  Future<void> _registerCurrentToken() async {
    final token = await _messaging.getToken(
      vapidKey: _vapidKey,
      serviceWorkerScriptPath: 'push/firebase-messaging-sw.js',
    );
    if (token == null) {
      throw const PushNotificationException(
        'This browser could not create a notification subscription.',
      );
    }
    await _call('registerPushDevice', {'token': token, 'platform': 'web'});
  }

  void _listenForTokenRefresh() {
    if (_tokenRefreshSubscription != null) return;
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (token) =>
          _call('registerPushDevice', {'token': token, 'platform': 'web'}),
    );
  }

  Future<Object?> _call(String functionName, Map<String, Object?> data) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null) {
      throw const PushNotificationException('Sign in to continue.');
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
      throw const PushNotificationException(
        'Browser notifications are temporarily unavailable.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw PushNotificationException(
        error?['message'] as String? ??
            'The notification request could not be completed.',
      );
    }
    return decoded['data'] ?? decoded['result'];
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    _httpClient.close();
  }
}

class PushNotificationException implements Exception {
  const PushNotificationException(this.message);

  final String message;

  @override
  String toString() => message;
}
