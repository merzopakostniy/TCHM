import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

class AppFirebaseOptions {
  static const isConfigured = bool.fromEnvironment(
    'FIREBASE_CONFIGURED',
    defaultValue: true,
  );

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError('Firebase is not configured yet.');
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => ios,
      TargetPlatform.android => android,
      _ => android,
    };
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyAvB91Dkx1lu8mzza08QuVuwIngtUlSvx0',
    appId: '1:764816237987:android:d8e0978655e172ddf92616',
    messagingSenderId: '764816237987',
    projectId: 'tchm-9612d',
    storageBucket: 'tchm-9612d.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyA_V0P1-yHMf6qTNDOoohMwXAFUXWRzOjA',
    appId: '1:764816237987:ios:8a1f2da79c9ddbe7f92616',
    messagingSenderId: '764816237987',
    projectId: 'tchm-9612d',
    storageBucket: 'tchm-9612d.firebasestorage.app',
    iosBundleId: 'merzopakostniy.tchmApp',
  );
}
