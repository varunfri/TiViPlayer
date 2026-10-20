import 'package:flutter/foundation.dart';

/// Multi-platform detection utility safe for Mobile, Desktop, and Web.
/// Never throws `Unsupported operation: Platform._operatingSystem` on Web.
class AppPlatform {
  static bool get isWeb => kIsWeb;
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  static bool get isMobile => isAndroid || isIOS;
  static bool get isDesktop => isMacOS || isWindows || isLinux;
}
