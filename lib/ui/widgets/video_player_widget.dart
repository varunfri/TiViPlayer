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

class VideoPlayerWidget extends StatefulWidget {
  final Channel? channel;
  final bool isMuted;
  final VideoScaleMode scaleMode;
  final bool isPlaying;

  const VideoPlayerWidget({
    super.key,
    required this.channel,
    this.isMuted = false,
    this.scaleMode = VideoScaleMode.cover,
    this.isPlaying = true,
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
  bool _isBuffering = false;

  Timer? _bufferingDebounceTimer;
  Timer? _bufferingWatchdogTimer;
  StreamSubscription? _bufferingSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription? _playingSubscription;
  StreamSubscription? _positionSubscription;

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
        context.read<TvStateProvider>().registerPlaybackRateCallback((rate) {
          _androidController?.setPlaybackSpeed(rate);
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
          _errorMessage = err;
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
        (_player!.platform as dynamic)?.setProperty('network-timeout', '20');
        (_player!.platform as dynamic)?.setProperty(
          'stream-lavf-o',
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

      _positionSubscription = _player!.stream.position.listen((pos) {
        if (!mounted) return;
        if (pos > Duration.zero && _isBuffering) {
          _bufferingDebounceTimer?.cancel();
          _bufferingWatchdogTimer?.cancel();
          setState(() {
            _isBuffering = false;
          });
        }
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
            _errorMessage = error;
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
          _errorMessage = error;
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
      _errorMessage = null;
    });

    final tvState = context.read<TvStateProvider>();
    final double initialVolume = tvState.volume;
    final double initialPlaybackRate = tvState.playbackRate;

    try {
      final List<String> candidateUrls = [];

      final Map<String, String> requestHeaders = {
        'User-Agent': 'TiviMate/5.1.0 (Android TV; Linux; OKHttp/5.4.0)',
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
            _errorMessage =
                'Channel #${widget.channel?.channelNumber ?? ""} is protected with Google Widevine DRM.\nmacOS WebKit does not include Widevine CDM. Launch the external player in Chrome/Edge or default browser to watch this broadcast.';
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
            _errorMessage = null;
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

        for (int i = 0; i < candidateUrls.length; i++) {
          final currentUrl = candidateUrls[i];
          final lower = currentUrl.toLowerCase();
          vp.VideoFormat? formatHint;
          if (lower.contains('.mpd') ||
              lower.contains('/dash') ||
              lower.contains('/mpd/')) {
            formatHint = vp.VideoFormat.dash;
          } else if (lower.contains('.m3u8') ||
              lower.contains('/hls') ||
              lower.contains('format=m3u8') ||
              lower.contains('type=m3u8')) {
            formatHint = vp.VideoFormat.hls;
          } else if (lower.contains('.ism')) {
            formatHint = vp.VideoFormat.ss;
          } else if (lower.endsWith('.mp4') ||
              lower.endsWith('.mkv') ||
              lower.endsWith('.avi')) {
            formatHint = vp.VideoFormat.other;
          } else {
            formatHint = vp.VideoFormat.hls;
          }

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
            break;
          } catch (initErr) {
            lastError = initErr;
            debugPrint(
              '[VideoPlayerWidget] Candidate failed ($currentUrl): $initErr',
            );
            controller.removeListener(_onAndroidControllerUpdate);
            await controller.dispose();
            _androidController = null;
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

        Object? lastError;
        bool openedSuccessfully = false;

        for (final currentUrl in candidateUrls) {
          try {
            await _player!.open(
              Media(currentUrl, httpHeaders: requestHeaders),
              play: widget.isPlaying,
            );
            await _player!.setVolume(widget.isMuted ? 0.0 : (initialVolume * 100.0));
            await _player!.setRate(initialPlaybackRate);
            openedSuccessfully = true;
            break;
          } catch (desktopErr) {
            lastError = desktopErr;
            debugPrint(
              '[VideoPlayerWidget] Desktop stream candidate error on $currentUrl: $desktopErr',
            );
          }
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
          _errorMessage = msg;
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
      _errorMessage = null;
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
              _errorMessage =
                  'Widevine DRM is not supported on macOS WebKit.\nThis channel requires Google Widevine CDM (supported on Android TV & Android devices).';
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
                _errorMessage =
                    'Widevine DRM stream detected.\nmacOS WebKit does not support Google Widevine CDM. This channel will play seamlessly on Android TV and Android devices.';
              });
            }
          } else if (text == 'PLAYING') {
            if (mounted) {
              setState(() {
                _isInitializing = false;
                _isInitialized = true;
                _isBuffering = false;
                _errorMessage = null;
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
                _errorMessage =
                    'Widevine DRM stream detected.\nmacOS WebKit does not support Google Widevine CDM. This channel will play seamlessly on Android TV and Android devices.';
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
          _errorMessage = 'In-app player failed: $e';
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
    _bufferingSubscription = null;
    _errorSubscription = null;
    _playingSubscription = null;
    _positionSubscription = null;
    if (_player != null) {
      try {
        final provider = context.read<TvStateProvider>();
        if (provider.activePlayer == _player) {
          provider.registerPlayer(null);
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
      } catch (_) {}
      _disposeAndroidPlayer();
    } else {
      _disposePlayer();
    }
    _cancelAutoRetry();
    super.dispose();
  }

  Map<String, dynamic> _categorizeError(String error, Channel? channel) {
    final lower = error.toLowerCase();
    if (channel?.hasDrm == true ||
        lower.contains('drm') ||
        lower.contains('widevine') ||
        lower.contains('playready') ||
        lower.contains('clearkey') ||
        (channel?.streamUrl.contains('/mpd/') == true &&
            (lower.contains('404') ||
                lower.contains('mediacodec') ||
                lower.contains('playback failure') ||
                lower.contains('source error') ||
                lower.contains('failed to initialize')))) {
      return {
        'icon': Icons.lock_clock_rounded,
        'color': TvTheme.accentGold,
        'badge': 'WIDEVINE DRM PROTECTED',
        'title': 'DRM Protected Channel',
        'desc': AppPlatform.isMacOS
            ? 'Channel #${channel?.channelNumber ?? ""} (${channel?.name ?? ""}) requires Google Widevine CDM. macOS WebKit does not include Google Widevine; this DRM channel plays natively on Android TV and Android devices.'
            : 'Channel #${channel?.channelNumber ?? ""} (${channel?.name ?? ""}) is encrypted with Google Widevine DRM. Playing via in-app hardware CDM engine.',
        'isDrm': true,
      };
    }
    if (lower.contains('500') ||
        lower.contains('internal server error') ||
        lower.contains('target vector')) {
      return {
        'icon': Icons.dns_rounded,
        'color': Colors.redAccent,
        'badge': 'HTTP 500 SERVER ERROR',
        'title': 'Upstream Proxy Scraper Failure',
        'desc':
            'The stream proxy (port 8443) failed to parse upstream source target vectors for this channel. The upstream website markup or token generator has changed.',
      };
    }
    if (lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('bad gateway') ||
        lower.contains('service unavailable') ||
        lower.contains('host offline')) {
      return {
        'icon': Icons.cloud_sync_rounded,
        'color': Colors.orangeAccent,
        'badge': 'HTTP 503 SERVICE UNAVAILABLE',
        'title': 'Upstream Host Offline / Cold Start',
        'desc':
            'The remote stream host is offline or the proxy is warming up the upstream session. Automatic retry in progress...',
      };
    }
    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        lower.contains('access denied')) {
      return {
        'icon': Icons.block_rounded,
        'color': Colors.deepOrangeAccent,
        'badge': 'HTTP 403 FORBIDDEN',
        'title': 'Access Forbidden / Token Expired',
        'desc':
            'The broadcast server rejected this playback session. The streaming token, signature, or user-agent may have expired.',
      };
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return {
        'icon': Icons.cloud_off_rounded,
        'color': Colors.redAccent,
        'badge': 'HTTP 404 NOT FOUND',
        'title': 'Stream Offline or Relocated',
        'desc':
            'The remote stream URL returned 404 Not Found. The channel may be temporarily down or undergoing maintenance.',
      };
    }
    if (lower.contains('codec') ||
        lower.contains('unsupported') ||
        lower.contains('format') ||
        lower.contains('demux')) {
      return {
        'icon': Icons.video_file_rounded,
        'color': Colors.purpleAccent,
        'badge': 'FORMAT UNSUPPORTED',
        'title': 'Incompatible Stream Codec',
        'desc':
            'The stream packaging or audio/video codec is not supported by the platform AV engine.',
      };
    }
    if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('connection refused') ||
        lower.contains('socket')) {
      return {
        'icon': Icons.wifi_off_rounded,
        'color': Colors.amberAccent,
        'badge': 'NETWORK TIMEOUT',
        'title': 'Connection Timed Out',
        'desc':
            'Unable to reach the broadcast streaming server. The upstream stream took too long to deliver chunks.',
      };
    }
    return {
      'icon': Icons.tv_off_rounded,
      'color': Colors.redAccent,
      'badge': 'NO SIGNAL',
      'title': 'Playback Interrupted',
      'desc':
          'Unable to play this broadcast stream. Retry connection or zap to an alternate channel.',
    };
  }

  Widget _buildErrorView(BuildContext context, BoxConstraints constraints) {
    final tvState = context.read<TvStateProvider>();
    final channel = widget.channel;
    final errorInfo = _categorizeError(_errorMessage ?? '', channel);

    final isCompact = constraints.maxHeight < 360 || constraints.maxWidth < 450;

    return Stack(
      children: [
        // 1. Dark Ambient Backdrop with optional blurred channel logo
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [Color(0xFF161922), Color(0xFF090A0E), Colors.black],
              ),
            ),
          ),
        ),

        // Optional Ambient Blurred Glow of Channel Logo
        if (channel?.logoUrl != null)
          Positioned.fill(
            child: Opacity(
              opacity: 0.14,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Image.network(
                  channel!.logoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),

        // 2. Main Content Card
        Positioned.fill(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580),
                padding: EdgeInsets.all(isCompact ? 16 : 28),
                decoration: BoxDecoration(
                  color: TvTheme.surfaceElevated.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (errorInfo['color'] as Color).withValues(
                      alpha: 0.35,
                    ),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status Badge & Icon Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (errorInfo['color'] as Color).withValues(
                              alpha: 0.2,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: (errorInfo['color'] as Color).withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                errorInfo['icon'] as IconData,
                                size: 14,
                                color: errorInfo['color'] as Color,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                errorInfo['badge'] as String,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                  color: errorInfo['color'] as Color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (channel?.groupName != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              channel!.groupName!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: TvTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Channel Identity Row
                    if (channel != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (channel.logoUrl != null) ...[
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: TvTheme.surfaceFocus,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: TvTheme.borderSubtle),
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
                            const SizedBox(width: 12),
                          ],
                          Flexible(
                            child: Text(
                              '#${channel.channelNumber}  ${channel.name}',
                              style: TextStyle(
                                fontSize: isCompact ? 16 : 20,
                                fontWeight: FontWeight.bold,
                                color: TvTheme.textBright,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Primary Title
                    Text(
                      errorInfo['title'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isCompact ? 15 : 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Description
                    Text(
                      errorInfo['desc'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isCompact ? 12 : 13,
                        color: TvTheme.textMuted,
                        height: 1.4,
                      ),
                    ),

                    // Auto-retry notice
                    if (_isAutoRetrying) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: TvTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: TvTheme.primary.withValues(alpha: 0.3),
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
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: _cancelAutoRetry,
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 22),

                    // TV Action Buttons (D-Pad Focusable)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        if (AppPlatform.isMacOS && channel != null) ...[
                          Builder(
                            builder: (context) {
                              final ch = channel;
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      elevation: 4,
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
                                      'Launch Chrome / Edge Player (Widevine CDM)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Colors.white30,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: () async {
                                      final url =
                                          ch.inAppWebPlayerUrl ??
                                          ch.webPlayerUrl ??
                                          ch.streamUrl;
                                      await launchUrl(
                                        Uri.parse(url),
                                        mode: LaunchMode
                                            .externalNonBrowserApplication,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Open in Default Browser',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  // if (ExternalPlayerService.isVlcInstalled())
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orangeAccent,
                                      side: const BorderSide(
                                        color: Colors.orangeAccent,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
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
                                      'Open in VLC',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 4,
                                ),
                                onPressed: () =>
                                    _initInAppWebPlayer(ch.inAppWebPlayerUrl!),
                                icon: const Icon(
                                  Icons.play_circle_fill_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  'Play via In-App Engine (#${ch.channelNumber})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                        if (AppPlatform.isWeb &&
                            channel != null &&
                            channel.inAppWebPlayerUrl != null) ...[
                          Builder(
                            builder: (context) {
                              final ch = channel;
                              return ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 4,
                                ),
                                onPressed: () {
                                  launchUrl(
                                    Uri.parse(ch.inAppWebPlayerUrl!),
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  'Open Web Player in Tab (#${ch.channelNumber})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],

                        // Retry Reconnect
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TvTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
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

                        // Zap Previous
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TvTheme.textBright,
                            side: const BorderSide(color: TvTheme.borderSubtle),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => tvState.playPreviousChannel(),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 16,
                          ),
                          label: const Text('CH -'),
                        ),

                        // Zap Next
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TvTheme.textBright,
                            side: const BorderSide(color: TvTheme.borderSubtle),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => tvState.playNextChannel(),
                          icon: const Icon(
                            Icons.arrow_downward_rounded,
                            size: 16,
                          ),
                          label: const Text('CH +'),
                        ),

                        // Channel Guide Toggle
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TvTheme.textBright,
                            side: const BorderSide(color: TvTheme.borderSubtle),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => tvState.toggleEpgOverlay(),
                          icon: const Icon(Icons.menu_rounded, size: 16),
                          label: const Text('Guide'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Diagnostics Accordion Toggle
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

                    // Expanded Technical Diagnostics
                    if (_showTechnicalDetails && channel != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
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
                                'DRM Scheme: ${channel.drmType?.toUpperCase()}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: TvTheme.accentGold,
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
              _errorMessage = err;
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
