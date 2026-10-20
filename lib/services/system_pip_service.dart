import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// System-wide Picture-in-Picture (PiP) service.
/// Interacts with Android's native PictureInPicture framework via MethodChannel
/// to allow playback in a floating window over the launcher and other apps.
class SystemPipService {
  static const MethodChannel _channel = MethodChannel('com.app.tvplayer/pip');

  static final ValueNotifier<bool> inPipModeNotifier = ValueNotifier<bool>(false);
  static bool get inPipMode => inPipModeNotifier.value;

  static bool _initialized = false;
  static final List<void Function(bool inPip)> _listeners = [];
  static VoidCallback? _onTogglePlayPause;
  static VoidCallback? _onNextChannel;

  /// Initialize native callback listeners for PiP mode change events and native PiP actions
  static void initialize({
    void Function(bool inPip)? onPipChanged,
    VoidCallback? onTogglePlayPause,
    VoidCallback? onNextChannel,
  }) {
    if (onPipChanged != null) {
      _listeners.add(onPipChanged);
    }
    if (onTogglePlayPause != null) {
      _onTogglePlayPause = onTogglePlayPause;
    }
    if (onNextChannel != null) {
      _onNextChannel = onNextChannel;
    }
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipModeChanged':
          final bool isPip = call.arguments as bool? ?? false;
          inPipModeNotifier.value = isPip;
          for (final listener in List.of(_listeners)) {
            listener(isPip);
          }
          break;
        case 'togglePlayPause':
          _onTogglePlayPause?.call();
          break;
        case 'nextChannel':
          _onNextChannel?.call();
          break;
      }
    });
  }

  /// Register a listener for PiP state changes
  static void addPipListener(void Function(bool inPip) listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  /// Remove a registered listener
  static void removePipListener(void Function(bool inPip) listener) {
    _listeners.remove(listener);
  }

  /// Check whether native Picture-in-Picture is supported by the device hardware/OS
  static Future<bool> isPipSupported() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final bool? supported = await _channel.invokeMethod<bool>('isPipSupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check whether Picture-in-Picture is permitted in Android Special App Access settings
  static Future<bool> isPipAllowed() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final bool? allowed = await _channel.invokeMethod<bool>('isPipAllowed');
      return allowed ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Open Android OS Settings page to enable Picture-in-Picture for this app
  static Future<bool> openPipSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final bool? ok = await _channel.invokeMethod<bool>('openPipSettings');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check whether the application is currently running inside the native PiP window
  static Future<bool> isInPipMode() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final bool? inPip = await _channel.invokeMethod<bool>('isInPipMode');
      return inPip ?? inPipMode;
    } catch (_) {
      return inPipMode;
    }
  }

  /// Immediately enter native Picture-in-Picture mode with the specified aspect ratio
  static Future<bool> enterPip({
    int numerator = 16,
    int denominator = 9,
    bool isPlaying = true,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final bool? ok = await _channel.invokeMethod<bool>('enterPip', {
        'numerator': numerator,
        'denominator': denominator,
        'isPlaying': isPlaying,
      });
      return ok ?? false;
    } catch (e) {
      debugPrint('[SystemPipService] enterPip error: $e');
      return false;
    }
  }

  /// Configure Android 12+ / Oreo auto-enter PiP when user navigates away or presses home
  static Future<void> setAutoEnterPip(
    bool enabled, {
    int numerator = 16,
    int denominator = 9,
    bool isPlaying = true,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod('setAutoEnterPip', {
        'enabled': enabled,
        'numerator': numerator,
        'denominator': denominator,
        'isPlaying': isPlaying,
      });
    } catch (e) {
      debugPrint('[SystemPipService] setAutoEnterPip error: $e');
    }
  }

  /// Notify native Android of playback state change so PiP remote actions update play/pause icon
  static Future<void> updatePlaybackState(bool isPlaying) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod('updatePlaybackState', {
        'isPlaying': isPlaying,
      });
    } catch (e) {
      debugPrint('[SystemPipService] updatePlaybackState error: $e');
    }
  }

  /// Control native Android WindowManager FLAG_KEEP_SCREEN_ON
  static Future<void> setKeepScreenOn(bool keepOn) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod('setKeepScreenOn', {
        'keepOn': keepOn,
      });
    } catch (e) {
      debugPrint('[SystemPipService] setKeepScreenOn error: $e');
    }
  }
}
