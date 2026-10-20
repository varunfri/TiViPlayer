import 'dart:async';
import '../../services/app_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/channel.dart';
import '../../models/playlist.dart';
import '../../providers/tv_state_provider.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/video_player_widget.dart';
import '../../ui/widgets/channel_tile_widget.dart';
import '../../ui/widgets/epg_detail_panel.dart';
import '../../ui/widgets/epg_grid_view.dart';
import '../../ui/widgets/player_controls_osd.dart';
import '../../services/system_pip_service.dart';
import '../widgets/tv_toast.dart';
import '../widgets/bottom_channel_scroll_list.dart';
import 'playlist_manager_dialog.dart';
import 'recordings_screen.dart';
import 'stream_settings_dialog.dart';
import '../widgets/desktop_pip_view.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({super.key});

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();
  final GlobalKey _playerGlobalKey = GlobalKey();

  bool _showOsdInFullscreen = false;
  bool _isMobileSearchOpen = false;
  Timer? _osdHideTimer;
  int? _lastPlayedChannelId;
  int? _lastSelectedGroupId;

  final ScrollController _channelsScrollController = ScrollController();
  final ScrollController _groupsScrollController = ScrollController();
  final ScrollController _mobileCategoriesScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (AppPlatform.isMobile) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TvStateProvider>().initialize();
    });
    SystemPipService.addPipListener(_onPipChanged);
  }

  void _onPipChanged(bool inPip) {
    if (inPip && mounted) {
      if (AppPlatform.isMobile) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      // Pop open dialogs when entering system PiP so only the video shows
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _enterFullscreenLandscape(TvStateProvider tvState) async {
    if (AppPlatform.isMobile) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (tvState.isEpgOverlayVisible) {
      tvState.toggleEpgOverlay();
    }
  }

  Future<void> _exitFullscreenPortrait(TvStateProvider tvState) async {
    if (AppPlatform.isMobile) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (!tvState.isEpgOverlayVisible) {
      tvState.toggleEpgOverlay();
    }
  }

  void _toggleFullscreenOrientation(TvStateProvider tvState) {
    if (tvState.isEpgOverlayVisible) {
      _enterFullscreenLandscape(tvState);
    } else {
      _exitFullscreenPortrait(tvState);
    }
  }

  @override
  void dispose() {
    if (AppPlatform.isMobile) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    SystemPipService.removePipListener(_onPipChanged);
    _searchController.dispose();
    _keyboardFocusNode.dispose();
    _channelsScrollController.dispose();
    _groupsScrollController.dispose();
    _mobileCategoriesScrollController.dispose();
    _osdHideTimer?.cancel();
    super.dispose();
  }

  void _scrollToActiveChannel(TvStateProvider tvState) {
    if (!_channelsScrollController.hasClients) return;
    final activeId = tvState.activePlayingChannel?.id ?? tvState.selectedChannel?.id;
    if (activeId == null) return;
    final index = tvState.channels.indexWhere((c) => c.id == activeId);
    if (index >= 0) {
      const itemHeight = 72.0;
      final target = (index * itemHeight - 80.0).clamp(
        0.0,
        _channelsScrollController.position.maxScrollExtent,
      );
      _channelsScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollToSelectedGroup(TvStateProvider tvState) {
    final groupId = tvState.selectedGroup?.id;
    if (groupId == null) return;
    final index = tvState.groups.indexWhere((g) => g.id == groupId);
    if (index < 0) return;

    if (_groupsScrollController.hasClients) {
      const itemHeight = 48.0;
      final target = (index * itemHeight - 60.0).clamp(
        0.0,
        _groupsScrollController.position.maxScrollExtent,
      );
      _groupsScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

    if (_mobileCategoriesScrollController.hasClients) {
      const chipWidth = 110.0;
      final target = (index * chipWidth - 40.0).clamp(
        0.0,
        _mobileCategoriesScrollController.position.maxScrollExtent,
      );
      _mobileCategoriesScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _triggerOsd() {
    setState(() => _showOsdInFullscreen = true);
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showOsdInFullscreen = false);
      }
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final tvState = context.read<TvStateProvider>();

      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.goBack) {
        if (tvState.showBottomChannelList) {
          tvState.setBottomChannelList(false);
        } else if (_showOsdInFullscreen) {
          setState(() => _showOsdInFullscreen = false);
        } else if (!tvState.isEpgOverlayVisible) {
          _exitFullscreenPortrait(tvState);
        } else if (tvState.isPlaying) {
          tvState.enterSystemPip(context: context);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _toggleFullscreenOrientation(tvState);
      } else if (event.logicalKey == LogicalKeyboardKey.keyC) {
        tvState.toggleBottomChannelList();
      } else if (event.logicalKey == LogicalKeyboardKey.keyG) {
        tvState.cycleViewMode();
      } else if (event.logicalKey == LogicalKeyboardKey.keyA) {
        tvState.cycleScaleMode();
      } else if (event.logicalKey == LogicalKeyboardKey.keyM) {
        tvState.toggleMute();
        _triggerOsd();
      } else if (event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.keyS) {
        tvState.togglePlayPause();
        _triggerOsd();
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
          !tvState.isEpgOverlayVisible) {
        tvState.playPreviousChannel();
        _triggerOsd();
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
          !tvState.isEpgOverlayVisible) {
        tvState.playNextChannel();
        _triggerOsd();
      } else if (event.logicalKey == LogicalKeyboardKey.keyR) {
        showDialog(context: context, builder: (_) => const RecordingsScreen());
      } else if (event.logicalKey == LogicalKeyboardKey.keyP) {
        tvState.enterSystemPip(context: context);
      } else if (event.logicalKey == LogicalKeyboardKey.keyO ||
                 event.logicalKey == LogicalKeyboardKey.keyS ||
                 event.logicalKey == LogicalKeyboardKey.keyQ) {
        showDialog(
          context: context,
          builder: (_) => const StreamSettingsDialog(initialTabIndex: 0),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tvState = context.watch<TvStateProvider>();
    final isFloatingPip = tvState.isPipMode && tvState.isEpgOverlayVisible;
    final size = MediaQuery.sizeOf(context);
    final orientation = MediaQuery.orientationOf(context);
    final isMobile = size.shortestSide < 600;
    final isMobilePortrait = isMobile && orientation == Orientation.portrait;
    final isTablet = size.shortestSide >= 600 && size.shortestSide < 900;

    final playerWidget = VideoPlayerWidget(
      key: _playerGlobalKey,
      channel: tvState.activePlayingChannel,
      isMuted: tvState.isMuted,
      scaleMode: tvState.scaleMode,
      isPlaying: tvState.isPlaying,
    );

    // When desktop floating PiP is active (always-on-top window over other apps)
    if (tvState.isDesktopPip) {
      return DesktopPipView(playerWidget: playerWidget);
    }

    // When system-wide PiP is active, render only the clean video stream
    // filling 100% of the native Android PiP floating window
    if (tvState.isSystemPip) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(child: playerWidget),
      );
    }

    final currentChannelId = tvState.activePlayingChannel?.id;
    final currentGroupId = tvState.selectedGroup?.id;
    if (currentChannelId != null && currentChannelId != _lastPlayedChannelId) {
      _lastPlayedChannelId = currentChannelId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (!tvState.isEpgOverlayVisible) {
            _triggerOsd();
          }
          _scrollToActiveChannel(tvState);
        }
      });
    }
    if (currentGroupId != null && currentGroupId != _lastSelectedGroupId) {
      _lastSelectedGroupId = currentGroupId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToSelectedGroup(tvState);
        }
      });
    }

    return PopScope(
      canPop:
          !isMobilePortrait &&
          tvState.isEpgOverlayVisible &&
          !tvState.isPlaying,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (tvState.showBottomChannelList) {
          tvState.setBottomChannelList(false);
          return;
        }
        if (_showOsdInFullscreen) {
          setState(() => _showOsdInFullscreen = false);
          return;
        }
        if (!tvState.isEpgOverlayVisible) {
          // Exit fullscreen, return to portrait split view
          _exitFullscreenPortrait(tvState);
          return;
        }
        if (tvState.isPlaying) {
          // While browsing in portrait with active video, Back key smoothly floats to PiP!
          tvState.enterSystemPip(context: context);
          return;
        }
      },
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: TvTheme.background,
          body: isMobilePortrait
              ? _buildMobilePortraitBody(context, tvState, playerWidget)
              : _buildWidescreenBody(
                  context,
                  tvState,
                  playerWidget,
                  isFloatingPip,
                  isMobile,
                  isTablet,
                  size,
                ),
        ),
      ),
    );
  }

  Widget _buildMobilePortraitBody(
    BuildContext context,
    TvStateProvider tvState,
    Widget playerWidget,
  ) {
    if (tvState.isEpgOverlayVisible) {
      return SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. TOP VIDEO PLAYER (16:9 Aspect Ratio)
            Container(
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  children: [
                    Positioned.fill(child: playerWidget),
                    if (tvState.isPlaying)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => tvState.togglePlayPause(),
                          onDoubleTap: () => _enterFullscreenLandscape(tvState),
                        ),
                      ),
                    _buildMobilePlayerOverlay(context, tvState),
                  ],
                ),
              ),
            ),

            // 2. BOTTOM CHANNELS / EPG BROWSER
            Expanded(
              child: Container(
                color: TvTheme.background,
                child: Column(
                  children: [
                    _buildTopBar(context, tvState, true),
                    _buildMobileCategoriesRow(context, tvState),
                    const Divider(color: TvTheme.borderSubtle, height: 1),
                    Expanded(
                      child: tvState.viewMode == TvViewMode.epgGrid
                          ? EpgGridView(tvState: tvState)
                          : tvState.viewMode == TvViewMode.bottomScrollList
                          ? Column(
                              children: [
                                Expanded(
                                  child: EpgDetailPanel(
                                    channel: tvState.selectedChannel,
                                    currentProgram: tvState.currentProgram,
                                    upcomingPrograms: tvState.upcomingPrograms,
                                    onToggleFavorite: () {
                                      final ch = tvState.selectedChannel;
                                      if (ch != null) {
                                        tvState.toggleFavorite(ch);
                                      }
                                    },
                                    onToggleFullscreen: () =>
                                        _enterFullscreenLandscape(tvState),
                                  ),
                                ),
                                // const Divider(
                                //   color: TvTheme.borderSubtle,
                                //   height: 1,
                                // ),
                                BottomChannelScrollListWidget(
                                  tvState: tvState,
                                  isStandalone: true,
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Expanded(
                                  child: _buildChannelsColumn(
                                    context,
                                    tvState,
                                    isMobile: true,
                                  ),
                                ),
                                if (tvState.showBottomChannelList)
                                  BottomChannelScrollListWidget(
                                    tvState: tvState,
                                    onClose: () =>
                                        tvState.setBottomChannelList(false),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Fullscreen Mobile Video View
    return Stack(
      children: [
        Positioned.fill(child: playerWidget),
        if (tvState.isPlaying)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _triggerOsd();
              },
              onDoubleTap: () => _exitFullscreenPortrait(tvState),
            ),
          ),
        if (tvState.showBottomChannelList)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BottomChannelScrollListWidget(
              tvState: tvState,
              onClose: () => tvState.setBottomChannelList(false),
            ),
          ),
        if (_showOsdInFullscreen && !tvState.showBottomChannelList)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: PlayerControlsOsd(
              channel: tvState.activePlayingChannel,
              currentProgram: tvState.currentProgram,
              tvState: tvState,
              onOpenGuide: () => _exitFullscreenPortrait(tvState),
            ),
          ),
        if (!_showOsdInFullscreen && !tvState.showBottomChannelList)
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => _exitFullscreenPortrait(tvState),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Guide',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => tvState.toggleBottomChannelList(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: tvState.showBottomChannelList
                              ? TvTheme.primaryAccent
                              : Colors.white24,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.view_carousel_rounded,
                            size: 16,
                            color: tvState.showBottomChannelList
                                ? TvTheme.primaryAccent
                                : Colors.white,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Channels',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMobilePlayerOverlay(
    BuildContext context,
    TvStateProvider tvState,
  ) {
    final channel = tvState.activePlayingChannel;
    return Positioned.fill(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top Controls Bar with Gradient
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    channel != null
                        ? '#${channel.channelNumber} ${channel.name}'
                        : 'Live TV',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    tvState.isMuted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    color: tvState.isMuted ? Colors.redAccent : Colors.white,
                    size: 18,
                  ),
                  tooltip: tvState.isMuted ? 'Unmute' : 'Mute',
                  onPressed: () => tvState.toggleMute(),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.picture_in_picture_alt_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  tooltip: 'Picture-in-Picture',
                  onPressed: () => tvState.enterSystemPip(context: context),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    tvState.showBottomChannelList
                        ? Icons.view_carousel_rounded
                        : Icons.view_carousel_outlined,
                    color: tvState.showBottomChannelList
                        ? TvTheme.primaryAccent
                        : Colors.white,
                    size: 18,
                  ),
                  tooltip: 'Bottom Channels',
                  onPressed: () => tvState.toggleBottomChannelList(),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: const Icon(
                    Icons.fullscreen_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  tooltip: 'Fullscreen',
                  onPressed: () => _enterFullscreenLandscape(tvState),
                ),
              ],
            ),
          ),

          // Bottom Quick Bar: Scale Mode & Play/Pause indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.75),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: () => tvState.cycleScaleMode(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white24, width: 0.5),
                    ),
                    child: Text(
                      tvState.scaleMode.name.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => tvState.togglePlayPause(),
                  child: Icon(
                    tvState.isPlaying
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidescreenBody(
    BuildContext context,
    TvStateProvider tvState,
    Widget playerWidget,
    bool isFloatingPip,
    bool isMobile,
    bool isTablet,
    Size size,
  ) {
    return MouseRegion(
      onHover: (_) {
        if (!tvState.isEpgOverlayVisible) {
          _triggerOsd();
        }
      },
      child: Stack(
        children: [
          // 1. FULL BACKGROUND VIDEO PLAYER (when not in floating PiP mode)
          if (!isFloatingPip) Positioned.fill(child: playerWidget),
          // 1.1 TRANSPARENT GESTURE DETECTOR ON TOP OF VIDEO
          if (!isFloatingPip && !tvState.isEpgOverlayVisible && tvState.isPlaying)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  _triggerOsd();
                },
                onDoubleTap: () => _toggleFullscreenOrientation(tvState),
              ),
            ),

          // 2. OVERLAY HUD & TV GUIDE
          if (tvState.isEpgOverlayVisible) ...[
            Positioned.fill(
              child: isFloatingPip
                  ? Container(color: const Color(0xFF0C0E14))
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.88),
                            Colors.black.withValues(alpha: 0.72),
                            Colors.black.withValues(alpha: 0.92),
                          ],
                        ),
                      ),
                    ),
            ),

            // Main Application Layout
            SafeArea(
              child: Column(
                children: [
                  // TOP BAR (Responsive for Mobile and Desktop)
                  _buildTopBar(context, tvState, isMobile),

                  const Divider(color: TvTheme.borderSubtle, height: 1),

                  // VIEW MODE: QUICK OVERLAY vs FULL EPG GRID vs BOTTOM SCROLL LIST
                  Expanded(
                    child: tvState.viewMode == TvViewMode.epgGrid
                        ? EpgGridView(tvState: tvState)
                        : tvState.viewMode == TvViewMode.bottomScrollList
                        ? Column(
                            children: [
                              const Spacer(),
                              BottomChannelScrollListWidget(
                                tvState: tvState,
                                isStandalone: true,
                              ),
                            ],
                          )
                        : isTablet
                        ? Column(
                            children: [
                              // Tablet Category Chips Row
                              _buildMobileCategoriesRow(context, tvState),

                              const Divider(
                                color: TvTheme.borderSubtle,
                                height: 1,
                              ),

                              Expanded(
                                child: Row(
                                  children: [
                                    // Channels Column
                                    _buildChannelsColumn(
                                      context,
                                      tvState,
                                      width: 330,
                                      isMobile: false,
                                    ),

                                    const VerticalDivider(
                                      color: TvTheme.borderSubtle,
                                      width: 1,
                                    ),

                                    // EPG Details & Schedule
                                    Expanded(
                                      child: EpgDetailPanel(
                                        channel: tvState.selectedChannel,
                                        currentProgram: tvState.currentProgram,
                                        upcomingPrograms:
                                            tvState.upcomingPrograms,
                                        onToggleFavorite: () {
                                          if (tvState.selectedChannel != null) {
                                            tvState.toggleFavorite(
                                              tvState.selectedChannel!,
                                            );
                                          }
                                        },
                                        onToggleFullscreen: () =>
                                            _enterFullscreenLandscape(tvState),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              // Col 1: Groups / Categories
                              _buildGroupsColumn(context, tvState),

                              const VerticalDivider(
                                color: TvTheme.borderSubtle,
                                width: 1,
                              ),

                              // Col 2: Channel List
                              _buildChannelsColumn(
                                context,
                                tvState,
                                width: 360,
                                isMobile: false,
                              ),

                              // Col 3: EPG Details & Schedule
                              Expanded(
                                child: EpgDetailPanel(
                                  channel: tvState.selectedChannel,
                                  currentProgram: tvState.currentProgram,
                                  upcomingPrograms: tvState.upcomingPrograms,
                                  onToggleFavorite: () {
                                    if (tvState.selectedChannel != null) {
                                      tvState.toggleFavorite(
                                        tvState.selectedChannel!,
                                      );
                                    }
                                  },
                                  onToggleFullscreen: () =>
                                      _enterFullscreenLandscape(tvState),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],

          // 3. FLOATING PiP WINDOW (when browsing guide in PiP mode)
          if (isFloatingPip)
            _buildFloatingPipCard(
              context,
              tvState,
              playerWidget,
              isMobile,
              size,
            ),

          // 4. BOTTOM CHANNEL SCROLL LIST OVERLAY
          if (tvState.showBottomChannelList)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomChannelScrollListWidget(
                tvState: tvState,
                onClose: () => tvState.setBottomChannelList(false),
              ),
            ),

          // 5. ON-SCREEN DISPLAY (OSD) IN FULLSCREEN MODE
          if (!tvState.isEpgOverlayVisible &&
              _showOsdInFullscreen &&
              !tvState.showBottomChannelList)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PlayerControlsOsd(
                channel: tvState.activePlayingChannel,
                currentProgram: tvState.currentProgram,
                tvState: tvState,
                onOpenGuide: () => _exitFullscreenPortrait(tvState),
              ),
            ),

          // 6. MINIMAL QUICK GUIDE & CHANNELS BUTTON WHEN IN FULLSCREEN
          // if (!tvState.isEpgOverlayVisible &&
          //     !_showOsdInFullscreen &&
          //     !tvState.showBottomChannelList)
          //   Positioned(
          //     top: isMobile ? 12 : 24,
          //     left: isMobile ? 12 : 24,
          //     child: SafeArea(
          //       child: Row(
          //         mainAxisSize: MainAxisSize.min,
          //         children: [
          //           InkWell(
          //             onTap: () {
          //               _exitFullscreenPortrait(tvState);
          //             },
          //             child: Container(
          //               padding: EdgeInsets.symmetric(
          //                 horizontal: isMobile ? 10 : 14,
          //                 vertical: isMobile ? 6 : 8,
          //               ),
          //               decoration: BoxDecoration(
          //                 color: Colors.black.withValues(alpha: 0.2),
          //                 borderRadius: BorderRadius.circular(20),
          //                 border: Border.all(color: Colors.white24, width: 1),
          //               ),
          //               child: Row(
          //                 mainAxisSize: MainAxisSize.min,
          //                 children: [
          //                   Icon(
          //                     isMobile
          //                         ? Icons.arrow_back_rounded
          //                         : Icons.menu_rounded,
          //                     size: 18,
          //                     color: Colors.white,
          //                   ),
          //                 ],
          //               ),
          //             ),
          //           ),
          //           const SizedBox(width: 8),
          //           InkWell(
          //             onTap: () => tvState.toggleBottomChannelList(),
          //             child: Container(
          //               padding: EdgeInsets.symmetric(
          //                 horizontal: isMobile ? 10 : 14,
          //                 vertical: isMobile ? 6 : 8,
          //               ),
          //               decoration: BoxDecoration(
          //                 color: Colors.black.withValues(alpha: 0.2),
          //                 borderRadius: BorderRadius.circular(20),
          //                 border: Border.all(
          //                   color: tvState.showBottomChannelList
          //                       ? TvTheme.primaryAccent
          //                       : Colors.white24,
          //                   width: 1,
          //                 ),
          //               ),
          //               child: Row(
          //                 mainAxisSize: MainAxisSize.min,
          //                 children: [
          //                   Icon(
          //                     Icons.view_carousel_rounded,
          //                     size: 18,
          //                     color: tvState.showBottomChannelList
          //                         ? TvTheme.primaryAccent
          //                         : Colors.white,
          //                   ),
          //                 ],
          //               ),
          //             ),
          //           ),
          //           InkWell(
          //             onTap: () => {},
          //             child: Container(
          //               padding: EdgeInsets.symmetric(
          //                 horizontal: isMobile ? 10 : 14,
          //                 vertical: isMobile ? 6 : 8,
          //               ),
          //               decoration: BoxDecoration(
          //                 color: Colors.black.withValues(alpha: 0.2),
          //                 borderRadius: BorderRadius.circular(20),
          //                 border: Border.all(
          //                   color: tvState.showBottomChannelList
          //                       ? TvTheme.primaryAccent
          //                       : Colors.white24,
          //                   width: 1,
          //                 ),
          //               ),
          //               child: Icon(Icons.aspect_ratio_outlined, size: 18),
          //             ),
          //           ),
          //         ],
          //       ),
          //     ),
          //   ),
        ],
      ),
    );
  }

  Widget _buildFloatingPipCard(
    BuildContext context,
    TvStateProvider tvState,
    Widget playerWidget,
    bool isMobile,
    Size size,
  ) {
    final channel = tvState.activePlayingChannel;
    final pipWidth = isMobile ? (size.width * 0.58).clamp(180.0, 260.0) : 360.0;
    final pipHeight = pipWidth * 9 / 16;
    final pipRight = isMobile ? 12.0 : 24.0;
    final pipBottom = isMobile ? 16.0 : 24.0;

    return Positioned(
      bottom: pipBottom,
      right: pipRight,
      width: pipWidth,
      height: pipHeight,
      child: GestureDetector(
        onDoubleTap: () {
          tvState.setPipMode(false);
          _enterFullscreenLandscape(tvState);
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: TvTheme.primaryAccent.withValues(alpha: 0.8),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.85),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: playerWidget),

              // Overlay Top Bar with Channel name & Quick PiP controls
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: TvTheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PiP',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          channel != null
                              ? '#${channel.channelNumber} ${channel.name}'
                              : 'Live Playback',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: tvState.isMuted ? 'Unmute' : 'Mute',
                        icon: Icon(
                          tvState.isMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: tvState.isMuted
                              ? Colors.redAccent
                              : Colors.white,
                          size: 16,
                        ),
                        onPressed: () => tvState.toggleMute(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Expand Fullscreen',
                        icon: const Icon(
                          Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        onPressed: () {
                          tvState.setPipMode(false);
                          _enterFullscreenLandscape(tvState);
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Exit PiP (Return to Background)',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 16,
                        ),
                        onPressed: () => tvState.setPipMode(false),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    TvStateProvider tvState,
    bool isMobile,
  ) {
    if (isMobile || MediaQuery.sizeOf(context).width < 950) {
      return _buildMobileTopBar(context, tvState);
    }
    return _buildDesktopTopBar(context, tvState);
  }

  Widget _buildMobileTopBar(BuildContext context, TvStateProvider tvState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Active Playlist display / quick tap
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => const PlaylistManagerDialog(),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: TvTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: TvTheme.borderSubtle),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tvState.isEpgSyncing)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: TvTheme.primaryAccent,
                              ),
                            ),
                          )
                        else
                          const Icon(
                            Icons.playlist_play_rounded,
                            size: 16,
                            color: TvTheme.primaryAccent,
                          ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            tvState.selectedPlaylist?.name ?? 'Playlists',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 16,
                          color: TvTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 6),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ignore logo
                  // Container(
                  //   padding: const EdgeInsets.all(5),
                  //   decoration: BoxDecoration(
                  //     color: TvTheme.primary,
                  //     borderRadius: BorderRadius.circular(8),
                  //   ),
                  //   child: const Icon(
                  //     Icons.live_tv_rounded,
                  //     color: Colors.white,
                  //     size: 18,
                  //   ),
                  // ),
                  // const SizedBox(width: 2),
                  // Search Toggle Icon
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: Icon(
                      _isMobileSearchOpen
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      size: 20,
                      color:
                          _isMobileSearchOpen ||
                              _searchController.text.isNotEmpty
                          ? TvTheme.primaryAccent
                          : Colors.white70,
                    ),
                    tooltip: 'Search',
                    onPressed: () {
                      setState(() {
                        _isMobileSearchOpen = !_isMobileSearchOpen;
                        if (!_isMobileSearchOpen &&
                            _searchController.text.isNotEmpty) {
                          _searchController.clear();
                          tvState.setSearchQuery('');
                        }
                      });
                    },
                  ),

                  // View Mode Toggle (List vs Grid vs Bottom Scroll List)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: Icon(
                      tvState.viewMode == TvViewMode.bottomScrollList
                          ? Icons.view_carousel_rounded
                          : tvState.viewMode == TvViewMode.epgGrid
                          ? Icons.view_list_rounded
                          : Icons.grid_view_rounded,
                      size: 20,
                      color: tvState.viewMode == TvViewMode.bottomScrollList
                          ? TvTheme.primaryAccent
                          : Colors.white70,
                    ),
                    tooltip: tvState.viewMode == TvViewMode.bottomScrollList
                        ? 'Bottom Scroll List'
                        : tvState.viewMode == TvViewMode.epgGrid
                        ? 'List View'
                        : 'EPG Grid',
                    onPressed: () => tvState.cycleViewMode(),
                  ),

                  // Bottom Channel Scroll List Toggle
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: Icon(
                      tvState.showBottomChannelList
                          ? Icons.view_carousel_rounded
                          : Icons.view_carousel_outlined,
                      size: 20,
                      color: tvState.showBottomChannelList
                          ? TvTheme.primaryAccent
                          : Colors.white70,
                    ),
                    tooltip: 'Bottom Channel Scroll List',
                    onPressed: () => tvState.toggleBottomChannelList(),
                  ),

                  // Fullscreen Video Toggle
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: const Icon(
                      Icons.fullscreen_rounded,
                      size: 22,
                      color: Colors.white,
                    ),
                    tooltip: 'Fullscreen Video',
                    onPressed: () => _enterFullscreenLandscape(tvState),
                  ),

                  // More Options Menu
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: Colors.white70,
                    ),
                    color: TvTheme.surfaceElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (val) {
                      switch (val) {
                        case 'recordings':
                          showDialog(
                            context: context,
                            builder: (_) => const RecordingsScreen(),
                          );
                          break;
                        case 'settings':
                          showDialog(
                            context: context,
                            builder: (_) => const StreamSettingsDialog(),
                          );
                          break;
                        case 'pip':
                          tvState.enterSystemPip(context: context);
                          break;
                        case 'playlists':
                          showDialog(
                            context: context,
                            builder: (_) => const PlaylistManagerDialog(),
                          );
                          break;
                        case 'bottom_channels':
                          tvState.toggleBottomChannelList();
                          break;
                        case 'fullscreen':
                          _toggleFullscreenOrientation(tvState);
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'recordings',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.fiber_smart_record_rounded,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tvState.isCurrentChannelRecording
                                  ? 'Recordings (1 REC)'
                                  : 'DVR & Recordings',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'pip',
                        child: Row(
                          children: [
                            Icon(
                              tvState.isPipMode
                                  ? Icons.picture_in_picture_alt_rounded
                                  : Icons.picture_in_picture_rounded,
                              size: 18,
                              color: TvTheme.primaryAccent,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tvState.isPipMode
                                  ? 'Background Player'
                                  : 'Picture-in-Picture (PiP)',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'settings',
                        child: Row(
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: Colors.white70,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Stream Settings',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'playlists',
                        child: Row(
                          children: [
                            Icon(
                              Icons.playlist_play_rounded,
                              size: 18,
                              color: TvTheme.primaryAccent,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Manage Playlists...',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'bottom_channels',
                        child: Row(
                          children: [
                            const Icon(
                              Icons.view_carousel_rounded,
                              size: 18,
                              color: TvTheme.primaryAccent,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              tvState.showBottomChannelList
                                  ? 'Hide Bottom Channel Bar'
                                  : 'Show Bottom Channel Bar',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'fullscreen',
                        child: Row(
                          children: [
                            Icon(
                              Icons.fullscreen_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Hide Guide (Fullscreen)',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Collapsible Mobile Search Field
        if (_isMobileSearchOpen || _searchController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchController,
                autofocus: _isMobileSearchOpen,
                onChanged: (val) => tvState.setSearchQuery(val),
                decoration: InputDecoration(
                  hintText: 'Search channels or genres...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: TvTheme.textMuted,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: TvTheme.textMuted,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      tvState.setSearchQuery('');
                      setState(() => _isMobileSearchOpen = false);
                    },
                  ),
                  filled: true,
                  fillColor: TvTheme.surfaceElevated,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDesktopTopBar(BuildContext context, TvStateProvider tvState) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          // Brand Logo & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: TvTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.live_tv_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'TiviPlayer',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),

          const SizedBox(width: 28),

          // Search Bar
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => tvState.setSearchQuery(val),
                decoration: InputDecoration(
                  hintText: 'Search channels or genres...',
                  hintStyle: const TextStyle(
                    fontSize: 13,
                    color: TvTheme.textMuted,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: TvTheme.textMuted,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            tvState.setSearchQuery('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: TvTheme.surfaceElevated.withValues(alpha: 0.8),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 20),

          // Mode Selector: List vs EPG Grid
          SegmentedButton<TvViewMode>(
            segments: const [
              ButtonSegment(
                value: TvViewMode.quickOverlay,
                icon: Icon(Icons.view_list_rounded, size: 18),
                label: Text('List View', style: TextStyle(fontSize: 12)),
              ),
              ButtonSegment(
                value: TvViewMode.epgGrid,
                icon: Icon(Icons.grid_view_rounded, size: 18),
                label: Text('EPG Grid', style: TextStyle(fontSize: 12)),
              ),
            ],
            selected: {tvState.viewMode},
            onSelectionChanged: (newVal) {
              tvState.setViewMode(newVal.first);
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return TvTheme.primary;
                }
                return TvTheme.surfaceElevated;
              }),
            ),
          ),

          const SizedBox(width: 14),

          // Favorites Toggle
          FilterChip(
            selected: tvState.isFavoritesOnly,
            onSelected: (_) => tvState.toggleFavoritesFilter(),
            label: const Text('Favorites'),
            avatar: Icon(
              tvState.isFavoritesOnly
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: 18,
              color: tvState.isFavoritesOnly
                  ? TvTheme.accentGold
                  : TvTheme.textMuted,
            ),
            backgroundColor: Colors.transparent,
            selectedColor: TvTheme.accentGold.withValues(alpha: 0.2),
            labelStyle: TextStyle(
              color: tvState.isFavoritesOnly
                  ? TvTheme.accentGold
                  : TvTheme.textBright,
              fontSize: 12,
            ),
          ),

          const SizedBox(width: 12),

          // Active Playlist Display & Quick Switcher
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const PlaylistManagerDialog(),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: TvTheme.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tvState.isEpgSyncing)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: TvTheme.primaryAccent,
                        ),
                      ),
                    )
                  else
                    const Icon(
                      Icons.playlist_play_rounded,
                      size: 20,
                      color: TvTheme.primaryAccent,
                    ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // const Text(
                        //   'PLAYLIST',
                        //   style: TextStyle(
                        //     fontSize: 9,
                        //     fontWeight: FontWeight.bold,
                        //     letterSpacing: 0.8,
                        //     color: TvTheme.textMuted,
                        //   ),
                        // ),
                        Text(
                          tvState.selectedPlaylist?.name ?? 'Playlists',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (tvState.playlists.length > 1)
                    PopupMenuButton<Playlist?>(
                      tooltip: 'Switch Playlist',
                      icon: const Icon(
                        Icons.arrow_drop_down_rounded,
                        color: TvTheme.primaryAccent,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: TvTheme.surfaceElevated,
                      onSelected: (p) async {
                        if (p != null) {
                          await tvState.switchPlaylist(p);
                          if (context.mounted) {
                            TvToast.success(context, 'Switched to "${p.name}"');
                          }
                        }
                      },
                      itemBuilder: (context) => [
                        ...tvState.playlists.map(
                          (p) => PopupMenuItem<Playlist?>(
                            value: p,
                            child: Row(
                              children: [
                                Icon(
                                  tvState.selectedPlaylist?.id == p.id
                                      ? Icons.check_circle_rounded
                                      : Icons.playlist_play_rounded,
                                  size: 16,
                                  color: tvState.selectedPlaylist?.id == p.id
                                      ? const Color(0xFF10B981)
                                      : TvTheme.textMuted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: TextStyle(
                                      fontWeight:
                                          tvState.selectedPlaylist?.id == p.id
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color:
                                          tvState.selectedPlaylist?.id == p.id
                                          ? Colors.white
                                          : TvTheme.textBright,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${p.channelCount} ch',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: TvTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          onTap: () {
                            Future.delayed(Duration.zero, () {
                              if (context.mounted) {
                                showDialog(
                                  context: context,
                                  builder: (_) => const PlaylistManagerDialog(),
                                );
                              }
                            });
                          },
                          child: const Row(
                            children: [
                              Icon(
                                Icons.settings_rounded,
                                size: 16,
                                color: TvTheme.primaryAccent,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Manage Playlists...',
                                style: TextStyle(
                                  color: TvTheme.primaryAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else
                    const Icon(
                      Icons.tune_rounded,
                      size: 14,
                      color: TvTheme.textMuted,
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Recordings Screen
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: TvTheme.surfaceElevated,
              foregroundColor: TvTheme.textBright,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const RecordingsScreen(),
              );
            },
            icon: const Icon(
              Icons.fiber_smart_record_rounded,
              size: 18,
              color: Colors.redAccent,
            ),
            label: const Text('Recordings (R)', style: TextStyle(fontSize: 13)),
          ),

          const SizedBox(width: 8),

          // Picture-in-Picture Toggle
          IconButton(
            tooltip: 'Picture-in-Picture (P)',
            icon: Icon(
              tvState.isPipMode
                  ? Icons.picture_in_picture_alt_rounded
                  : Icons.picture_in_picture_rounded,
              color: tvState.isPipMode ? TvTheme.primaryAccent : Colors.white,
              size: 24,
            ),
            onPressed: () => tvState.enterSystemPip(context: context),
          ),

          // Stream & Video Settings
          IconButton(
            tooltip: 'Video Quality & Stream Settings (S/O)',
            icon: const Icon(Icons.tune_rounded, color: Colors.white, size: 24),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const StreamSettingsDialog(initialTabIndex: 0),
              );
            },
          ),

          const SizedBox(width: 4),

          // Fullscreen Toggle button
          IconButton(
            tooltip: 'Fullscreen (F)',
            icon: const Icon(
              Icons.fullscreen_rounded,
              color: Colors.white,
              size: 26,
            ),
            onPressed: () => _toggleFullscreenOrientation(tvState),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsColumn(BuildContext context, TvStateProvider tvState) {
    return SizedBox(
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'CATEGORIES',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: TvTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _groupsScrollController,
              itemCount: tvState.groups.length,
              itemBuilder: (context, index) {
                final group = tvState.groups[index];
                final isSelected =
                    !tvState.isFavoritesOnly &&
                    tvState.selectedGroup?.id == group.id;

                return ListTile(
                  dense: true,
                  selected: isSelected,
                  selectedTileColor: TvTheme.primary.withValues(alpha: 0.2),
                  leading: Icon(
                    Icons.folder_rounded,
                    size: 18,
                    color: isSelected
                        ? TvTheme.primaryAccent
                        : TvTheme.textMuted,
                  ),
                  title: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? TvTheme.textBright : Colors.white70,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: TvTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${group.channelCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: TvTheme.textMuted,
                      ),
                    ),
                  ),
                  onTap: () => tvState.selectGroup(group),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCategoriesRow(
    BuildContext context,
    TvStateProvider tvState,
  ) {
    if (tvState.groups.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 48,
      color: Colors.black.withValues(alpha: 0.25),
      child: ListView.separated(
        controller: _mobileCategoriesScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: tvState.groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = tvState.groups[index];
          final isSelected =
              !tvState.isFavoritesOnly && tvState.selectedGroup?.id == group.id;

          return ChoiceChip(
            selected: isSelected,
            onSelected: (_) => tvState.selectGroup(group),
            backgroundColor: Colors.transparent,
            selectedColor: TvTheme.primary,
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : TvTheme.textBright,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white24 : Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${group.channelCount}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : TvTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected
                    ? TvTheme.primaryAccent
                    : TvTheme.borderSubtle,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showChannelEpgSheet(
    BuildContext context,
    Channel channel,
    TvStateProvider tvState,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.sizeOf(context).height * 0.78,
        decoration: BoxDecoration(
          color: TvTheme.surfaceElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: TvTheme.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Expanded(
              child: EpgDetailPanel(
                channel: channel,
                currentProgram: tvState.selectedChannel?.id == channel.id
                    ? tvState.currentProgram
                    : null,
                upcomingPrograms: tvState.selectedChannel?.id == channel.id
                    ? tvState.upcomingPrograms
                    : const [],
                onToggleFavorite: () => tvState.toggleFavorite(channel),
                onToggleFullscreen: () {
                  Navigator.of(ctx).pop();
                  tvState.playChannel(channel);
                  _enterFullscreenLandscape(tvState);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelsColumn(
    BuildContext context,
    TvStateProvider tvState, {
    double? width,
    bool isMobile = false,
  }) {
    Widget content;
    if (tvState.isLoading) {
      content = const Center(
        child: CircularProgressIndicator(color: TvTheme.primary),
      );
    } else if (tvState.channels.isEmpty) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 48,
              color: TvTheme.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'No channels found',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: TvTheme.textMuted),
            ),
          ],
        ),
      );
    } else {
      content = ListView.builder(
        controller: _channelsScrollController,
        key: const PageStorageKey('my_list_view'),
        itemCount: tvState.channels.length,
        itemBuilder: (context, index) {
          final channel = tvState.channels[index];
          final isSelected = tvState.selectedChannel?.id == channel.id;
          final isPlaying = tvState.activePlayingChannel?.id == channel.id;
          final liveProgram = isSelected
              ? (tvState.currentProgram ??
                    tvState.getLiveProgramForChannel(channel))
              : tvState.getLiveProgramForChannel(channel);

          return ChannelTileWidget(
            channel: channel,
            currentProgram: liveProgram,
            isSelected: isSelected,
            isPlaying: isPlaying,
            onTap: () async {
              tvState.playChannel(channel);
              if (!isMobile) {
                await Future.delayed(const Duration(milliseconds: 300));
                tvState.toggleEpgOverlay();
              }
            },
            onToggleFavorite: () => tvState.toggleFavorite(channel),
            onInfoTap: isMobile
                ? () {
                    tvState.selectChannel(channel);
                    _showChannelEpgSheet(context, channel, tvState);
                  }
                : null,
          );
        },
      );
    }

    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return content;
  }
}
