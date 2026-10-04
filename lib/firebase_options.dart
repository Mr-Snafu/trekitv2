// Generated from the Firebase project configuration for trekit-10e88.
// Firebase API keys identify the project; they are not server credentials.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase is not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAFdsQRjiX17sIjQZmBHK8aZd8MDzLbzq8',
    appId: '1:692333975435:web:fe0a7d803d6039b89b818e',
    messagingSenderId: '692333975435',
    projectId: 'trekit-10e88',
    authDomain: 'trekit-10e88.firebaseapp.com',
    storageBucket: 'trekit-10e88.firebasestorage.app',
    measurementId: 'G-N63F4BHVEF',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD4FxgwQ-2UJJcPXJzvWYcMd1FKotG99Jw',
    appId: '1:692333975435:android:c180b1d1059f98ab9b818e',
    messagingSenderId: '692333975435',
    projectId: 'trekit-10e88',
    storageBucket: 'trekit-10e88.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCrRemSqJ4fgCrJ9xRxWDtrJfYVRPlc2DQ',
    appId: '1:692333975435:ios:b33921a9d6c93ffa9b818e',
    messagingSenderId: '692333975435',
    projectId: 'trekit-10e88',
    storageBucket: 'trekit-10e88.firebasestorage.app',
    iosBundleId: 'com.cowtowndev.trekit',
  );
}
