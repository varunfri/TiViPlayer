import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../ui/theme.dart';
import '../models/playlist.dart';
import '../models/channel_group.dart';
import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/recording_item.dart';
import '../services/database_service.dart';
import '../services/playlist_parser.dart';
import '../services/xtream_service.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import '../services/stream_recording_service.dart';
import '../services/recording_scheduler.dart';
import '../services/system_pip_service.dart';
import '../services/epg_parser.dart';
import '../services/screen_wake_service.dart';
import '../services/desktop_pip_service.dart';
import '../services/app_platform.dart';

enum TvViewMode { quickOverlay, epgGrid, bottomScrollList }

enum VideoScaleMode { cover, contain, fitWidth, fitHeight, fourThree, sixteenNine }

class TvStateProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;

  List<Playlist> _playlists = [];
  Playlist? _selectedPlaylist;

  List<ChannelGroup> _groups = [];
  ChannelGroup? _selectedGroup;

  List<Channel> _channels = [];
  Channel? _selectedChannel;
  Channel? _activePlayingChannel;

  EpgProgram? _currentProgram;
  List<EpgProgram> _upcomingPrograms = [];
  Map<String, EpgProgram> _liveProgramsMap = {};
  Timer? _epgRefreshTimer;
  Timer? _epgAutoSyncTimer;
  bool _isEpgSyncing = false;

  bool _isEpgOverlayVisible = true;
  bool _showBottomChannelList = false;
  bool _isFavoritesOnly = false;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _errorMessage;

  TvViewMode _viewMode = TvViewMode.quickOverlay;
  VideoScaleMode _scaleMode = VideoScaleMode.cover;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isPlaying = true;
  bool _isPipMode = false;
  bool _isSystemPip = false;
  bool _isDesktopPip = false;
  Player? _activePlayer;
  int _bufferSizeBytes = 32 * 1024 * 1024;
  double _playbackRate = 1.0;
  Map<String, String> _persistedSettings = {};

  // Getters
  List<Playlist> get playlists => _playlists;
  Playlist? get selectedPlaylist => _selectedPlaylist;
  List<ChannelGroup> get groups => _groups;
  ChannelGroup? get selectedGroup => _selectedGroup;
  List<Channel> get channels => _channels;
  Channel? get selectedChannel => _selectedChannel;
  Channel? get activePlayingChannel => _activePlayingChannel;
  Map<String, String> get persistedSettings => _persistedSettings;
  EpgProgram? get currentProgram => _currentProgram;
  List<EpgProgram> get upcomingPrograms => _upcomingPrograms;
  Map<String, EpgProgram> get liveProgramsMap => _liveProgramsMap;

  EpgProgram? getLiveProgramForChannel(Channel channel) {
    if (_liveProgramsMap.isEmpty) return null;
    final tvgId = channel.tvgId?.trim().toLowerCase();
    if (tvgId != null && tvgId.isNotEmpty && _liveProgramsMap.containsKey(tvgId)) {
      return _liveProgramsMap[tvgId];
    }
    final name = channel.name.trim().toLowerCase();
    if (name.isNotEmpty && _liveProgramsMap.containsKey(name)) {
      return _liveProgramsMap[name];
    }
    return null;
  }
  bool get isEpgSyncing => _isEpgSyncing;
  bool get isEpgOverlayVisible => _isEpgOverlayVisible;
  bool get showBottomChannelList => _showBottomChannelList;
  bool get isFavoritesOnly => _isFavoritesOnly;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  TvViewMode get viewMode => _viewMode;
  VideoScaleMode get scaleMode => _scaleMode;
  double get volume => _volume;
  bool get isMuted => _isMuted;
  bool get isPlaying => _isPlaying;
  bool get isPipMode => _isPipMode;
  bool get isSystemPip => _isSystemPip;
  bool get isDesktopPip => _isDesktopPip;
  Player? get activePlayer => _activePlayer;
  int get bufferSizeBytes => _bufferSizeBytes;
  double get playbackRate => _playbackRate;

  /// Returns (numerator, denominator) for native OS PiP window aspect ratio
  (int, int) getAspectRatioForScaleMode() {
    switch (_scaleMode) {
      case VideoScaleMode.fourThree:
        return (4, 3);
      case VideoScaleMode.sixteenNine:
      case VideoScaleMode.contain:
      case VideoScaleMode.cover:
      case VideoScaleMode.fitWidth:
      case VideoScaleMode.fitHeight:
        return (16, 9);
    }
  }

  /// Triggers system-wide Picture-in-Picture on Android (floating outside app over other apps),
  /// or Desktop Picture-in-Picture on macOS / Windows / Linux (always-on-top compact window over other apps).
  Future<void> enterSystemPip({BuildContext? context}) async {
    // If no channel is currently playing, start the selected or first channel so PiP displays live content
    if (_activePlayingChannel == null && _channels.isNotEmpty) {
      playChannel(_selectedChannel ?? _channels.first);
    }

    // On Desktop (macOS, Windows, Linux), enter true OS-level floating PiP window
    // that stays strictly over other apps using window_manager setAlwaysOnTop
    if (AppPlatform.isDesktop) {
      final ratio = getAspectRatioForScaleMode();
      await toggleDesktopPip(aspectRatio: ratio);
      return;
    }

    final supported = await SystemPipService.isPipSupported();
    if (supported) {
      // Check whether Android OS Special App Access -> Picture-in-Picture is permitted
      final allowed = await SystemPipService.isPipAllowed();
      if (!allowed) {
        if (context != null && context.mounted) {
          final openSettings = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: TvTheme.surfaceElevated,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.picture_in_picture_rounded, color: TvTheme.primaryAccent),
                  SizedBox(width: 10),
                  Text(
                    'Enable Picture-in-Picture',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: const Text(
                'To display video while using other apps, please allow Picture-in-Picture permission for TiviPlayer in Android Settings.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.settings_rounded, size: 18),
                  label: const Text('Open Settings'),
                  style: FilledButton.styleFrom(backgroundColor: TvTheme.primary),
                ),
              ],
            ),
          );
          if (openSettings == true) {
            await SystemPipService.openPipSettings();
          }
        }
        return;
      }

      final ratio = getAspectRatioForScaleMode();
      final ok = await SystemPipService.enterPip(
        numerator: ratio.$1,
        denominator: ratio.$2,
        isPlaying: _isPlaying,
      );
      if (ok) {
        _isPipMode = false;
        notifyListeners();
      } else {
        togglePipMode();
      }
    } else {
      togglePipMode();
    }
  }

  void _updateNativePipAutoEnter() {
    final shouldKeepAwake = _activePlayingChannel != null && _isPlaying;
    ScreenWakeService.keepScreenOn(shouldKeepAwake);

    if (shouldKeepAwake) {
      final ratio = getAspectRatioForScaleMode();
      SystemPipService.setAutoEnterPip(
        true,
        numerator: ratio.$1,
        denominator: ratio.$2,
        isPlaying: _isPlaying,
      );
    } else {
      SystemPipService.setAutoEnterPip(false, isPlaying: _isPlaying);
    }
  }

  void togglePipMode() {
    _isPipMode = !_isPipMode;
    notifyListeners();
  }

  void setPipMode(bool val) {
    _isPipMode = val;
    notifyListeners();
  }

  /// Enters Desktop Picture-in-Picture mode (resizes window & floats over other apps)
  Future<void> enterDesktopPip({(int, int)? aspectRatio}) async {
    final ratio = aspectRatio ?? getAspectRatioForScaleMode();
    final ok = await DesktopPipService.enterPip(aspectRatio: ratio);
    if (ok) {
      _isDesktopPip = true;
      _isPipMode = false;
      notifyListeners();
    }
  }

  /// Exits Desktop Picture-in-Picture mode (restores window bounds & removes always-on-top)
  Future<void> exitDesktopPip() async {
    final ok = await DesktopPipService.exitPip();
    if (ok) {
      _isDesktopPip = false;
      notifyListeners();
    }
  }

  /// Toggles Desktop Picture-in-Picture mode
  Future<void> toggleDesktopPip({(int, int)? aspectRatio}) async {
    if (_isDesktopPip) {
      await exitDesktopPip();
    } else {
      await enterDesktopPip(aspectRatio: aspectRatio);
    }
  }

  void _onDesktopPipChanged() {
    if (_isDesktopPip != DesktopPipService.isInPip) {
      _isDesktopPip = DesktopPipService.isInPip;
      notifyListeners();
    }
  }

  void Function(double rate)? _playbackRateCallback;

  void registerPlayer(Player? player) {
    _activePlayer = player;
  }

  void registerPlaybackRateCallback(void Function(double rate)? cb) {
    _playbackRateCallback = cb;
  }

  void _saveCurrentPlaybackState() {
    final updates = <String, String>{};
    if (_activePlayingChannel != null) {
      final ch = _activePlayingChannel!;
      if (ch.id != null) {
        updates['last_channel_id'] = ch.id.toString();
      }
      updates['last_channel_name'] = ch.name;
      updates['last_channel_stream_url'] = ch.streamUrl;

      if (_selectedPlaylist?.id != null) {
        final pid = _selectedPlaylist!.id!;
        updates['last_playlist_id'] = pid.toString();
        updates['last_playlist_name'] = _selectedPlaylist!.name;
        updates['last_playlist_url'] = _selectedPlaylist!.url;

        if (ch.id != null) {
          updates['playlist_${pid}_last_channel_id'] = ch.id.toString();
        }
        updates['playlist_${pid}_last_channel_name'] = ch.name;
        updates['playlist_${pid}_last_channel_stream_url'] = ch.streamUrl;

        if (_isFavoritesOnly) {
          updates['playlist_${pid}_is_favorites_only'] = '1';
          if (ch.id != null) {
            updates['playlist_${pid}_fav_last_channel_id'] = ch.id.toString();
          }
        } else {
          updates['playlist_${pid}_is_favorites_only'] = '0';
        }

        if (_selectedGroup?.id != null) {
          final gid = _selectedGroup!.id!;
          updates['last_group_id'] = gid.toString();
          updates['last_group_name'] = _selectedGroup!.name;

          updates['playlist_${pid}_last_group_id'] = gid.toString();
          updates['playlist_${pid}_last_group_name'] = _selectedGroup!.name;

          if (ch.id != null) {
            updates['group_${gid}_last_channel_id'] = ch.id.toString();
          }
          updates['group_${gid}_last_channel_name'] = ch.name;
          updates['group_${gid}_last_channel_stream_url'] = ch.streamUrl;
        }
      }
    }

    updates['is_favorites_only'] = _isFavoritesOnly ? '1' : '0';
    updates['video_scale_mode'] = _scaleMode.name;
    updates['volume'] = _volume.toString();
    updates['is_muted'] = _isMuted ? '1' : '0';
    updates['buffer_size_bytes'] = _bufferSizeBytes.toString();
    updates['view_mode'] = _viewMode.name;
    updates['playback_rate'] = _playbackRate.toString();

    _persistedSettings.addAll(updates);
    _db.saveSettings(updates).catchError((e) {
      debugPrint('[TvStateProvider] Failed to persist playback state: $e');
    });
  }

  void setBufferSize(int bytes) {
    _bufferSizeBytes = bytes;
    _persistedSettings['buffer_size_bytes'] = bytes.toString();
    _db.saveSetting('buffer_size_bytes', bytes.toString()).ignore();
    notifyListeners();
  }

  void setPlaybackRate(double rate) {
    _playbackRate = rate;
    _activePlayer?.setRate(rate);
    _playbackRateCallback?.call(rate);
    _persistedSettings['playback_rate'] = rate.toString();
    _db.saveSetting('playback_rate', rate.toString()).ignore();
    notifyListeners();
  }

  void setScaleMode(VideoScaleMode mode) {
    _scaleMode = mode;
    _updateNativePipAutoEnter();
    _persistedSettings['video_scale_mode'] = mode.name;
    _db.saveSetting('video_scale_mode', mode.name).ignore();
    notifyListeners();
  }

  TvStateProvider() {
    StreamRecordingService.instance.activeRecordingsCount.addListener(notifyListeners);
    StreamRecordingService.instance.activeBytesProgress.addListener(notifyListeners);
    if (AppPlatform.isDesktop) {
      DesktopPipService.isPipNotifier.addListener(_onDesktopPipChanged);
    }
    _epgRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _loadLivePrograms());
    _epgAutoSyncTimer = Timer.periodic(const Duration(hours: 6), (_) => autoSyncEpgIfNeeded().ignore());
  }

  @override
  void dispose() {
    ScreenWakeService.releaseWakeLock();
    _epgRefreshTimer?.cancel();
    _epgAutoSyncTimer?.cancel();
    StreamRecordingService.instance.activeRecordingsCount.removeListener(notifyListeners);
    StreamRecordingService.instance.activeBytesProgress.removeListener(notifyListeners);
    if (AppPlatform.isDesktop) {
      DesktopPipService.isPipNotifier.removeListener(_onDesktopPipChanged);
    }
    super.dispose();
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      SystemPipService.initialize(
        onPipChanged: (inPip) {
          _isSystemPip = inPip;
          if (inPip) {
            _isPipMode = false;
          } else {
            _updateNativePipAutoEnter();
          }
          notifyListeners();
        },
        onTogglePlayPause: () {
          togglePlayPause();
        },
        onNextChannel: () {
          playNextChannel();
        },
      );
      await RecordingScheduler.instance.initialize();
      _persistedSettings = await _db.getAllSettings();

      // Restore persisted player and view settings
      if (_persistedSettings.containsKey('video_scale_mode')) {
        try {
          _scaleMode = VideoScaleMode.values.firstWhere(
            (m) => m.name == _persistedSettings['video_scale_mode'],
            orElse: () => VideoScaleMode.cover,
          );
        } catch (_) {}
      }
      if (_persistedSettings.containsKey('volume')) {
        final v = double.tryParse(_persistedSettings['volume'] ?? '');
        if (v != null) _volume = v.clamp(0.0, 1.0);
      }
      if (_persistedSettings.containsKey('is_muted')) {
        _isMuted = _persistedSettings['is_muted'] == '1';
      }
      if (_persistedSettings.containsKey('buffer_size_bytes')) {
        final b = int.tryParse(_persistedSettings['buffer_size_bytes'] ?? '');
        if (b != null && b > 0) _bufferSizeBytes = b;
      }
      if (_persistedSettings.containsKey('view_mode')) {
        try {
          _viewMode = TvViewMode.values.firstWhere(
            (v) => v.name == _persistedSettings['view_mode'],
            orElse: () => TvViewMode.quickOverlay,
          );
        } catch (_) {}
      }
      if (_persistedSettings.containsKey('playback_rate')) {
        final r = double.tryParse(_persistedSettings['playback_rate'] ?? '');
        if (r != null && r > 0) _playbackRate = r;
      }
      if (_persistedSettings.containsKey('is_favorites_only')) {
        _isFavoritesOnly = _persistedSettings['is_favorites_only'] == '1';
      }

      _playlists = await _db.getPlaylists();

      if (_playlists.isEmpty) {
        // Automatically scaffold with rich demo channels on first run
        await loadDemoPlaylist();
      } else {
        // Locate last played playlist if persisted
        Playlist? targetPlaylist;
        final savedPidStr = _persistedSettings['last_playlist_id'];
        if (savedPidStr != null) {
          final savedPid = int.tryParse(savedPidStr);
          if (savedPid != null) {
            targetPlaylist = _playlists.where((p) => p.id == savedPid).firstOrNull;
          }
        }
        if (targetPlaylist == null && _persistedSettings.containsKey('last_playlist_url')) {
          final url = _persistedSettings['last_playlist_url'];
          targetPlaylist = _playlists.where((p) => p.url == url).firstOrNull;
        }
        if (targetPlaylist == null && _persistedSettings.containsKey('last_playlist_name')) {
          final name = _persistedSettings['last_playlist_name'];
          targetPlaylist = _playlists.where((p) => p.name == name).firstOrNull;
        }

        _selectedPlaylist = targetPlaylist ?? _playlists.first;
        await _loadGroupsAndChannels(isInitialResume: true);

        // Self-heal: If existing demo playlist has deprecated dead streams (Bloomberg/France24), refresh with active streams
        final hasDeadDemoUrls = _channels.any((c) =>
            c.streamUrl.contains('liveprodupmx.akamaized.net') ||
            c.streamUrl.contains('static.france24.com') ||
            c.streamUrl.contains('live-hls-web-aje.getaj.net'));
        if (hasDeadDemoUrls && _selectedPlaylist?.url == 'https://demo-iptv.internal/playlist.m3u') {
          if (_selectedPlaylist?.id != null) {
            await _db.deletePlaylist(_selectedPlaylist!.id!);
          }
          await loadDemoPlaylist();
        } else if (_channels.isNotEmpty && _activePlayingChannel == null) {
          playChannel(_channels.first);
        }
        // Auto-sync EPG in background if missing, expired, or stale (never blocks video playback)
        autoSyncEpgIfNeeded().ignore();
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadDemoPlaylist() async {
    _isLoading = true;
    notifyListeners();

    try {
      final playlist = Playlist(
        name: 'Demo Public TV',
        type: PlaylistType.m3u,
        url: 'https://demo-iptv.internal/playlist.m3u',
      );

      final playlistId = await _db.insertPlaylist(playlist);
      _playlists = await _db.getPlaylists();
      _selectedPlaylist = _playlists.firstWhere((p) => p.id == playlistId);

      // Insert Demo channels & EPG
      final demoGroups = PlaylistParser.getDemoPlaylists();
      final demoEpg = PlaylistParser.generateDemoEpg();

      await _db.saveParsedPlaylistData(
        playlistId: playlistId,
        groupedChannels: demoGroups,
        epgList: demoEpg,
      );

      await _loadGroupsAndChannels();

      // Start playing the first channel by default
      if (_channels.isNotEmpty) {
        playChannel(_channels.first);
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addM3uPlaylist(String name, String url, {String? customEpgUrl}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final bundle = await PlaylistParser.parseM3uBundleFromUrl(url);
      final effectiveEpgUrl = (customEpgUrl != null && customEpgUrl.trim().isNotEmpty)
          ? customEpgUrl.trim()
          : bundle.epgUrl;

      final playlist = Playlist(
        name: name,
        type: PlaylistType.m3u,
        url: url,
        epgUrl: effectiveEpgUrl,
      );

      final playlistId = await _db.insertPlaylist(playlist);
      await _db.saveParsedPlaylistData(
        playlistId: playlistId,
        groupedChannels: bundle.groups,
      );

      _playlists = await _db.getPlaylists();
      _selectedPlaylist = _playlists.firstWhere((p) => p.id == playlistId);
      await _loadGroupsAndChannels();

      if (effectiveEpgUrl != null && effectiveEpgUrl.isNotEmpty) {
        syncEpgForPlaylist(playlistId, effectiveEpgUrl).ignore();
      }
    } catch (e) {
      _errorMessage = 'Failed to load M3U: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addLocalFilePlaylist(String name, String filePath, {String? customEpgUrlOrPath}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final bundle = await PlaylistParser.parseM3uBundleFromFile(filePath);
      final effectiveEpg = (customEpgUrlOrPath != null && customEpgUrlOrPath.trim().isNotEmpty)
          ? customEpgUrlOrPath.trim()
          : bundle.epgUrl;

      final playlist = Playlist(
        name: name.isNotEmpty ? name : 'Local Playlist',
        type: PlaylistType.m3u,
        url: filePath,
        epgUrl: effectiveEpg,
      );

      final playlistId = await _db.insertPlaylist(playlist);
      await _db.saveParsedPlaylistData(
        playlistId: playlistId,
        groupedChannels: bundle.groups,
      );

      _playlists = await _db.getPlaylists();
      _selectedPlaylist = _playlists.firstWhere((p) => p.id == playlistId);
      await _loadGroupsAndChannels();

      if (effectiveEpg != null && effectiveEpg.isNotEmpty) {
        syncEpgForPlaylist(playlistId, effectiveEpg).ignore();
      }
    } catch (e) {
      _errorMessage = 'Failed to read local file: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int> syncEpgForPlaylist(int playlistId, String epgUrlOrPath) async {
    try {
      final result = await EpgParser.fetchAndParseEpgWithResult(epgUrlOrPath);
      final programs = result.programs;
      if (programs.isNotEmpty) {
        await _db.saveEpgPrograms(programs);
        await _db.updatePlaylistEpgUrl(playlistId, result.effectiveUrlOrPath);
        await _db.updatePlaylistEpgSyncTime(playlistId, DateTime.now().millisecondsSinceEpoch);

        _playlists = await _db.getPlaylists();
        await _loadLivePrograms();
        if (_selectedPlaylist?.id == playlistId) {
          _selectedPlaylist = _playlists.firstWhere((p) => p.id == playlistId);
          await _loadEpgForSelectedChannel();
        }
        notifyListeners();
      }
      return programs.length;
    } catch (e) {
      debugPrint('[TvStateProvider] EPG sync error: $e');
      rethrow;
    }
  }

  Future<int?> autoSyncEpgIfNeeded({bool force = false}) async {
    final playlist = _selectedPlaylist;
    if (playlist == null) return null;
    final epgUrl = playlist.epgUrl?.trim();
    if (epgUrl == null || epgUrl.isEmpty) return null;

    final pid = playlist.id;
    if (pid == null) return null;

    if (_isEpgSyncing) return null; // Avoid concurrent duplicate syncs

    final futureCount = await _db.getFutureEpgProgramCountForPlaylist(pid);
    final isStale = playlist.isEpgStale;

    if (force || isStale || futureCount == 0) {
      _isEpgSyncing = true;
      notifyListeners();

      try {
        final count = await syncEpgForPlaylist(pid, epgUrl);
        debugPrint('[TvStateProvider] Auto-synced $count EPG programs for "${playlist.name}"');
        return count;
      } catch (e) {
        debugPrint('[TvStateProvider] Auto-sync EPG non-critical error: $e');
        return null;
      } finally {
        _isEpgSyncing = false;
        notifyListeners();
      }
    }
    return null;
  }

  Future<void> updatePlaylistEpgUrl(int playlistId, String? epgUrl) async {
    await _db.updatePlaylistEpgUrl(playlistId, epgUrl);
    _playlists = await _db.getPlaylists();
    if (_selectedPlaylist?.id == playlistId) {
      _selectedPlaylist = _playlists.firstWhere((p) => p.id == playlistId);
    }
    notifyListeners();

    if (epgUrl != null && epgUrl.trim().isNotEmpty) {
      await syncEpgForPlaylist(playlistId, epgUrl.trim());
    }
  }

  Future<void> addLocalBytesPlaylist(String name, Uint8List bytes) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final parsed = PlaylistParser.parseM3uFromBytes(bytes);
      final playlist = Playlist(
        name: name.isNotEmpty ? name : 'Imported Playlist',
        type: PlaylistType.m3u,
        url: 'memory://playlist.m3u',
      );

      final playlistId = await _db.insertPlaylist(playlist);
      await _db.saveParsedPlaylistData(
        playlistId: playlistId,
        groupedChannels: parsed,
      );

      _playlists = await _db.getPlaylists();
      _selectedPlaylist = _playlists.firstWhere((p) => p.id == playlistId);
      await _loadGroupsAndChannels();
    } catch (e) {
      _errorMessage = 'Failed to parse file: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addXtreamPlaylist(String name, String serverUrl, String username, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final xtream = XtreamService(
        serverUrl: serverUrl,
        username: username,
        password: password,
      );

      final isValid = await xtream.authenticate();
      if (!isValid) {
        throw Exception('Xtream Authentication failed. Please verify credentials.');
      }

      final parsed = await xtream.fetchLiveStreams();
      final playlist = Playlist(
        name: name,
        type: PlaylistType.xtream,
        url: serverUrl,
        username: username,
        password: password,
        epgUrl: xtream.epgUrl,
      );

      final playlistId = await _db.insertPlaylist(playlist);
      await _db.saveParsedPlaylistData(
        playlistId: playlistId,
        groupedChannels: parsed,
      );

      _playlists = await _db.getPlaylists();
      _selectedPlaylist = _playlists.firstWhere((p) => p.id == playlistId);
      await _loadGroupsAndChannels();

      syncEpgForPlaylist(playlistId, xtream.epgUrl).ignore();
    } catch (e) {
      _errorMessage = 'Xtream error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> switchPlaylist(Playlist playlist) async {
    if (_selectedPlaylist?.id == playlist.id) return;
    _isLoading = true;
    _errorMessage = null;
    _selectedPlaylist = playlist;
    _selectedGroup = null;
    _selectedChannel = null;
    _activePlayingChannel = null;
    _isPlaying = false;
    _updateNativePipAutoEnter();

    // Persist switched playlist immediately
    final pid = playlist.id;
    if (pid != null) {
      final updates = {
        'last_playlist_id': pid.toString(),
        'last_playlist_name': playlist.name,
        'last_playlist_url': playlist.url,
      };
      _persistedSettings.addAll(updates);
      _db.saveSettings(updates).ignore();
    }
    notifyListeners();

    try {
      await _loadGroupsAndChannels(isInitialResume: false);
      // Auto-sync EPG in background for the newly loaded playlist if needed
      autoSyncEpgIfNeeded().ignore();
    } catch (e) {
      _errorMessage = 'Failed to switch playlist: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> renamePlaylist(int playlistId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    try {
      await _db.renamePlaylist(playlistId, trimmed);
      _playlists = await _db.getPlaylists();
      if (_selectedPlaylist?.id == playlistId) {
        _selectedPlaylist = _playlists.firstWhere((p) => p.id == playlistId);
        _persistedSettings['last_playlist_name'] = trimmed;
        _db.saveSetting('last_playlist_name', trimmed).ignore();
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to rename playlist: $e';
      notifyListeners();
    }
  }

  Future<void> deletePlaylist(int playlistId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _db.deletePlaylist(playlistId);
      _persistedSettings.removeWhere((k, _) => k.startsWith('playlist_${playlistId}_'));
      if (_persistedSettings['last_playlist_id'] == playlistId.toString()) {
        _persistedSettings.remove('last_playlist_id');
        _persistedSettings.remove('last_playlist_name');
        _persistedSettings.remove('last_playlist_url');
      }

      _playlists = await _db.getPlaylists();
      if (_selectedPlaylist?.id == playlistId) {
        if (_playlists.isNotEmpty) {
          _selectedPlaylist = _playlists.first;
          _selectedGroup = null;
          await _loadGroupsAndChannels();
          if (_channels.isNotEmpty) {
            playChannel(_channels.first);
          }
        } else {
          _selectedPlaylist = null;
          _groups = [];
          _channels = [];
          _selectedChannel = null;
          _activePlayingChannel = null;
          await loadDemoPlaylist();
        }
      }
    } catch (e) {
      _errorMessage = 'Failed to delete playlist: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int> getPlaylistChannelCount(int playlistId) async {
    return await _db.getChannelCount(playlistId);
  }

  Future<void> _loadGroupsAndChannels({bool isInitialResume = false}) async {
    if (_selectedPlaylist?.id == null) return;
    final pid = _selectedPlaylist!.id!;

    _groups = await _db.getGroups(pid);

    // Check if favorites mode was saved for this playlist
    final favKey = 'playlist_${pid}_is_favorites_only';
    if (_persistedSettings.containsKey(favKey)) {
      _isFavoritesOnly = _persistedSettings[favKey] == '1';
    } else if (isInitialResume && _persistedSettings.containsKey('is_favorites_only')) {
      _isFavoritesOnly = _persistedSettings['is_favorites_only'] == '1';
    }

    if (!_isFavoritesOnly && _groups.isNotEmpty) {
      ChannelGroup? targetGroup;
      final savedGidStr = _persistedSettings['playlist_${pid}_last_group_id'] ??
          (isInitialResume ? _persistedSettings['last_group_id'] : null);
      if (savedGidStr != null) {
        final savedGid = int.tryParse(savedGidStr);
        if (savedGid != null) {
          targetGroup = _groups.where((g) => g.id == savedGid).firstOrNull;
        }
      }
      if (targetGroup == null) {
        final savedGroupName = _persistedSettings['playlist_${pid}_last_group_name'] ??
            (isInitialResume ? _persistedSettings['last_group_name'] : null);
        if (savedGroupName != null) {
          targetGroup = _groups.where((g) => g.name.toLowerCase() == savedGroupName.toLowerCase()).firstOrNull;
        }
      }
      _selectedGroup = targetGroup ?? _groups.first;
    } else if (!_isFavoritesOnly && _groups.isNotEmpty && _selectedGroup == null) {
      _selectedGroup = _groups.first;
    }

    await _refreshChannels(isInitialResume: isInitialResume);
  }

  Future<void> _refreshChannels({bool isInitialResume = false, int? preferredChannelId}) async {
    if (_selectedPlaylist?.id == null) return;
    final pid = _selectedPlaylist!.id!;

    _channels = await _db.getChannels(
      playlistId: pid,
      groupId: _isFavoritesOnly ? null : _selectedGroup?.id,
      favoritesOnly: _isFavoritesOnly,
      searchQuery: _searchQuery,
    );

    await _loadLivePrograms();

    if (_channels.isNotEmpty) {
      Channel? targetChannel;

      if (_searchQuery.trim().isNotEmpty) {
        if (_activePlayingChannel != null) {
          targetChannel = _channels.where((c) => c.id == _activePlayingChannel!.id).firstOrNull;
        }
        targetChannel ??= _channels.first;
        _selectedChannel = targetChannel;
        await _loadEpgForSelectedChannel();
      } else {
        if (preferredChannelId != null) {
          targetChannel = _channels.where((c) => c.id == preferredChannelId).firstOrNull;
        }

        // 1. Try per-group last channel if a specific group is selected
        if (targetChannel == null && !_isFavoritesOnly && _selectedGroup?.id != null) {
          final gid = _selectedGroup!.id!;
          final gidStr = _persistedSettings['group_${gid}_last_channel_id'];
          if (gidStr != null) {
            final chId = int.tryParse(gidStr);
            if (chId != null) {
              targetChannel = _channels.where((c) => c.id == chId).firstOrNull;
            }
          }
          if (targetChannel == null) {
            final sUrl = _persistedSettings['group_${gid}_last_channel_stream_url'];
            if (sUrl != null) {
              targetChannel = _channels.where((c) => c.streamUrl == sUrl).firstOrNull;
            }
          }
          if (targetChannel == null) {
            final sName = _persistedSettings['group_${gid}_last_channel_name'];
            if (sName != null) {
              targetChannel = _channels.where((c) => c.name.toLowerCase() == sName.toLowerCase()).firstOrNull;
            }
          }
        }

        // 2. Try favorites last channel if favorites mode is active
        if (targetChannel == null && _isFavoritesOnly) {
          final favChIdStr = _persistedSettings['playlist_${pid}_fav_last_channel_id'];
          if (favChIdStr != null) {
            final chId = int.tryParse(favChIdStr);
            if (chId != null) {
              targetChannel = _channels.where((c) => c.id == chId).firstOrNull;
            }
          }
        }

        // 3. Try playlist last channel
        if (targetChannel == null) {
          final playChIdStr = _persistedSettings['playlist_${pid}_last_channel_id'] ??
              (isInitialResume ? _persistedSettings['last_channel_id'] : null);
          if (playChIdStr != null) {
            final chId = int.tryParse(playChIdStr);
            if (chId != null) {
              targetChannel = _channels.where((c) => c.id == chId).firstOrNull;
            }
          }
          if (targetChannel == null) {
            final sUrl = _persistedSettings['playlist_${pid}_last_channel_stream_url'] ??
                (isInitialResume ? _persistedSettings['last_channel_stream_url'] : null);
            if (sUrl != null) {
              targetChannel = _channels.where((c) => c.streamUrl == sUrl).firstOrNull;
            }
          }
          if (targetChannel == null) {
            final sName = _persistedSettings['playlist_${pid}_last_channel_name'] ??
                (isInitialResume ? _persistedSettings['last_channel_name'] : null);
            if (sName != null) {
              targetChannel = _channels.where((c) => c.name.toLowerCase() == sName.toLowerCase()).firstOrNull;
            }
          }
        }

        // 4. Try current active playing channel if still present in this filtered list
        if (targetChannel == null && _activePlayingChannel != null) {
          targetChannel = _channels.where((c) => c.id == _activePlayingChannel!.id).firstOrNull;
        }

        // 5. Fallback to first channel in list
        _selectedChannel = targetChannel ?? _channels.first;

        if (isInitialResume || _activePlayingChannel == null) {
          playChannel(_selectedChannel!, saveState: true);
        } else {
          await _loadEpgForSelectedChannel();
        }
      }
    } else {
      _selectedChannel = null;
      _currentProgram = null;
      _upcomingPrograms = [];
    }
    notifyListeners();
  }

  Future<void> _loadLivePrograms() async {
    try {
      final live = await _db.getLivePrograms();
      _liveProgramsMap = live;
      notifyListeners();
    } catch (e) {
      debugPrint('[TvStateProvider] Failed to load live programs: $e');
    }
  }

  Future<void> _loadEpgForSelectedChannel() async {
    final channel = _selectedChannel;
    if (channel == null) {
      _currentProgram = null;
      _upcomingPrograms = [];
      return;
    }

    final candidateId = (channel.tvgId != null && channel.tvgId!.trim().isNotEmpty)
        ? channel.tvgId!.trim()
        : channel.name.trim();

    if (candidateId.isEmpty) {
      _currentProgram = null;
      _upcomingPrograms = [];
      return;
    }

    try {
      var current = await _db.getCurrentProgram(candidateId);
      var upcoming = await _db.getUpcomingPrograms(candidateId, limit: 4);

      // If candidateId was tvgId and yielded no program, try channel.name as fallback
      if (current == null && channel.name.trim().isNotEmpty && channel.name.trim() != candidateId) {
        current = await _db.getCurrentProgram(channel.name.trim());
        if (upcoming.isEmpty) {
          upcoming = await _db.getUpcomingPrograms(channel.name.trim(), limit: 4);
        }
      }

      _currentProgram = current;
      _upcomingPrograms = upcoming;
      notifyListeners();
    } catch (e) {
      debugPrint('[TvStateProvider] Failed to load EPG for channel: $e');
    }
  }

  void selectGroup(ChannelGroup? group) {
    _isFavoritesOnly = false;
    _selectedGroup = group;
    final updates = <String, String>{
      'is_favorites_only': '0',
    };
    if (group?.id != null) {
      final gid = group!.id!;
      updates['last_group_id'] = gid.toString();
      updates['last_group_name'] = group.name;
    }
    if (_selectedPlaylist?.id != null && group?.id != null) {
      final pid = _selectedPlaylist!.id!;
      final gid = group!.id!;
      updates['playlist_${pid}_last_group_id'] = gid.toString();
      updates['playlist_${pid}_last_group_name'] = group.name;
      updates['playlist_${pid}_is_favorites_only'] = '0';
    }
    _persistedSettings.addAll(updates);
    _db.saveSettings(updates).ignore();
    _refreshChannels();
  }

  void toggleFavoritesFilter() {
    _isFavoritesOnly = !_isFavoritesOnly;
    final val = _isFavoritesOnly ? '1' : '0';
    final updates = <String, String>{
      'is_favorites_only': val,
    };
    if (_selectedPlaylist?.id != null) {
      final pid = _selectedPlaylist!.id!;
      updates['playlist_${pid}_is_favorites_only'] = val;
    }
    _persistedSettings.addAll(updates);
    _db.saveSettings(updates).ignore();
    _refreshChannels();
  }

  void selectChannel(Channel channel) {
    _selectedChannel = channel;
    _loadEpgForSelectedChannel();
    if (_selectedPlaylist?.id != null && channel.id != null) {
      final pid = _selectedPlaylist!.id!;
      final updates = <String, String>{
        'playlist_${pid}_last_channel_id': channel.id.toString(),
        'playlist_${pid}_last_channel_name': channel.name,
        'playlist_${pid}_last_channel_stream_url': channel.streamUrl,
      };
      if (_selectedGroup?.id != null) {
        final gid = _selectedGroup!.id!;
        updates['group_${gid}_last_channel_id'] = channel.id.toString();
        updates['group_${gid}_last_channel_name'] = channel.name;
        updates['group_${gid}_last_channel_stream_url'] = channel.streamUrl;
      }
      _persistedSettings.addAll(updates);
      _db.saveSettings(updates).ignore();
    }
  }

  void playChannel(Channel channel, {bool saveState = true}) {
    _selectedChannel = channel;
    _activePlayingChannel = channel;
    _isPlaying = true;
    _loadEpgForSelectedChannel();
    _updateNativePipAutoEnter();
    if (saveState) {
      _saveCurrentPlaybackState();
    }
    notifyListeners();
  }

  void playNextChannel() {
    if (_channels.isEmpty || _activePlayingChannel == null) return;
    final currentIndex = _channels.indexWhere((c) => c.id == _activePlayingChannel!.id);
    if (currentIndex != -1 && currentIndex + 1 < _channels.length) {
      playChannel(_channels[currentIndex + 1]);
    } else if (_channels.isNotEmpty) {
      playChannel(_channels.first);
    }
  }

  void playPreviousChannel() {
    if (_channels.isEmpty || _activePlayingChannel == null) return;
    final currentIndex = _channels.indexWhere((c) => c.id == _activePlayingChannel!.id);
    if (currentIndex > 0) {
      playChannel(_channels[currentIndex - 1]);
    } else if (_channels.isNotEmpty) {
      playChannel(_channels.last);
    }
  }

  Future<void> toggleFavorite(Channel channel) async {
    if (channel.id == null) return;
    final newFav = !channel.isFavorite;
    await _db.toggleFavorite(channel.id!, newFav);

    // Update in memory
    final index = _channels.indexWhere((c) => c.id == channel.id);
    if (index != -1) {
      _channels[index] = channel.copyWith(isFavorite: newFav);
    }
    if (_selectedChannel?.id == channel.id) {
      _selectedChannel = _selectedChannel!.copyWith(isFavorite: newFav);
    }
    if (_activePlayingChannel?.id == channel.id) {
      _activePlayingChannel = _activePlayingChannel!.copyWith(isFavorite: newFav);
    }
    notifyListeners();
  }

  void toggleEpgOverlay() {
    _isEpgOverlayVisible = !_isEpgOverlayVisible;
    notifyListeners();
  }

  void setViewMode(TvViewMode mode) {
    _viewMode = mode;
    _persistedSettings['view_mode'] = mode.name;
    _db.saveSetting('view_mode', mode.name).ignore();
    notifyListeners();
  }

  void toggleBottomChannelList() {
    _showBottomChannelList = !_showBottomChannelList;
    notifyListeners();
  }

  void setBottomChannelList(bool show) {
    if (_showBottomChannelList != show) {
      _showBottomChannelList = show;
      notifyListeners();
    }
  }

  void cycleViewMode() {
    switch (_viewMode) {
      case TvViewMode.quickOverlay:
        _viewMode = TvViewMode.epgGrid;
        break;
      case TvViewMode.epgGrid:
        _viewMode = TvViewMode.bottomScrollList;
        break;
      case TvViewMode.bottomScrollList:
        _viewMode = TvViewMode.quickOverlay;
        break;
    }
    _persistedSettings['view_mode'] = _viewMode.name;
    _db.saveSetting('view_mode', _viewMode.name).ignore();
    notifyListeners();
  }

  void cycleScaleMode() {
    switch (_scaleMode) {
      case VideoScaleMode.cover:
        _scaleMode = VideoScaleMode.contain;
        break;
      case VideoScaleMode.contain:
        _scaleMode = VideoScaleMode.fitWidth;
        break;
      case VideoScaleMode.fitWidth:
        _scaleMode = VideoScaleMode.fitHeight;
        break;
      case VideoScaleMode.fitHeight:
        _scaleMode = VideoScaleMode.fourThree;
        break;
      case VideoScaleMode.fourThree:
        _scaleMode = VideoScaleMode.sixteenNine;
        break;
      case VideoScaleMode.sixteenNine:
        _scaleMode = VideoScaleMode.cover;
        break;
    }
    _updateNativePipAutoEnter();
    _persistedSettings['video_scale_mode'] = _scaleMode.name;
    _db.saveSetting('video_scale_mode', _scaleMode.name).ignore();
    notifyListeners();
  }

  void togglePlayPause() {
    _isPlaying = !_isPlaying;
    _updateNativePipAutoEnter();
    notifyListeners();
  }

  void stopPlayback() {
    _isPlaying = false;
    _updateNativePipAutoEnter();
    notifyListeners();
  }

  void resumePlayback() {
    _isPlaying = true;
    _updateNativePipAutoEnter();
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    _persistedSettings['is_muted'] = _isMuted ? '1' : '0';
    _db.saveSetting('is_muted', _isMuted ? '1' : '0').ignore();
    notifyListeners();
  }

  void setVolume(double val) {
    _volume = val.clamp(0.0, 1.0);
    _isMuted = _volume == 0;
    _persistedSettings['volume'] = _volume.toString();
    _persistedSettings['is_muted'] = _isMuted ? '1' : '0';
    _db.saveSettings({
      'volume': _volume.toString(),
      'is_muted': _isMuted ? '1' : '0',
    }).ignore();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _refreshChannels();
  }

  // --- DVR RECORDING OPERATIONS ---
  bool isRecordingChannel(int channelId) {
    return StreamRecordingService.instance.isRecordingChannel(channelId);
  }

  bool get isCurrentChannelRecording {
    if (_activePlayingChannel?.id == null) return false;
    return isRecordingChannel(_activePlayingChannel!.id!);
  }

  RecordingItem? get currentChannelRecordingItem {
    if (_activePlayingChannel?.id == null) return null;
    return StreamRecordingService.instance.getActiveJobForChannel(_activePlayingChannel!.id!);
  }

  int get currentChannelBytesRecorded {
    final item = currentChannelRecordingItem;
    if (item?.id == null) return 0;
    return StreamRecordingService.instance.activeBytesProgress.value[item!.id!] ?? item.bytesRecorded;
  }

  Future<void> toggleRecordActiveChannel({Duration duration = const Duration(minutes: 60)}) async {
    if (_activePlayingChannel == null) return;
    final chId = _activePlayingChannel!.id ?? 0;
    if (isRecordingChannel(chId)) {
      await RecordingScheduler.instance.stopRecordingForChannel(chId);
    } else {
      await RecordingScheduler.instance.startInstantRecording(
        channel: _activePlayingChannel!,
        currentProgram: _currentProgram,
        duration: duration,
      );
    }
    notifyListeners();
  }

  Future<void> startInstantRecording({Duration duration = const Duration(minutes: 60)}) async {
    if (_activePlayingChannel == null) return;
    await RecordingScheduler.instance.startInstantRecording(
      channel: _activePlayingChannel!,
      currentProgram: _currentProgram,
      duration: duration,
    );
    notifyListeners();
  }

  Future<void> stopActiveChannelRecording() async {
    if (_activePlayingChannel?.id == null) return;
    await RecordingScheduler.instance.stopRecordingForChannel(_activePlayingChannel!.id!);
    notifyListeners();
  }

  Future<RecordingItem?> scheduleProgramRecording(
    Channel channel,
    EpgProgram program, {
    int preRoll = 2,
    int postRoll = 5,
  }) async {
    final item = await RecordingScheduler.instance.scheduleProgramRecording(
      channel: channel,
      program: program,
      preRollMinutes: preRoll,
      postRollMinutes: postRoll,
    );
    notifyListeners();
    return item;
  }

  Future<List<RecordingItem>> fetchAllRecordings() async {
    return await _db.getAllRecordings();
  }

  Future<void> deleteRecording(RecordingItem item) async {
    await RecordingScheduler.instance.deleteRecordingWithFile(item);
    notifyListeners();
  }

  Future<void> cancelRecording(int recordingId) async {
    await RecordingScheduler.instance.cancelRecording(recordingId);
    notifyListeners();
  }
}
