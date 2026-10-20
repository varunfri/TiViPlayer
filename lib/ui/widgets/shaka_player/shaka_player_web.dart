// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter_shaka/flutter_shaka.dart' as shaka;

Widget buildShakaPlayer({
  Key? key,
  required String url,
  required bool isPlaying,
  required bool isMuted,
  String? drmLicenseUrl,
  Map<String, String>? headers,
  BoxFit fit = BoxFit.contain,
  VoidCallback? onPlay,
  VoidCallback? onPause,
  ValueChanged<String>? onError,
  VoidCallback? onLoaded,
}) {
  return ShakaPlayerWeb(
    key: key,
    url: url,
    isPlaying: isPlaying,
    isMuted: isMuted,
    drmLicenseUrl: drmLicenseUrl,
    headers: headers,
    fit: fit,
    onPlay: onPlay,
    onPause: onPause,
    onError: onError,
    onLoaded: onLoaded,
  );
}

class ShakaPlayerWeb extends StatefulWidget {
  final String url;
  final bool isPlaying;
  final bool isMuted;
  final String? drmLicenseUrl;
  final Map<String, String>? headers;
  final BoxFit fit;
  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final ValueChanged<String>? onError;
  final VoidCallback? onLoaded;

  const ShakaPlayerWeb({
    super.key,
    required this.url,
    required this.isPlaying,
    required this.isMuted,
    this.drmLicenseUrl,
    this.headers,
    required this.fit,
    this.onPlay,
    this.onPause,
    this.onError,
    this.onLoaded,
  });

  @override
  State<ShakaPlayerWeb> createState() => _ShakaPlayerWebState();
}

class _ShakaPlayerWebState extends State<ShakaPlayerWeb> {
  static int _viewIdCounter = 0;
  late final String _viewType;
  html.VideoElement? _videoElement;
  shaka.Player? _shakaPlayer;
  bool _isDisposed = false;
  StreamSubscription? _playSub;
  StreamSubscription? _pauseSub;

  @override
  void initState() {
    super.initState();
    _viewType = 'shaka-video-view-${_viewIdCounter++}';
    _setupVideoElement();
    _initShaka();
  }

  void _setupVideoElement() {
    final video = html.VideoElement()
      ..autoplay = widget.isPlaying
      ..muted = widget.isMuted
      ..controls = false
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..style.backgroundColor = 'black'
      ..style.objectFit = widget.fit == BoxFit.cover ? 'cover' : 'contain';

    video.setAttribute('playsinline', 'true');
    video.setAttribute('webkit-playsinline', 'true');

    _playSub = video.onPlay.listen((_) {
      if (!_isDisposed) widget.onPlay?.call();
    });

    _pauseSub = video.onPause.listen((_) {
      if (!_isDisposed) widget.onPause?.call();
    });

    _videoElement = video;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => video);
  }

  Future<void> _initShaka() async {
    try {
      int retries = 0;
      while (!shaka.isLoaded && retries < 25) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_isDisposed) return;
        retries++;
      }

      if (!shaka.isLoaded) {
        debugPrint('[ShakaPlayerWeb] shaka library not loaded in window after timeout.');
        widget.onError?.call('Shaka Player library failed to load');
        return;
      }

      shaka.installPolyfills();

      if (!shaka.Player.isBrowserSupported()) {
        debugPrint('[ShakaPlayerWeb] Shaka Player is not supported on this browser.');
        widget.onError?.call('Shaka Player is not supported on this browser');
        return;
      }

      final player = shaka.Player(_videoElement!);
      _shakaPlayer = player;

      // Configure DRM if a license URL is provided
      if (widget.drmLicenseUrl != null && widget.drmLicenseUrl!.isNotEmpty) {
        player.configure({
          'drm': {
            'servers': {
              'com.widevine.alpha': widget.drmLicenseUrl,
            },
            'advanced': {
              'com.widevine.alpha': {
                'videoRobustness': 'SW_SECURE_CRYPTO',
                'audioRobustness': 'SW_SECURE_CRYPTO',
              }
            }
          }
        });
      }

      // Add error listener
      player.addEventListener('error', (dynamic event) {
        debugPrint('[ShakaPlayerWeb] Shaka internal error event: $event');
      });

      await _loadStream(widget.url);
    } catch (e) {
      debugPrint('[ShakaPlayerWeb] Initialization failed: $e');
      if (!_isDisposed) {
        widget.onError?.call('$e');
      }
    }
  }

  Future<void> _loadStream(String url) async {
    if (_shakaPlayer == null || _isDisposed) return;
    try {
      debugPrint('[ShakaPlayerWeb] Loading stream via Shaka Player: $url');
      await _shakaPlayer!.load(url);
      if (!_isDisposed) {
        widget.onLoaded?.call();
        if (widget.isPlaying) {
          try {
            await _videoElement?.play();
          } catch (playErr) {
            debugPrint('[ShakaPlayerWeb] Autoplay notice: $playErr');
          }
        }
      }
    } catch (e) {
      debugPrint('[ShakaPlayerWeb] Stream load error: $e');
      if (!_isDisposed) {
        widget.onError?.call('Shaka load failure: $e');
      }
    }
  }

  @override
  void didUpdateWidget(ShakaPlayerWeb oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_videoElement != null) {
      if (widget.isMuted != oldWidget.isMuted) {
        _videoElement!.muted = widget.isMuted;
      }

      if (widget.fit != oldWidget.fit) {
        _videoElement!.style.objectFit = widget.fit == BoxFit.cover ? 'cover' : 'contain';
      }

      if (widget.isPlaying != oldWidget.isPlaying) {
        if (widget.isPlaying) {
          _videoElement!.play().catchError((_) {});
        } else {
          _videoElement!.pause();
        }
      }
    }

    if (widget.url != oldWidget.url) {
      _loadStream(widget.url);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _playSub?.cancel();
    _pauseSub?.cancel();
    try {
      _shakaPlayer?.destroy();
    } catch (_) {}
    try {
      _videoElement?.pause();
      _videoElement?.src = '';
      _videoElement?.remove();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
