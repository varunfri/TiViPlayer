import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:video_player/video_player.dart' as vp;
import '../../models/channel.dart';
import '../../providers/tv_state_provider.dart';
import '../../services/screen_wake_service.dart';
import '../../services/app_platform.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/external_player_service.dart';
import '../../ui/theme.dart';
import 'tv_toast.dart';
import 'shaka_player/shaka_player_view.dart';
import '../../services/hls_manifest_prober.dart';

class VideoPlayerWidget extends StatefulWidget {
  final Channel? channel;
  final bool isMuted;
  final VideoScaleMode scaleMode;
  final bool isPlaying;
  final ValueChanged<bool>? onErrorChanged;

  const VideoPlayerWidget({
    super.key,
    required this.channel,
    this.isMuted = false,
    this.scaleMode = VideoScaleMode.cover,
    this.isPlaying = true,
    this.onErrorChanged,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  static final http.Client _httpClient = http.Client();

  // Desktop / macOS playback engine (libmpv)
  Player? _player;
  VideoController? _videoController;

  // Android playback engine (Google ExoPlayer / Media3 via video_player)
  vp.VideoPlayerController? _androidController;

  // Web playback engine (Google Shaka Player via flutter_shaka)
  String? _webStreamUrl;

  // In-App Web Player Engine (HTML5 Shaka Player + Widevine CDM for DRM streams on Mobile/Desktop WebView)
  WebViewController? _webViewController;
  bool _isUsingWebPlayer = false;

  bool _isInitializing = false;
  bool _isInitialized = false;
  String? _errorMessage;

  void _setErrorMessage(String? error) {
    final hadError = _errorMessage != null;
    _errorMessage = error;
    final hasError = _errorMessage != null;
    if (hadError != hasError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onErrorChanged?.call(hasError);
        }
      });
    }
  }

  bool _isBuffering = false;

  Timer? _bufferingDebounceTimer;
  Timer? _bufferingWatchdogTimer;
  StreamSubscription? _bufferingSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _bufferSubscription;

  // Auto-retry & diagnostics state
  Timer? _autoRetryTimer;
  int _autoRetryCountdown = 5;
  int _retryCount = 0;
  bool _isAutoRetrying = false;
  bool _showTechnicalDetails = false;

  @override
  void initState() {
    super.initState();
    if (AppPlatform.isAndroid) {
      try {
        final tvState = context.read<TvStateProvider>();
        tvState.registerPlaybackRateCallback((rate) {
          _androidController?.setPlaybackSpeed(rate);
        });
        tvState.registerSeekCallback((target) async {
          await _androidController?.seekTo(target);
        });
      } catch (_) {}
    } else if (AppPlatform.isDesktop) {
      _ensurePlayerInitialized();
    }
    if (widget.channel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.channel != null) {
          _openStream(widget.channel!.streamUrl);
        }
      });
    }
  }

  void _onAndroidControllerUpdate() {
    if (!mounted || _androidController == null) return;
    final val = _androidController!.value;
    if (val.hasError) {
      final err = val.errorDescription ?? 'Android ExoPlayer playback failure';
      debugPrint('[VideoPlayerWidget] Android ExoPlayer error: $err');
      if (AppPlatform.isMacOS &&
          widget.channel?.inAppWebPlayerUrl != null &&
          !_isUsingWebPlayer) {
        debugPrint(
          '[VideoPlayerWidget] ExoPlayer error, switching to In-App Web Player...',
        );
        _initInAppWebPlayer(widget.channel!.inAppWebPlayerUrl!);
        return;
      }
      if (_errorMessage == null) {
        setState(() {
          _setErrorMessage(err);
          _isInitializing = false;
          _isBuffering = false;
        });
        _startAutoRetry();
      }
    } else {
      if (val.isBuffering != _isBuffering) {
        setState(() {
          _isBuffering = val.isBuffering;
        });
      }
      if (val.isInitialized) {
        final tvState = context.read<TvStateProvider>();
        Duration buf = Duration.zero;
        if (val.buffered.isNotEmpty) {
          buf = val.buffered.last.end;
        }
        tvState.updatePlaybackProgress(
          position: val.position,
          duration: val.duration,
          buffer: buf,
        );
      }
    }
  }

  void _ensurePlayerInitialized() {
    if (_player != null && _videoController != null) return;

    try {
      final tvState = context.read<TvStateProvider>();
      _player = Player(
        configuration: PlayerConfiguration(bufferSize: tvState.bufferSizeBytes),
      );

      _videoController = VideoController(
        _player!,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );

      try {
        _player?.setVolume(tvState.isMuted ? 0.0 : (tvState.volume * 100.0));
        _player?.setRate(tvState.playbackRate);
        tvState.registerPlayer(_player);
        tvState.registerSeekCallback((target) async {
          await _player?.seek(target);
        });
        (_player!.platform as dynamic)?.setProperty(
          'user-agent',
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
        );
        (_player!.platform as dynamic)?.setProperty('network-timeout', '20');
        (_player!.platform as dynamic)?.setProperty(
          'demuxer-lavf-o',
          'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
        );
      } catch (_) {}

      _bufferingSubscription = _player!.stream.buffering.listen((isBuffering) {
        if (!mounted) return;
        if (isBuffering) {
          _bufferingDebounceTimer?.cancel();
          _bufferingDebounceTimer = Timer(const Duration(milliseconds: 400), () {
            if (mounted && (_player?.state.buffering ?? false)) {
              setState(() {
                _isBuffering = true;
              });
              // Safety watchdog: prevent indefinite spinner if stream events desync
              _bufferingWatchdogTimer?.cancel();
              _bufferingWatchdogTimer = Timer(const Duration(seconds: 5), () {
                if (mounted && _isBuffering) {
                  setState(() {
                    _isBuffering = false;
                  });
                }
              });
            }
          });
        } else {
          _bufferingDebounceTimer?.cancel();
          _bufferingWatchdogTimer?.cancel();
          if (_isBuffering) {
            setState(() {
              _isBuffering = false;
            });
          }
        }
      });

      _playingSubscription = _player!.stream.playing.listen((isPlaying) {
        if (!mounted) return;
        if (isPlaying && _isBuffering) {
          _bufferingDebounceTimer?.cancel();
          _bufferingWatchdogTimer?.cancel();
          setState(() {
            _isBuffering = false;
          });
        }
      });

      _durationSubscription = _player!.stream.duration.listen((dur) {
        if (!mounted) return;
        final tvState = context.read<TvStateProvider>();
        tvState.updatePlaybackProgress(
          position: _player?.state.position ?? Duration.zero,
          duration: dur,
          buffer: _player?.state.buffer,
        );
      });

      _bufferSubscription = _player!.stream.buffer.listen((buf) {
        if (!mounted) return;
        final tvState = context.read<TvStateProvider>();
        tvState.updatePlaybackProgress(
          position: _player?.state.position ?? Duration.zero,
          duration: _player?.state.duration ?? Duration.zero,
          buffer: buf,
        );
      });

      _positionSubscription = _player!.stream.position.listen((pos) {
        if (!mounted) return;
        if (pos > Duration.zero && _isBuffering) {
          _bufferingDebounceTimer?.cancel();
          _bufferingWatchdogTimer?.cancel();
          setState(() {
            _isBuffering = false;
          });
        }
        final tvState = context.read<TvStateProvider>();
        tvState.updatePlaybackProgress(
          position: pos,
          duration: _player?.state.duration ?? Duration.zero,
          buffer: _player?.state.buffer,
        );
      });

      _errorSubscription = _player!.stream.error.listen((error) {
        if (!mounted || _errorMessage != null) return;
        debugPrint('[VideoPlayerWidget] stream.error: $error');

        // Ignore transient browser DOM play interruptions on Web
        final lower = error.toLowerCase();
        if (lower.contains('interrupted because the media was removed') ||
            lower.contains('play() request was interrupted') ||
            lower.contains('notallowederror') ||
            lower.contains('user didn\'t interact') ||
            lower.contains('abort_err')) {
          debugPrint(
            '[VideoPlayerWidget] Ignored transient Web DOM play interruption: $error',
          );
          return;
        }

        // If it's a TCP timeout (0xffffffc4 / -60 / ETIMEDOUT) or temporary connection stall,
        // retry the desktop stream automatically rather than falling back to webview
        if (lower.contains('ffurl_read') ||
            lower.contains('0xffffffc4') ||
            lower.contains('connection reset') ||
            lower.contains('connection refused') ||
            lower.contains('timed out') ||
            lower.contains('timeout')) {
          debugPrint(
            '[VideoPlayerWidget] Transient network read timeout ($error), initiating auto-reconnect...',
          );
          setState(() {
            _setErrorMessage(error);
            _isInitializing = false;
            _isBuffering = false;
          });
          _startAutoRetry();
          return;
        }

        if (!AppPlatform.isWeb &&
            widget.channel?.inAppWebPlayerUrl != null &&
            !_isUsingWebPlayer) {
          debugPrint(
            '[VideoPlayerWidget] Desktop stream error ($error), switching to In-App Web Player: ${widget.channel!.inAppWebPlayerUrl}',
          );
          _initInAppWebPlayer(widget.channel!.inAppWebPlayerUrl!);
          return;
        }
        setState(() {
          _setErrorMessage(error);
          _isInitializing = false;
          _isBuffering = false;
        });
        _startAutoRetry();
      });
    } catch (e) {
      debugPrint('[VideoPlayerWidget] Native player init notice: $e');
    }
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.channel?.streamUrl != oldWidget.channel?.streamUrl) {
      _cancelAutoRetry();
      _bufferingDebounceTimer?.cancel();
      _retryCount = 0;
      _showTechnicalDetails = false;
      _isBuffering = false;
      if (widget.channel != null) {
        _openStream(widget.channel!.streamUrl);
      } else {
        if (AppPlatform.isAndroid) {
          _androidController?.pause();
        } else if (AppPlatform.isWeb) {
          _webStreamUrl = null;
        } else {
          _player?.stop();
        }
        setState(() {
          _isInitialized = false;
        });
      }
    } else {
      // 1. Dynamic Mute / Unmute reactive handler
      if (widget.isMuted != oldWidget.isMuted) {
        if (_isUsingWebPlayer && _webViewController != null) {
          _webViewController!.runJavaScript('''
            (function() {
              const v = document.getElementById("jiotv_go_player") || document.querySelector("video");
              if (v) v.muted = ${widget.isMuted};
            })();
          ''');
        } else if (AppPlatform.isAndroid) {
          final tvState = context.read<TvStateProvider>();
          _androidController?.setVolume(widget.isMuted ? 0.0 : tvState.volume);
        } else if (_player != null) {
          final tvState = context.read<TvStateProvider>();
          _player!.setVolume(widget.isMuted ? 0.0 : (tvState.volume * 100.0));
        }
      }
      // 2. Dynamic Play / Stop reactive handler
      if (widget.isPlaying != oldWidget.isPlaying) {
        ScreenWakeService.keepScreenOn(widget.isPlaying);
        if (_isUsingWebPlayer && _webViewController != null) {
          _webViewController!.runJavaScript('''
            (function() {
              const v = document.getElementById("jiotv_go_player") || document.querySelector("video");
              if (v) {
                if (${widget.isPlaying}) {
                  v.play().catch(function() {});
                } else {
                  v.pause();
                }
              }
            })();
          ''');
        } else if (AppPlatform.isAndroid) {
          if (widget.isPlaying) {
            _androidController?.play();
          } else {
            _androidController?.pause();
          }
        } else if (_player != null) {
          if (widget.isPlaying) {
            _player!.play();
          } else {
            _player!.pause();
          }
        }
      }
    }
  }

  Future<void> _openStream(String streamUrl) async {
    _disposeWebPlayer();
    _cancelAutoRetry();
    _bufferingDebounceTimer?.cancel();
    if (AppPlatform.isDesktop) {
      _ensurePlayerInitialized();
    }

    setState(() {
      _isInitializing = true;
      _isInitialized = false;
      _setErrorMessage(null);
    });

    final tvState = context.read<TvStateProvider>();
    final double initialVolume = tvState.volume;
    final double initialPlaybackRate = tvState.playbackRate;

    try {
      final List<String> candidateUrls = [];

      final Map<String, String> requestHeaders = {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
        'Accept': '*/*',
        'Connection': 'keep-alive',
      };

      // Extract numeric channelId if available:
      String? channelId;
      if (widget.channel?.tvgId != null &&
          RegExp(r'^\d+$').hasMatch(widget.channel!.tvgId!)) {
        channelId = widget.channel!.tvgId;
      } else {
        final match = RegExp(
          r'/(?:live/)?(?:mpd/)?(\d+)(?:\.m3u8|\.mpd)?(?:\?|$)',
        ).firstMatch(streamUrl);
        channelId = match?.group(1);
      }

      // DRM License and Headers setup for ExoPlayer (Android) & Shaka Player:
      String? drmLicenseUrl = widget.channel?.drmLicenseUrl;
      if (drmLicenseUrl == null || drmLicenseUrl.isEmpty) {
        if (channelId != null &&
            (streamUrl.contains('/mpd') || widget.channel?.hasDrm == true)) {
          try {
            final u = Uri.parse(streamUrl);
            drmLicenseUrl = '${u.origin}/live/key/$channelId';
          } catch (_) {}
        }
      }

      if (drmLicenseUrl != null && drmLicenseUrl.isNotEmpty) {
        requestHeaders['x-drm-license-url'] = drmLicenseUrl;
      }

      if (widget.channel?.drmHeaders != null) {
        try {
          final decoded = jsonDecode(widget.channel!.drmHeaders!);
          if (decoded is Map) {
            decoded.forEach((key, value) {
              requestHeaders[key.toString()] = value.toString();
              requestHeaders['x-drm-header-${key.toString()}'] = value
                  .toString();
            });
          }
        } catch (_) {}
      }

      // Smart Stream Adaptation:
      // JioTV Go exports both DASH (/mpd/{id} or /live/mpd/{id}) and unencrypted AES-128 HLS (/live/{id}.m3u8).
      // Many channels (such as 143, 144, 154, 762) have an unencrypted AES-128 HLS stream at /live/{id}.m3u8
      // which plays directly in ExoPlayer (Android) and media_kit (macOS, Windows, Web) without Widevine CDM.

      if (channelId != null &&
          (streamUrl.contains('/mpd') || streamUrl.contains('/live/'))) {
        try {
          final u = Uri.parse(streamUrl);
          final hlsCandidate = '${u.origin}/live/$channelId.m3u8';
          if (hlsCandidate != streamUrl) {
            final isHlsValid = await _isStreamUrlReachable(
              hlsCandidate,
              requestHeaders,
            );
            if (isHlsValid) {
              candidateUrls.add(hlsCandidate);
              debugPrint(
                '[VideoPlayerWidget] Found working unencrypted HLS stream: $hlsCandidate',
              );
            } else {
              debugPrint(
                '[VideoPlayerWidget] HLS candidate is unavailable (404) for $hlsCandidate',
              );
            }
          }
        } catch (_) {}
      }

      // Always ensure the streamUrl is present in candidates
      if (!candidateUrls.contains(streamUrl)) {
        candidateUrls.add(streamUrl);
      }

      // Android Candidate Fallback Extensions:
      if (AppPlatform.isAndroid) {
        // 1. Android Emulator Host loopback mapping:
        if (streamUrl.contains('localhost') ||
            streamUrl.contains('127.0.0.1')) {
          final emulatorUrl = streamUrl
              .replaceAll('localhost', '10.0.2.2')
              .replaceAll('127.0.0.1', '10.0.2.2');
          if (!candidateUrls.contains(emulatorUrl)) {
            candidateUrls.add(emulatorUrl);
          }
        }
        // 2. HTTPS to HTTP cleartext fallback (for local media servers with optional SSL):
        if (streamUrl.startsWith('https://')) {
          final httpFallback = 'http://${streamUrl.substring(8)}';
          if (!candidateUrls.contains(httpFallback)) {
            candidateUrls.add(httpFallback);
          }
        }
      }

      // Probe HLS manifest headers to differentiate RFC 8216 VOD vs Live stream
      final probeCandidate = candidateUrls.firstWhere(
        (u) => u.toLowerCase().contains('.m3u8'),
        orElse: () => candidateUrls.first,
      );
      final isDirectMediaFile =
          probeCandidate.toLowerCase().contains('.mp4') ||
          probeCandidate.toLowerCase().contains('.mkv') ||
          probeCandidate.toLowerCase().contains('.avi') ||
          probeCandidate.toLowerCase().contains('.mov') ||
          probeCandidate.toLowerCase().contains('.ts');

      if (!isDirectMediaFile &&
          (probeCandidate.toLowerCase().contains('.m3u8') ||
              probeCandidate.toLowerCase().contains('/hls') ||
              (widget.channel?.isLive != false &&
                  !probeCandidate.toLowerCase().contains('/stream/')))) {
        HlsManifestProber.probeStream(
              probeCandidate,
              customHeaders: requestHeaders,
            )
            .then((probe) {
              if (!mounted) return;
              final tvState = context.read<TvStateProvider>();
              if (probe.isVod) {
                tvState.setManifestStreamType(
                  isVod: true,
                  probedDuration: probe.totalDuration,
                );
              } else if (probe.isLive && probe.mediaSequence != null) {
                tvState.setManifestStreamType(isVod: false);
              }
            })
            .catchError((_) {});
      }

      // If no working unencrypted HLS stream was found on macOS desktop DRM stream:
      if (AppPlatform.isMacOS &&
          candidateUrls.length == 1 &&
          widget.channel?.hasDrm == true) {
        debugPrint(
          '[VideoPlayerWidget] macOS DRM stream detected with no unencrypted HLS variant.',
        );
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _isInitialized = false;
            _isUsingWebPlayer = false;
            _setErrorMessage(
              'Channel #${widget.channel?.channelNumber ?? ""} is protected with Google Widevine DRM.\nmacOS WebKit does not include Widevine CDM. Launch the external player in Chrome/Edge or default browser to watch this broadcast.',
            );
          });
        }
        return;
      }

      if (AppPlatform.isWeb) {
        // Web Platform Engine: Google Shaka Player (flutter_shaka)
        _webStreamUrl = candidateUrls.isNotEmpty
            ? candidateUrls.first
            : streamUrl;
        debugPrint(
          '[VideoPlayerWidget] Web Engine selected Shaka Player stream: $_webStreamUrl',
        );
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _isInitialized = true;
            _setErrorMessage(null);
            _retryCount = 0;
          });
          ScreenWakeService.keepScreenOn(widget.isPlaying);
        }
        return;
      }

      if (AppPlatform.isAndroid) {
        // Android Engine: Native Google ExoPlayer / Media3 via video_player
        if (_androidController != null) {
          final old = _androidController!;
          _androidController = null;
          old.removeListener(_onAndroidControllerUpdate);
          old
              .pause()
              .then((_) => old.dispose())
              .catchError((_) => old.dispose());
        }

        Object? lastError;
        bool initializedSuccessfully = false;

        List<vp.VideoFormat?> getFormatHintsForUrl(String url) {
          final lower = url.toLowerCase();
          if (lower.contains('.mpd') ||
              lower.contains('/dash') ||
              lower.contains('/mpd/')) {
            return [vp.VideoFormat.dash];
          }
          if (lower.contains('.ism')) {
            return [vp.VideoFormat.ss];
          }
          if (lower.contains('.m3u8') ||
              lower.contains('/hls') ||
              lower.contains('format=m3u8') ||
              lower.contains('type=m3u8')) {
            return [vp.VideoFormat.hls, vp.VideoFormat.other];
          }
          if (lower.contains('.mp4') ||
              lower.contains('.mkv') ||
              lower.contains('.avi') ||
              lower.contains('.ts') ||
              lower.contains('/stream/') ||
              lower.contains('/movie/') ||
              lower.contains('/series/') ||
              widget.channel?.isVod == true) {
            return [vp.VideoFormat.other, vp.VideoFormat.hls];
          }
          return [vp.VideoFormat.hls, vp.VideoFormat.other];
        }

        candidateLoop:
        for (int i = 0; i < candidateUrls.length; i++) {
          final currentUrl = candidateUrls[i];
          final formatHints = getFormatHintsForUrl(currentUrl);

          for (final formatHint in formatHints) {
            final uri = Uri.parse(currentUrl);
            final controller = vp.VideoPlayerController.networkUrl(
              uri,
              formatHint: formatHint,
              httpHeaders: requestHeaders,
            );
            _androidController = controller;
            controller.addListener(_onAndroidControllerUpdate);

            try {
              await controller.initialize();
              initializedSuccessfully = true;
              await controller.setVolume(widget.isMuted ? 0.0 : initialVolume);
              await controller.setPlaybackSpeed(initialPlaybackRate);
              if (widget.isPlaying) {
                await controller.play();
              }
              break candidateLoop;
            } catch (initErr) {
              lastError = initErr;
              debugPrint(
                '[VideoPlayerWidget] Candidate failed ($currentUrl, hint: $formatHint): $initErr',
              );
              controller.removeListener(_onAndroidControllerUpdate);
              await controller.dispose();
              _androidController = null;
            }
          }
        }

        if (!initializedSuccessfully) {
          if (AppPlatform.isMacOS &&
              widget.channel?.inAppWebPlayerUrl != null) {
            debugPrint(
              '[VideoPlayerWidget] All Android ExoPlayer candidates failed. Seamlessly launching In-App Web Player...',
            );
            await _initInAppWebPlayer(widget.channel!.inAppWebPlayerUrl!);
            return;
          }
          throw lastError ?? Exception('Failed to initialize playback');
        }

        if (mounted) {
          setState(() {
            _isInitializing = false;
            _isInitialized = true;
            _retryCount = 0;
          });
          ScreenWakeService.keepScreenOn(widget.isPlaying);
        }
      } else {
        // Desktop / macOS Engine: media_kit (libmpv)
        if (_isInitialized) {
          await _player!.stop();
        }

        bool openedSuccessfully = false;
        Object? lastError;

        final userAgents = [
          requestHeaders['User-Agent'] ??
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
          'AppleCoreMedia/1.0.0.19G71 (Apple TV; U; CPU OS 15_6 like Mac OS X)',
          'VLC/3.0.18 LibVLC/3.0.18',
        ];

        for (final currentUrl in candidateUrls) {
          for (final ua in userAgents) {
            try {
              final headers = Map<String, String>.from(requestHeaders);
              headers['User-Agent'] = ua;
              try {
                (_player!.platform as dynamic)?.setProperty('user-agent', ua);
              } catch (_) {}

              await _player!.open(
                Media(currentUrl, httpHeaders: headers),
                play: widget.isPlaying,
              );
              await _player!.setVolume(
                widget.isMuted ? 0.0 : (initialVolume * 100.0),
              );
              await _player!.setRate(initialPlaybackRate);
              openedSuccessfully = true;
              break;
            } catch (desktopErr) {
              lastError = desktopErr;
              debugPrint(
                '[VideoPlayerWidget] Desktop stream candidate error on $currentUrl (UA: $ua): $desktopErr',
              );
            }
          }
          if (openedSuccessfully) break;
        }

        if (!openedSuccessfully) {
          if (!AppPlatform.isWeb && widget.channel?.inAppWebPlayerUrl != null) {
            debugPrint(
              '[VideoPlayerWidget] Desktop playback engine failed. Seamlessly launching In-App Web Player...',
            );
            await _initInAppWebPlayer(widget.channel!.inAppWebPlayerUrl!);
            return;
          }
          throw lastError ?? Exception('Desktop playback engine failed');
        }

        if (mounted) {
          setState(() {
            _isInitializing = false;
            _isInitialized = true;
            _retryCount = 0;
          });
          ScreenWakeService.keepScreenOn(widget.isPlaying);
        }
      }
    } catch (e) {
      if (AppPlatform.isMacOS &&
          widget.channel?.inAppWebPlayerUrl != null &&
          !_isUsingWebPlayer) {
        debugPrint(
          '[VideoPlayerWidget] Stream initialization error: $e. Seamlessly falling back to In-App Web Player...',
        );
        await _initInAppWebPlayer(widget.channel!.inAppWebPlayerUrl!);
        return;
      }
      if (mounted) {
        // Cold-start seamless recovery: for proxies warming up, silently retry up to 2 times
        // keeping the loading spinner active before splashing an error screen
        if (_retryCount < 2 &&
            widget.channel?.hasDrm != true &&
            !streamUrl.contains('/mpd/')) {
          _retryCount++;
          await Future.delayed(const Duration(milliseconds: 1200));
          if (mounted && widget.channel?.streamUrl == streamUrl) {
            _openStream(streamUrl);
          }
          return;
        }

        String msg = '$e';
        if (widget.channel?.hasDrm == true || streamUrl.contains('/mpd/')) {
          msg =
              'Protected DRM Stream (${widget.channel!.drmType?.toUpperCase() ?? "WIDEVINE"}). Hardware CDM required: $e';
        }
        setState(() {
          _isInitializing = false;
          _isInitialized = false;
          _setErrorMessage(msg);
        });
        _startAutoRetry();
      }
    }
  }

  void _startAutoRetry() {
    _autoRetryTimer?.cancel();
    if (_retryCount >= 4 || widget.channel?.hasDrm == true) {
      ScreenWakeService.keepScreenOn(false);
      setState(() {
        _isAutoRetrying = false;
      });
      return;
    }

    setState(() {
      _autoRetryCountdown = 5;
      _isAutoRetrying = true;
    });

    _autoRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoRetryCountdown <= 1) {
        timer.cancel();
        _isAutoRetrying = false;
        _retryCount++;
        if (widget.channel != null) {
          _openStream(widget.channel!.streamUrl);
        }
      } else {
        setState(() {
          _autoRetryCountdown--;
        });
      }
    });
  }

  void _cancelAutoRetry() {
    _autoRetryTimer?.cancel();
    if (_isAutoRetrying && mounted) {
      setState(() {
        _isAutoRetrying = false;
      });
    }
  }

  Future<bool> _isStreamUrlReachable(
    String url,
    Map<String, String> headers,
  ) async {
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers.addAll(headers)
        ..followRedirects = true
        ..maxRedirects = 3;
      final streamedResponse = await _httpClient
          .send(req)
          .timeout(const Duration(milliseconds: 3500));
      streamedResponse.stream.listen((_) {}).cancel();
      return streamedResponse.statusCode >= 200 &&
          streamedResponse.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Future<void> _initInAppWebPlayer(String url) async {
    if (AppPlatform.isWeb) {
      debugPrint(
        '[VideoPlayerWidget] In-App webview not supported on Flutter Web.',
      );
      return;
    }
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('.m3u8') ||
        lowerUrl.contains('.ts') ||
        lowerUrl.contains('.mpd')) {
      debugPrint(
        '[VideoPlayerWidget] In-App Web Player cannot load raw media stream ($url). Aborting web fallback.',
      );
      return;
    }
    await _stopNativePlayback();
    _cancelAutoRetry();

    setState(() {
      _isInitializing = true;
      _isInitialized = false;
      _isUsingWebPlayer = true;
      _setErrorMessage(null);
    });

    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted);

      if (AppPlatform.isMobile) {
        try {
          controller.setBackgroundColor(Colors.black);
        } catch (_) {}
      }

      controller.setOnConsoleMessage((message) {
        debugPrint(
          '[InAppWebPlayer JS] ${message.level.name}: ${message.message}',
        );
        final lower = message.message.toLowerCase();
        if (lower.contains('widevine not supported') ||
            lower.contains('requested_key_system_config_unsupported') ||
            lower.contains('shaka player critical error 6001') ||
            lower.contains('widevine drm error: 6001')) {
          if (AppPlatform.isMacOS && mounted && _errorMessage == null) {
            setState(() {
              _isInitializing = false;
              _isInitialized = false;
              _isUsingWebPlayer = false;
              _setErrorMessage(
                'Widevine DRM is not supported on macOS WebKit.\nThis channel requires Google Widevine CDM (supported on Android TV & Android devices).',
              );
            });
          }
        }
      });

      controller.addJavaScriptChannel(
        'FlutterHost',
        onMessageReceived: (JavaScriptMessage msg) {
          debugPrint('[InAppWebPlayer FlutterHost] ${msg.message}');
          final text = msg.message;
          if (text.startsWith('WIDEVINE_UNSUPPORTED')) {
            if (mounted && AppPlatform.isMacOS) {
              setState(() {
                _isInitializing = false;
                _isInitialized = false;
                _isUsingWebPlayer = false;
                _setErrorMessage(
                  'Widevine DRM stream detected.\nmacOS WebKit does not support Google Widevine CDM. This channel will play seamlessly on Android TV and Android devices.',
                );
              });
            }
          } else if (text == 'PLAYING') {
            if (mounted) {
              setState(() {
                _isInitializing = false;
                _isInitialized = true;
                _isBuffering = false;
                _setErrorMessage(null);
              });
              ScreenWakeService.keepScreenOn(widget.isPlaying);
            }
          }
        },
      );

      if (AppPlatform.isAndroid &&
          controller.platform is AndroidWebViewController) {
        final androidController =
            controller.platform as AndroidWebViewController;
        androidController.setOnPlatformPermissionRequest((request) {
          debugPrint(
            '[VideoPlayerWidget] In-app Web Player granting permission: ${request.types}',
          );
          request.grant();
        });
        androidController.setMediaPlaybackRequiresUserGesture(false);
      }

      final navigationDelegate = NavigationDelegate(
        onNavigationRequest: (NavigationRequest request) {
          if (request.url.contains('/player/')) {
            debugPrint(
              '[VideoPlayerWidget] Blocked redirect to broken /player/ endpoint: ${request.url}',
            );
            if (AppPlatform.isMacOS && mounted) {
              setState(() {
                _isInitializing = false;
                _isInitialized = false;
                _isUsingWebPlayer = false;
                _setErrorMessage(
                  'Widevine DRM stream detected.\nmacOS WebKit does not support Google Widevine CDM. This channel will play seamlessly on Android TV and Android devices.',
                );
              });
            }
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (pageUrl) {
          debugPrint('[VideoPlayerWidget] In-app Web Player loading: $pageUrl');
          if (pageUrl.contains('/player/')) {
            debugPrint(
              '[VideoPlayerWidget] Caught redirect to /player/, restoring /mpd/ URL...',
            );
            controller.loadRequest(Uri.parse(url));
          }
        },
        onPageFinished: (pageUrl) {
          debugPrint(
            '[VideoPlayerWidget] In-app Web Player finished loading: $pageUrl',
          );
          if (pageUrl == 'about:blank') return;
          controller.runJavaScript('''
            (function() {
              try {
                // Prevent JavaScript inside player_drm.html from redirecting to /player/
                const origReplace = window.location.replace;
                window.location.replace = function(u) {
                  if (typeof u === "string" && u.includes("/player/")) {
                    console.warn("Prevented redirect to /player/:", u);
                    if (window.FlutterHost) {
                      window.FlutterHost.postMessage("WIDEVINE_UNSUPPORTED:redirect_to_player");
                    }
                    return;
                  }
                  origReplace.call(window.location, u);
                };

                const style = document.createElement("style");
                style.innerHTML = ".shaka-controls-container { display: none !important; } .unmute-overlay { display: none !important; } body { overflow: hidden !important; background-color: black !important; }";
                document.head.appendChild(style);

                const v = document.getElementById("jiotv_go_player") || document.querySelector("video");
                if (v) {
                  v.muted = ${widget.isMuted};
                  v.addEventListener("playing", function() {
                    if (window.FlutterHost) window.FlutterHost.postMessage("PLAYING");
                  });
                  v.play().catch(function() {});
                }
                const btn = document.getElementById("unmute-btn");
                if (btn) btn.click();

                // Proactively detect Widevine CDM support
                if (!window.navigator.requestMediaKeySystemAccess) {
                  if (window.FlutterHost) window.FlutterHost.postMessage("WIDEVINE_UNSUPPORTED:no_eme");
                } else {
                  window.navigator.requestMediaKeySystemAccess("com.widevine.alpha", [
                    { initDataTypes: ["cenc"], videoCapabilities: [{ contentType: 'video/mp4; codecs="avc1.42E01E"' }] }
                  ]).catch(function(err) {
                    if (window.FlutterHost) window.FlutterHost.postMessage("WIDEVINE_UNSUPPORTED:" + err);
                  });
                }
              } catch(e) {}
            })();
          ''');
          if (mounted && _errorMessage == null) {
            setState(() {
              _isInitializing = false;
              _isInitialized = true;
              _retryCount = 0;
            });
            ScreenWakeService.keepScreenOn(widget.isPlaying);
          }
        },
        onWebResourceError: (err) {
          debugPrint(
            '[VideoPlayerWidget] In-app Web Player resource error: ${err.description} (${err.errorCode})',
          );
        },
      );

      if (AppPlatform.isAndroid &&
          navigationDelegate.platform is AndroidNavigationDelegate) {
        final androidDelegate =
            navigationDelegate.platform as AndroidNavigationDelegate;
        androidDelegate.setOnSSlAuthError((error) => error.proceed());
      }

      controller.setNavigationDelegate(navigationDelegate);
      _webViewController = controller;
      await controller.loadRequest(Uri.parse(url));
    } catch (e) {
      debugPrint(
        '[VideoPlayerWidget] Failed to initialize in-app web player: $e',
      );
      if (mounted) {
        setState(() {
          _setErrorMessage('In-app player failed: $e');
          _isInitializing = false;
          _isUsingWebPlayer = false;
        });
        _startAutoRetry();
      }
    }
  }

  void _disposeWebPlayer() {
    if (_webViewController != null) {
      try {
        _webViewController!.loadRequest(Uri.parse('about:blank'));
      } catch (_) {}
      _webViewController = null;
    }
    _isUsingWebPlayer = false;
  }

  void _disposeAndroidPlayer() {
    _disposeWebPlayer();
    _bufferingDebounceTimer?.cancel();
    _bufferingWatchdogTimer?.cancel();
    try {
      context.read<TvStateProvider>().registerSeekCallback(null);
    } catch (_) {}
    if (_androidController != null) {
      final old = _androidController!;
      _androidController = null;
      old.removeListener(_onAndroidControllerUpdate);
      old.pause().then((_) => old.dispose()).catchError((_) => old.dispose());
    }
    _isBuffering = false;
    _isInitialized = false;
  }

  Future<void> _stopNativePlayback() async {
    _bufferingDebounceTimer?.cancel();
    _bufferingWatchdogTimer?.cancel();
    if (AppPlatform.isAndroid) {
      if (_androidController != null) {
        try {
          await _androidController!.pause();
        } catch (_) {}
      }
    } else if (AppPlatform.isWeb) {
      _webStreamUrl = null;
    } else {
      if (_player != null) {
        try {
          await _player!.stop();
        } catch (_) {}
      }
    }
    _isBuffering = false;
  }

  void _disposePlayer() {
    _disposeWebPlayer();
    _bufferingDebounceTimer?.cancel();
    _bufferingWatchdogTimer?.cancel();
    _bufferingSubscription?.cancel();
    _errorSubscription?.cancel();
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _bufferSubscription?.cancel();
    _bufferingSubscription = null;
    _errorSubscription = null;
    _playingSubscription = null;
    _positionSubscription = null;
    _durationSubscription = null;
    _bufferSubscription = null;
    if (_player != null) {
      try {
        final provider = context.read<TvStateProvider>();
        if (provider.activePlayer == _player) {
          provider.registerPlayer(null);
          provider.registerSeekCallback(null);
        }
      } catch (_) {}
      final playerToDispose = _player;
      _player = null;
      _videoController = null;
      try {
        playerToDispose?.stop();
        playerToDispose?.dispose();
      } catch (_) {}
    }
    _isBuffering = false;
    _isInitialized = false;
  }

  @override
  void dispose() {
    ScreenWakeService.keepScreenOn(false);
    _disposeWebPlayer();
    if (AppPlatform.isAndroid) {
      try {
        context.read<TvStateProvider>().registerPlaybackRateCallback(null);
        context.read<TvStateProvider>().registerSeekCallback(null);
      } catch (_) {}
      _disposeAndroidPlayer();
    } else {
      _disposePlayer();
    }
    _cancelAutoRetry();
    widget.onErrorChanged?.call(false);
    super.dispose();
  }

  Map<String, dynamic> _categorizeError(String error, Channel? channel) {
    final lower = error.toLowerCase();
    final bool isDrmStream =
        channel?.hasDrm == true ||
        lower.contains('drm') ||
        lower.contains('widevine') ||
        lower.contains('playready') ||
        lower.contains('clearkey') ||
        lower.contains('fairplay') ||
        (channel?.streamUrl.contains('/mpd') == true &&
            (lower.contains('404') ||
                lower.contains('mediacodec') ||
                lower.contains('playback failure') ||
                lower.contains('source error') ||
                lower.contains('failed to initialize')));

    if (isDrmStream) {
      return {
        'icon': Icons.security_rounded,
        'color': const Color(0xFF06B6D4), // Vibrant Electric Cyan
        'glowColor': const Color(0xFF00E5FF),
        'badge': 'WIDEVINE DRM PROTECTED',
        'title': 'DRM Encrypted Broadcast',
        'desc': AppPlatform.isMacOS
            ? 'Channel #${channel?.channelNumber ?? ""} (${channel?.name ?? ""}) requires Google Widevine CDM. macOS libmpv does not bundle Widevine; click below to launch in Chrome/Edge with hardware DRM or use an external player.'
            : 'Channel #${channel?.channelNumber ?? ""} (${channel?.name ?? ""}) requires hardware DRM decryption. Native hardware pipeline initializing.',
        'isDrm': true,
        'isNoSignal': false,
      };
    }

    if (lower.contains('500') ||
        lower.contains('internal server error') ||
        lower.contains('target vector')) {
      return {
        'icon': Icons.dns_rounded,
        'color': const Color(0xFFEF4444), // Crimson
        'glowColor': const Color(0xFFF87171),
        'badge': 'HTTP 500 SERVER ERROR',
        'title': 'Upstream Ingest Server Error',
        'desc':
            'The stream proxy or broadcaster server returned an internal 500 error while parsing upstream target streams.',
        'isDrm': false,
        'isNoSignal': false,
      };
    }

    if (lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('bad gateway') ||
        lower.contains('service unavailable') ||
        lower.contains('host offline')) {
      return {
        'icon': Icons.cloud_sync_rounded,
        'color': const Color(0xFFF59E0B), // Amber
        'glowColor': const Color(0xFFFBBF24),
        'badge': 'HTTP 503 SERVICE UNAVAILABLE',
        'title': 'Transponder Warming Up',
        'desc':
            'The remote streaming host is warming up upstream sessions or temporarily unreachable. Automatic retry in progress...',
        'isDrm': false,
        'isNoSignal': false,
      };
    }

    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('access denied')) {
      return {
        'icon': Icons.block_rounded,
        'color': const Color(0xFFF97316), // Orange
        'glowColor': const Color(0xFFFB923C),
        'badge': 'HTTP 403 FORBIDDEN',
        'title': 'Access Forbidden / Token Expired',
        'desc':
            'The broadcast CDN server rejected this session. The streaming token, key signature, or user-agent has expired.',
        'isDrm': false,
        'isNoSignal': false,
      };
    }

    if (lower.contains('404') || lower.contains('not found')) {
      return {
        'icon': Icons.satellite_alt_rounded,
        'color': const Color(0xFFEF4444), // Crimson
        'glowColor': const Color(0xFFF87171),
        'badge': 'NO SIGNAL (404)',
        'title': 'Signal Lost / Feed Offline',
        'desc':
            'The streaming transponder returned 404 Not Found. This channel feed is temporarily offline or relocated.',
        'isDrm': false,
        'isNoSignal': true,
      };
    }

    if (lower.contains('codec') ||
        lower.contains('unsupported') ||
        lower.contains('format') ||
        lower.contains('demux')) {
      return {
        'icon': Icons.video_file_rounded,
        'color': const Color(0xFFA855F7), // Purple
        'glowColor': const Color(0xFFC084FC),
        'badge': 'FORMAT UNSUPPORTED',
        'title': 'Incompatible Stream Codec',
        'desc':
            'The audio/video container or encoding profile is not supported by the platform AV demuxer.',
        'isDrm': false,
        'isNoSignal': false,
      };
    }

    if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('connection refused') ||
        lower.contains('socket') ||
        lower.contains('failed to open')) {
      return {
        'icon': Icons.satellite_alt_rounded,
        'color': const Color(0xFFEF4444), // Crimson
        'glowColor': const Color(0xFFF87171),
        'badge': 'NO SIGNAL',
        'title': 'No Broadcast Signal',
        'desc':
            'No broadcast signal received from the transponder. Checking alternative stream feeds or re-establishing connection.',
        'isDrm': false,
        'isNoSignal': true,
      };
    }

    return {
      'icon': Icons.tv_off_rounded,
      'color': const Color(0xFFEF4444),
      'glowColor': const Color(0xFFF87171),
      'badge': 'NO SIGNAL',
      'title': 'Playback Interrupted',
      'desc':
          'Unable to receive broadcast packets. Check your network connection or zap to an alternate channel.',
      'isDrm': false,
      'isNoSignal': true,
    };
  }

  Widget _buildErrorView(BuildContext context, BoxConstraints constraints) {
    final tvState = context.read<TvStateProvider>();
    final channel = widget.channel;
    final errorInfo = _categorizeError(_errorMessage ?? '', channel);
    final Color accentColor = errorInfo['color'] as Color;
    final Color glowColor = (errorInfo['glowColor'] as Color?) ?? accentColor;
    final bool isDrm = errorInfo['isDrm'] == true;
    final bool isNoSignal = errorInfo['isNoSignal'] == true;

    final double width = constraints.maxWidth;
    final double height = constraints.maxHeight;

    // Responsive Tiers:
    // 1. Ultra-Compact: PiP / split-screen preview tiles (<240h or <360w)
    // 2. Compact: Mobile portrait / small dialogs (<480h or <580w)
    // 3. Full: Standard TV / Desktop / Widescreen
    final bool isUltraCompact = height < 240 || width < 360;
    final bool isCompact = !isUltraCompact && (height < 480 || width < 580);

    // ==========================================
    // TIER 1: ULTRA-COMPACT (PiP / Mini Grid Tiles)
    // ==========================================
    if (isUltraCompact) {
      return Container(
        color: const Color(0xFF090A0F),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.9),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    errorInfo['icon'] as IconData,
                    size: 13,
                    color: accentColor,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      errorInfo['badge'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: accentColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (channel != null) ...[
                const SizedBox(height: 3),
                Text(
                  '#${channel.channelNumber}  ${channel.name}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: TvTheme.textBright,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              // Mini Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (channel != null) {
                          _openStream(channel.streamUrl);
                        }
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: TvTheme.primary.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 11,
                              color: Colors.white,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Retry',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => tvState.playNextChannel(),
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_downward_rounded,
                              size: 11,
                              color: TvTheme.textBright,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'CH+',
                              style: TextStyle(
                                fontSize: 10,
                                color: TvTheme.textBright,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (isDrm && AppPlatform.isMacOS && channel != null) ...[
                    const SizedBox(width: 6),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => ExternalPlayerService.launchDrmPlayer(
                          context: context,
                          channel: channel,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_browser_rounded,
                                size: 11,
                                color: Colors.white,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Chrome',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    // ==========================================
    // TIER 2 & 3: COMPACT & FULL SCREEN CINEMATIC UI
    // ==========================================
    return Stack(
      children: [
        // 1. Ambient Background Layer with Rich Radial Glow
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.25,
                  colors: [
                    glowColor.withValues(alpha: isDrm ? 0.16 : 0.13),
                    const Color(0xFF11141D),
                    const Color(0xFF08090C),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.45, 0.85, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 2. High-Tech Background Graphic Pattern
        // For DRM: Cyber Shield / Matrix Overlay
        // For No Signal: Subtle Radar / Geometric Broadcast Waves
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.05,
              child: CustomPaint(
                painter: _BroadcastPatternPainter(
                  isDrm: isDrm,
                  isNoSignal: isNoSignal,
                  accentColor: accentColor,
                ),
              ),
            ),
          ),
        ),

        // 3. Optional Blurred Channel Logo Aura
        if (channel?.logoUrl != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.10,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
                  child: Image.network(
                    channel!.logoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),

        // 4. Main Responsive Glassmorphic Card
        Positioned.fill(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 16 : 28,
                vertical: isCompact ? 14 : 24,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  constraints: BoxConstraints(maxWidth: isCompact ? 500 : 640),
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 20 : 36,
                    vertical: isCompact ? 20 : 32,
                  ),
                  decoration: BoxDecoration(
                    color: TvTheme.surfaceElevated.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.22),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.75),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // A. Top Pill & Group Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Status Pill with Glowing Dot
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 10 : 14,
                              vertical: isCompact ? 4 : 6,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.65),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: glowColor.withValues(alpha: 0.25),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: glowColor,
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  errorInfo['badge'] as String,
                                  style: TextStyle(
                                    fontSize: isCompact ? 10.5 : 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.1,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (channel?.groupName != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 8 : 10,
                                vertical: isCompact ? 4 : 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: Text(
                                channel!.groupName!.toUpperCase(),
                                style: TextStyle(
                                  fontSize: isCompact ? 10 : 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: TvTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      SizedBox(height: isCompact ? 14 : 20),

                      // B. Hero Circular Icon with Pulsing Ambient Aura
                      Container(
                        width: isCompact ? 60 : 76,
                        height: isCompact ? 60 : 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              accentColor.withValues(alpha: 0.25),
                              accentColor.withValues(alpha: 0.04),
                            ],
                          ),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.55),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: glowColor.withValues(alpha: 0.35),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          errorInfo['icon'] as IconData,
                          size: isCompact ? 30 : 38,
                          color: accentColor,
                        ),
                      ),

                      SizedBox(height: isCompact ? 12 : 18),

                      // C. Channel Identity Badge (Logo + Name)
                      if (channel != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (channel.logoUrl != null) ...[
                              Container(
                                width: isCompact ? 32 : 40,
                                height: isCompact ? 32 : 40,
                                decoration: BoxDecoration(
                                  color: TvTheme.surfaceFocus,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: TvTheme.borderSubtle,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.network(
                                  channel.logoUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.live_tv_rounded,
                                    size: 20,
                                    color: TvTheme.primaryAccent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Text(
                                '#${channel.channelNumber}  ${channel.name}',
                                style: TextStyle(
                                  fontSize: isCompact ? 16 : 20,
                                  fontWeight: FontWeight.bold,
                                  color: TvTheme.textBright,
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],

                      // D. Primary Title
                      Text(
                        errorInfo['title'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isCompact ? 16 : 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // E. Informative Description
                      Text(
                        errorInfo['desc'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isCompact ? 12 : 13.5,
                          color: TvTheme.textMuted,
                          height: 1.45,
                        ),
                      ),

                      // F. Auto-Retry Indicator Pill
                      if (_isAutoRetrying) ...[
                        SizedBox(height: isCompact ? 12 : 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: TvTheme.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: TvTheme.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: TvTheme.primaryAccent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Auto-reconnecting in ${_autoRetryCountdown}s... (Attempt ${_retryCount + 1}/3)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: TvTheme.primaryAccent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _cancelAutoRetry,
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      SizedBox(height: isCompact ? 18 : 24),

                      // G. Responsive Action Buttons (D-Pad Focusable)
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          // macOS Widevine Helper Buttons
                          if (AppPlatform.isMacOS &&
                              channel != null &&
                              isDrm) ...[
                            Builder(
                              builder: (context) {
                                final ch = channel;
                                return ElevatedButton.icon(
                                  autofocus: true,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompact ? 14 : 20,
                                      vertical: isCompact ? 10 : 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 5,
                                    shadowColor: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.4),
                                  ),
                                  onPressed: () =>
                                      ExternalPlayerService.launchDrmPlayer(
                                        context: context,
                                        channel: ch,
                                      ),
                                  icon: const Icon(
                                    Icons.open_in_browser_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Launch Chrome / Edge (Widevine CDM)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                            Builder(
                              builder: (context) {
                                final ch = channel;
                                return OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompact ? 12 : 16,
                                      vertical: isCompact ? 10 : 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () async {
                                    final url =
                                        ch.inAppWebPlayerUrl ??
                                        ch.webPlayerUrl ??
                                        ch.streamUrl;
                                    await launchUrl(
                                      Uri.parse(url),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.open_in_new_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Default Browser',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                            Builder(
                              builder: (context) {
                                final ch = channel;
                                return OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orangeAccent,
                                    side: const BorderSide(
                                      color: Colors.orangeAccent,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompact ? 12 : 16,
                                      vertical: isCompact ? 10 : 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () async {
                                    await ExternalPlayerService.launchInVlc(
                                      context: context,
                                      streamUrl: ch.streamUrl,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.play_circle_outline_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'VLC Player',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],

                          // Standard In-App Web Engine for Mobile / Other
                          if (!AppPlatform.isMacOS &&
                              !AppPlatform.isWeb &&
                              channel != null &&
                              channel.inAppWebPlayerUrl != null &&
                              !_isUsingWebPlayer) ...[
                            Builder(
                              builder: (context) {
                                final ch = channel;
                                return ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isCompact ? 14 : 18,
                                      vertical: isCompact ? 10 : 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () => _initInAppWebPlayer(
                                    ch.inAppWebPlayerUrl!,
                                  ),
                                  icon: const Icon(
                                    Icons.play_circle_fill_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    'In-App Web Engine (#${ch.channelNumber})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],

                          // Standard Retry Reconnect
                          ElevatedButton.icon(
                            autofocus: !isDrm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: TvTheme.primary,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 14 : 18,
                                vertical: isCompact ? 10 : 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 4,
                            ),
                            onPressed: () {
                              if (widget.channel != null) {
                                _openStream(widget.channel!.streamUrl);
                              }
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text(
                              'Retry Connection',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),

                          // Channel Switcher (Previous Channel)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TvTheme.textBright,
                              side: const BorderSide(
                                color: TvTheme.borderSubtle,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 12 : 14,
                                vertical: isCompact ? 10 : 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => tvState.playPreviousChannel(),
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 16,
                            ),
                            label: const Text('CH -'),
                          ),

                          // Channel Switcher (Next Channel)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TvTheme.textBright,
                              side: const BorderSide(
                                color: TvTheme.borderSubtle,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 12 : 14,
                                vertical: isCompact ? 10 : 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => tvState.playNextChannel(),
                            icon: const Icon(
                              Icons.arrow_downward_rounded,
                              size: 16,
                            ),
                            label: const Text('CH +'),
                          ),

                          // Channel Guide EPG Toggle
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: TvTheme.textBright,
                              side: const BorderSide(
                                color: TvTheme.borderSubtle,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: isCompact ? 12 : 14,
                                vertical: isCompact ? 10 : 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => tvState.toggleEpgOverlay(),
                            icon: const Icon(Icons.menu_rounded, size: 16),
                            label: const Text('Guide'),
                          ),
                        ],
                      ),

                      SizedBox(height: isCompact ? 10 : 14),

                      // H. Technical Diagnostics Accordion Toggle
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showTechnicalDetails = !_showTechnicalDetails;
                          });
                        },
                        icon: Icon(
                          _showTechnicalDetails
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: TvTheme.textMuted,
                        ),
                        label: Text(
                          _showTechnicalDetails
                              ? 'Hide Diagnostics'
                              : 'Show Technical Diagnostics',
                          style: const TextStyle(
                            fontSize: 12,
                            color: TvTheme.textMuted,
                          ),
                        ),
                      ),

                      // Expanded Technical Diagnostics Panel
                      if (_showTechnicalDetails && channel != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: TvTheme.borderSubtle),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'Stream URL:',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: TvTheme.primaryAccent,
                                    ),
                                  ),
                                  const Spacer(),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(text: channel.streamUrl),
                                      );
                                      TvToast.info(
                                        context,
                                        'Stream URL copied to clipboard',
                                      );
                                    },
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.copy_rounded,
                                          size: 12,
                                          color: TvTheme.primaryAccent,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Copy',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: TvTheme.primaryAccent,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                channel.streamUrl,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              if (channel.hasDrm) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'DRM Scheme: ${channel.drmType?.toUpperCase() ?? "WIDEVINE"}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF06B6D4),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (channel.drmLicenseUrl != null)
                                  SelectableText(
                                    'License Server: ${channel.drmLicenseUrl}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white60,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                              ],
                              if (channel.inAppWebPlayerUrl != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Text(
                                      'In-App Player URL:',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueAccent,
                                      ),
                                    ),
                                    const Spacer(),
                                    InkWell(
                                      onTap: () {
                                        Clipboard.setData(
                                          ClipboardData(
                                            text: channel.inAppWebPlayerUrl!,
                                          ),
                                        );
                                        TvToast.info(
                                          context,
                                          'In-App Player URL copied to clipboard',
                                        );
                                      },
                                      child: const Row(
                                        children: [
                                          Icon(
                                            Icons.copy_rounded,
                                            size: 12,
                                            color: Colors.blueAccent,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'Copy',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.blueAccent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  channel.inAppWebPlayerUrl!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white70,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              const Text(
                                'Error Trace:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.redAccent,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                _errorMessage ?? 'Unknown playback error',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white60,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoSurface(BoxFit fit, double? forcedAspectRatio) {
    if (_isUsingWebPlayer && _webViewController != null) {
      final webWidget = IgnorePointer(
        ignoring: true,
        child: Focus(
          canRequestFocus: false,
          descendantsAreFocusable: false,
          skipTraversal: true,
          child: WebViewWidget(controller: _webViewController!),
        ),
      );
      if (forcedAspectRatio != null) {
        return Center(
          child: AspectRatio(aspectRatio: forcedAspectRatio, child: webWidget),
        );
      }
      return SizedBox.expand(child: webWidget);
    }

    if (AppPlatform.isAndroid) {
      if (_androidController != null &&
          _androidController!.value.isInitialized) {
        final val = _androidController!.value;
        final actualAspect = val.aspectRatio > 0 ? val.aspectRatio : (16 / 9);

        Widget rawPlayer = vp.VideoPlayer(_androidController!);

        if (forcedAspectRatio != null) {
          return Center(
            child: AspectRatio(
              aspectRatio: forcedAspectRatio,
              child: FittedBox(
                fit: fit,
                child: SizedBox(
                  width: val.size.width > 0 ? val.size.width : 1920,
                  height: val.size.height > 0 ? val.size.height : 1080,
                  child: rawPlayer,
                ),
              ),
            ),
          );
        }

        switch (widget.scaleMode) {
          case VideoScaleMode.contain:
            return Center(
              child: AspectRatio(aspectRatio: actualAspect, child: rawPlayer),
            );
          case VideoScaleMode.cover:
          case VideoScaleMode.fitWidth:
          case VideoScaleMode.fitHeight:
            return SizedBox.expand(
              child: FittedBox(
                fit: fit,
                child: SizedBox(
                  width: val.size.width > 0 ? val.size.width : 1920,
                  height: val.size.height > 0 ? val.size.height : 1080,
                  child: rawPlayer,
                ),
              ),
            );
          default:
            return Center(
              child: AspectRatio(aspectRatio: actualAspect, child: rawPlayer),
            );
        }
      } else {
        return const SizedBox.shrink();
      }
    } else if (AppPlatform.isWeb) {
      if (_webStreamUrl == null) return const SizedBox.shrink();
      final shakaWidget = ShakaPlayerView(
        url: _webStreamUrl!,
        isPlaying: widget.isPlaying,
        isMuted: widget.isMuted,
        drmLicenseUrl: widget.channel?.drmLicenseUrl,
        fit: fit,
        onLoaded: () {
          if (mounted) {
            setState(() {
              _isBuffering = false;
              _isInitializing = false;
              _isInitialized = true;
            });
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _setErrorMessage(err);
              _isInitializing = false;
              _isBuffering = false;
            });
            _startAutoRetry();
          }
        },
      );

      return forcedAspectRatio != null
          ? Center(
              child: AspectRatio(
                aspectRatio: forcedAspectRatio,
                child: shakaWidget,
              ),
            )
          : SizedBox.expand(child: shakaWidget);
    } else {
      if (_videoController == null) return const SizedBox.shrink();
      return forcedAspectRatio != null
          ? Center(
              child: AspectRatio(
                aspectRatio: forcedAspectRatio,
                child: Video(
                  controller: _videoController!,
                  fit: fit,
                  controls: NoVideoControls,
                ),
              ),
            )
          : Video(
              controller: _videoController!,
              fit: fit,
              controls: NoVideoControls,
            );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channel == null) {
      return Container(
        color: TvTheme.background,
        child: const Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tv_rounded, size: 48, color: TvTheme.borderSubtle),
                  SizedBox(height: 8),
                  Text(
                    'No channel selected',
                    style: TextStyle(color: TvTheme.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return LayoutBuilder(
        builder: (context, constraints) =>
            _buildErrorView(context, constraints),
      );
    }

    final hasPlayer = _isUsingWebPlayer
        ? (_webViewController != null)
        : (AppPlatform.isWeb
              ? (_webStreamUrl != null)
              : (AppPlatform.isAndroid
                    ? (_androidController != null)
                    : (_player != null && _videoController != null)));

    if (hasPlayer) {
      BoxFit fit;
      double? forcedAspectRatio;
      switch (widget.scaleMode) {
        case VideoScaleMode.contain:
          fit = BoxFit.contain;
          break;
        case VideoScaleMode.fitWidth:
          fit = BoxFit.fitWidth;
          break;
        case VideoScaleMode.fitHeight:
          fit = BoxFit.fitHeight;
          break;
        case VideoScaleMode.cover:
          fit = BoxFit.cover;
          break;
        case VideoScaleMode.fourThree:
          fit = BoxFit.fill;
          forcedAspectRatio = 4 / 3;
          break;
        case VideoScaleMode.sixteenNine:
          fit = BoxFit.fill;
          forcedAspectRatio = 16 / 9;
          break;
      }

      return SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoSurface(fit, forcedAspectRatio),
            // Loading / Tuning Overlay (keeps underlying Video texture mounted)
            if (_isInitializing || !_isInitialized)
              Positioned.fill(
                child: Container(
                  color: TvTheme.background,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: TvTheme.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Tuning into ${widget.channel!.name}...',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Live Recording Badge
            Consumer<TvStateProvider>(
              builder: (context, tvState, _) {
                if (!tvState.isCurrentChannelRecording || tvState.isSystemPip) {
                  return const SizedBox.shrink();
                }
                final bytes = tvState.currentChannelBytesRecorded;
                final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);

                return Positioned(
                  top: 24,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.5),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'REC $mb MB',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // Buffering Circle Indicator
            if (_isBuffering && widget.isPlaying)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 4.0,
                      color: TvTheme.primaryAccent,
                    ),
                  ),
                ),
              ),
            if (!widget.isPlaying)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      context.read<TvStateProvider>().togglePlayPause(),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.65),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Material(
                            color: TvTheme.surfaceElevated.withValues(
                              alpha: 0.9,
                            ),
                            shape: const CircleBorder(
                              side: BorderSide(
                                color: TvTheme.borderSubtle,
                                width: 2,
                              ),
                            ),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => context
                                  .read<TvStateProvider>()
                                  .togglePlayPause(),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Icon(
                                  widget.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 46,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(color: TvTheme.background);
  }
}

class _BroadcastPatternPainter extends CustomPainter {
  final bool isDrm;
  final bool isNoSignal;
  final Color accentColor;

  const _BroadcastPatternPainter({
    required this.isDrm,
    required this.isNoSignal,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);

    if (isDrm) {
      // High-tech matrix grid + concentric rings
      const step = 44.0;
      for (double x = 0; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (double y = 0; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      for (double r = 60; r < 260; r += 45) {
        canvas.drawCircle(center, r, paint);
      }
    } else if (isNoSignal) {
      // Concentric broadcast radar waves & crosshairs
      for (double r = 40; r < 360; r += 50) {
        canvas.drawCircle(center, r, paint);
      }
      canvas.drawLine(
        Offset(0, center.dy),
        Offset(size.width, center.dy),
        paint,
      );
      canvas.drawLine(
        Offset(center.dx, 0),
        Offset(center.dx, size.height),
        paint,
      );
    } else {
      // Subtle scanline pattern
      const step = 20.0;
      for (double y = 0; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BroadcastPatternPainter oldDelegate) {
    return oldDelegate.isDrm != isDrm ||
        oldDelegate.isNoSignal != isNoSignal ||
        oldDelegate.accentColor != accentColor;
  }
}
