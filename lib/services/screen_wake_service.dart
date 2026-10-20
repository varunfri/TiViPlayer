import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'system_pip_service.dart';

/// Service responsible for keeping the device display awake during active video playback.
/// Prevents phones, tablets, Android TV, and desktop devices from sleeping or timing out.
class ScreenWakeService {
  static bool _isWakeEnabled = false;

  /// Returns whether the wake lock is currently active.
  static bool get isWakeEnabled => _isWakeEnabled;

  /// Toggle screen wake lock state based on playback.
  static Future<void> keepScreenOn(bool enable) async {
    _isWakeEnabled = enable;

    // 1. Cross-platform Wakelock (Android, iOS, macOS, Windows, Linux, Web)
    try {
      await WakelockPlus.toggle(enable: enable);
      debugPrint('[ScreenWakeService] WakelockPlus toggled: $enable');
    } catch (e) {
      debugPrint('[ScreenWakeService] WakelockPlus error: $e');
    }

    // 2. Native Android WindowManager FLAG_KEEP_SCREEN_ON
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await SystemPipService.setKeepScreenOn(enable);
        debugPrint(
          '[ScreenWakeService] Native Android keep-screen-on toggled: $enable',
        );
      } catch (e) {
        debugPrint('[ScreenWakeService] Native keepScreenOn error: $e');
      }
    }
  }

  /// Convenience method to disable wake lock when app is paused/closed
  static Future<void> releaseWakeLock() async {
    await keepScreenOn(false);
  }
}
