import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'app_platform.dart';

/// Service managing Desktop Picture-in-Picture mode on macOS, Windows, and Linux.
///
/// Resizes and floats the Flutter desktop window in the corner of the screen
/// and keeps it strictly displayed OVER other apps via [windowManager.setAlwaysOnTop].
class DesktopPipService {
  DesktopPipService._();

  static bool _isInPip = false;
  static bool get isInPip => _isInPip;

  static final ValueNotifier<bool> isPipNotifier = ValueNotifier<bool>(false);

  static Size? _savedSize;
  static Offset? _savedPosition;

  /// Default floating window width on desktop
  static const double defaultPipWidth = 440.0;

  /// Enters desktop Picture-in-Picture mode:
  /// Resizes the window, floats it in the bottom-right corner, and sets always-on-top.
  static Future<bool> enterPip({(int, int)? aspectRatio}) async {
    if (!AppPlatform.isDesktop) return false;
    if (_isInPip) return true;

    try {
      // 1. Save current window bounds
      _savedSize = await windowManager.getSize();
      _savedPosition = await windowManager.getPosition();

      // 2. Compute aspect ratio and dimensions
      final ratioW = aspectRatio?.$1 ?? 16;
      final ratioH = aspectRatio?.$2 ?? 9;
      const double pipWidth = defaultPipWidth;
      final double pipHeight = (pipWidth * ratioH / ratioW).roundToDouble();

      // 3. Find the display where the window currently resides
      Display activeDisplay;
      try {
        final displays = await screenRetriever.getAllDisplays();
        if (_savedPosition != null && displays.isNotEmpty) {
          final windowCenter = Offset(
            _savedPosition!.dx + (_savedSize?.width ?? 0) / 2,
            _savedPosition!.dy + (_savedSize?.height ?? 0) / 2,
          );
          activeDisplay = displays.firstWhere(
            (d) {
              final pos = d.visiblePosition ?? const Offset(0, 0);
              final size = d.visibleSize ?? d.size;
              return windowCenter.dx >= pos.dx &&
                  windowCenter.dx <= pos.dx + size.width &&
                  windowCenter.dy >= pos.dy &&
                  windowCenter.dy <= pos.dy + size.height;
            },
            orElse: () => displays.first,
          );
        } else {
          activeDisplay = await screenRetriever.getPrimaryDisplay();
        }
      } catch (_) {
        activeDisplay = await screenRetriever.getPrimaryDisplay();
      }

      final workArea = activeDisplay.visibleSize ?? activeDisplay.size;
      final workPos = activeDisplay.visiblePosition ?? const Offset(0, 0);

      const double margin = 28.0;
      final double posX = workPos.dx + workArea.width - pipWidth - margin;
      final double posY = workPos.dy + workArea.height - pipHeight - margin;

      // 4. Configure window manager to display over all other applications
      await windowManager.setMinimumSize(const Size(240, 135));
      await windowManager.setSize(Size(pipWidth, pipHeight));
      await windowManager.setPosition(Offset(posX, posY));
      await windowManager.setAlwaysOnTop(true);

      _isInPip = true;
      isPipNotifier.value = true;
      debugPrint('[DesktopPipService] Entered Desktop PiP: size=($pipWidth, $pipHeight), pos=($posX, $posY), alwaysOnTop=true');
      return true;
    } catch (e) {
      debugPrint('[DesktopPipService] Error entering desktop PiP: $e');
      return false;
    }
  }

  /// Exits desktop Picture-in-Picture mode and restores previous window bounds
  static Future<bool> exitPip() async {
    if (!AppPlatform.isDesktop || !_isInPip) return false;

    try {
      // 1. Remove always-on-top so the window behaves normally
      await windowManager.setAlwaysOnTop(false);

      // 2. Restore previous window minimum size & dimensions
      await windowManager.setMinimumSize(const Size(800, 500));

      if (_savedSize != null) {
        await windowManager.setSize(_savedSize!);
      } else {
        await windowManager.setSize(const Size(1280, 720));
      }

      if (_savedPosition != null) {
        await windowManager.setPosition(_savedPosition!);
      }

      _isInPip = false;
      isPipNotifier.value = false;
      debugPrint('[DesktopPipService] Exited Desktop PiP and restored normal window frame.');
      return true;
    } catch (e) {
      debugPrint('[DesktopPipService] Error exiting desktop PiP: $e');
      return false;
    }
  }

  /// Toggles between desktop PiP and standard window mode
  static Future<bool> togglePip({(int, int)? aspectRatio}) async {
    if (_isInPip) {
      return exitPip();
    } else {
      return enterPip(aspectRatio: aspectRatio);
    }
  }
}
