import 'package:flutter/foundation.dart';

/// Legacy Firebase/YANDEX_API flags cannot select a different production server.
abstract final class RuntimeConfig {
  static const demo = kDebugMode && (bool.fromEnvironment('DEMO') || shot >= 0);
  static const shot = kDebugMode
      ? int.fromEnvironment('SHOT', defaultValue: -1)
      : -1;
}
