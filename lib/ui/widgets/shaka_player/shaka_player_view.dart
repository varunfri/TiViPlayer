import 'package:flutter/material.dart';
import 'shaka_player_stub.dart'
    if (dart.library.html) 'shaka_player_web.dart'
    as impl;

class ShakaPlayerView extends StatelessWidget {
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

  const ShakaPlayerView({
    super.key,
    required this.url,
    this.isPlaying = true,
    this.isMuted = false,
    this.drmLicenseUrl,
    this.headers,
    this.fit = BoxFit.contain,
    this.onPlay,
    this.onPause,
    this.onError,
    this.onLoaded,
  });

  @override
  Widget build(BuildContext context) {
    return impl.buildShakaPlayer(
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
}
