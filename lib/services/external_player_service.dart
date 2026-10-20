import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/channel.dart';
import 'app_platform.dart';
import '../ui/widgets/tv_toast.dart';

class BrowserInfo {
  final String name;
  final String appName;
  final String appPath;
  final bool supportsWidevine;

  const BrowserInfo({
    required this.name,
    required this.appName,
    required this.appPath,
    this.supportsWidevine = true,
  });
}

class ExternalPlayerService {
  ExternalPlayerService._();

  static const List<BrowserInfo> _macBrowsers = [
    BrowserInfo(
      name: 'Google Chrome',
      appName: 'Google Chrome',
      appPath: '/Applications/Google Chrome.app',
      supportsWidevine: true,
    ),
    BrowserInfo(
      name: 'Microsoft Edge',
      appName: 'Microsoft Edge',
      appPath: '/Applications/Microsoft Edge.app',
      supportsWidevine: true,
    ),
    BrowserInfo(
      name: 'Brave Browser',
      appName: 'Brave Browser',
      appPath: '/Applications/Brave Browser.app',
      supportsWidevine: true,
    ),
    BrowserInfo(
      name: 'Firefox',
      appName: 'Firefox',
      appPath: '/Applications/Firefox.app',
      supportsWidevine: true,
    ),
  ];

  /// Detects installed desktop browsers that support Widevine CDM
  static List<BrowserInfo> getInstalledDrmBrowsers() {
    if (!AppPlatform.isMacOS) return const [];
    final installed = <BrowserInfo>[];
    for (final b in _macBrowsers) {
      try {
        if (Directory(b.appPath).existsSync() ||
            Directory('${Platform.environment['HOME']}/Applications/${b.appName}.app').existsSync()) {
          installed.add(b);
        }
      } catch (_) {}
    }
    return installed;
  }

  /// Checks if VLC is installed on macOS
  static bool isVlcInstalled() {
    if (!AppPlatform.isMacOS) return false;
    try {
      return Directory('/Applications/VLC.app').existsSync() ||
          Directory('${Platform.environment['HOME']}/Applications/VLC.app').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Launches the DRM web player in an external browser with Widevine CDM support.
  /// On macOS desktop, attempts to launch in standalone App Mode (--app=URL)
  /// so it renders as a pure, frameless player without browser clutter.
  static Future<bool> launchDrmPlayer({
    BuildContext? context,
    required Channel channel,
    String? preferredBrowser,
  }) async {
    final playerUrl = channel.inAppWebPlayerUrl ?? channel.webPlayerUrl ?? channel.streamUrl;
    debugPrint('[ExternalPlayerService] Launching DRM Player for #${channel.channelNumber}: $playerUrl');

    bool launched = false;
    String launchedVia = 'Default Browser';

    if (AppPlatform.isMacOS) {
      final browsersToTry = <BrowserInfo>[];
      if (preferredBrowser != null) {
        final match = _macBrowsers.where((b) => b.appName.toLowerCase() == preferredBrowser.toLowerCase());
        if (match.isNotEmpty) browsersToTry.add(match.first);
      }

      // Add detected installed browsers
      for (final b in getInstalledDrmBrowsers()) {
        if (!browsersToTry.any((x) => x.appName == b.appName)) {
          browsersToTry.add(b);
        }
      }

      // Fallback list of known Widevine browsers
      for (final b in _macBrowsers) {
        if (!browsersToTry.any((x) => x.appName == b.appName)) {
          browsersToTry.add(b);
        }
      }

      // 1. Try launching in standalone Chrome/Edge/Brave App Mode
      for (final browser in browsersToTry) {
        try {
          final res = await Process.run('open', [
            '-na',
            browser.appName,
            '--args',
            '--app=$playerUrl',
          ]);
          if (res.exitCode == 0) {
            launched = true;
            launchedVia = browser.name;
            debugPrint('[ExternalPlayerService] Successfully launched via ${browser.name} App Mode');
            break;
          } else {
            debugPrint('[ExternalPlayerService] ${browser.name} exitCode: ${res.exitCode}, stderr: ${res.stderr}');
          }
        } catch (e) {
          debugPrint('[ExternalPlayerService] Process.run error for ${browser.name}: $e');
        }
      }

      // 2. If app mode failed, try generic `open <url>`
      if (!launched) {
        try {
          final res = await Process.run('open', [playerUrl]);
          if (res.exitCode == 0) {
            launched = true;
            launchedVia = 'System Browser';
          }
        } catch (e) {
          debugPrint('[ExternalPlayerService] Generic open failed: $e');
        }
      }
    }

    // 3. Fallback to Flutter url_launcher (works reliably even in sandboxed environments)
    if (!launched) {
      try {
        final uri = Uri.parse(playerUrl);
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) {
          launchedVia = 'System Default Browser';
        }
      } catch (e) {
        debugPrint('[ExternalPlayerService] launchUrl failed: $e');
      }
    }

    if (context != null && context.mounted) {
      if (launched) {
        TvToast.info(context, 'Launched #${channel.channelNumber} in $launchedVia');
      } else {
        TvToast.error(context, 'Failed to launch external player. Please copy the URL.');
      }
    }

    return launched;
  }

  /// Launches an unencrypted stream (HLS / MP4) in VLC Media Player
  static Future<bool> launchInVlc({
    BuildContext? context,
    required String streamUrl,
  }) async {
    bool launched = false;
    if (AppPlatform.isMacOS) {
      try {
        final res = await Process.run('open', ['-a', 'VLC', streamUrl]);
        launched = (res.exitCode == 0);
      } catch (_) {}
    }

    if (!launched) {
      try {
        final uri = Uri.parse(streamUrl);
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    if (context != null && context.mounted) {
      if (launched) {
        TvToast.info(context, 'Opened stream in VLC Player');
      } else {
        TvToast.error(context, 'VLC Player could not be launched');
      }
    }

    return launched;
  }
}
