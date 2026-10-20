import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import '../../providers/tv_state_provider.dart';
import '../../ui/theme.dart';

class StreamSettingsDialog extends StatefulWidget {
  final int initialTabIndex;

  const StreamSettingsDialog({super.key, this.initialTabIndex = 0});

  @override
  State<StreamSettingsDialog> createState() => _StreamSettingsDialogState();
}

class _StreamSettingsDialogState extends State<StreamSettingsDialog> {
  late int _selectedTabIndex;
  StreamSubscription? _tracksSubscription;
  StreamSubscription? _trackSubscription;
  StreamSubscription? _videoParamsSubscription;

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = context.read<TvStateProvider>().activePlayer;
      if (player != null) {
        _tracksSubscription = player.stream.tracks.listen((_) {
          if (mounted) setState(() {});
        });
        _trackSubscription = player.stream.track.listen((_) {
          if (mounted) setState(() {});
        });
        _videoParamsSubscription = player.stream.videoParams.listen((_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  @override
  void dispose() {
    _tracksSubscription?.cancel();
    _trackSubscription?.cancel();
    _videoParamsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvState = context.watch<TvStateProvider>();
    final player = tvState.activePlayer;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 40,
        vertical: isMobile ? 20 : 30,
      ),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: math.min(size.height - 32, 560),
        ),
        decoration: BoxDecoration(
          color: TvTheme.surfaceElevated.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TvTheme.borderSubtle, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 24,
                vertical: isMobile ? 12 : 16,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: TvTheme.borderSubtle)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: TvTheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      color: TvTheme.primaryAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stream & Playback Settings',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isMobile ? 16 : 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tvState.activePlayingChannel?.name ?? 'Live Stream',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: TvTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                    tooltip: 'Close (ESC)',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab Navigation Row (horizontally scrollable on mobile)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.black.withValues(alpha: 0.2),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabButton(
                      0,
                      'Video Quality',
                      Icons.high_quality_rounded,
                    ),
                    const SizedBox(width: 8),
                    _buildTabButton(
                      1,
                      'Aspect Ratio',
                      Icons.aspect_ratio_rounded,
                    ),
                    const SizedBox(width: 8),
                    _buildTabButton(
                      2,
                      'Audio Tracks',
                      Icons.audiotrack_rounded,
                    ),
                    const SizedBox(width: 8),
                    _buildTabButton(3, 'Subtitles', Icons.subtitles_rounded),
                    const SizedBox(width: 8),
                    _buildTabButton(4, 'Buffer & Speed', Icons.speed_rounded),
                  ],
                ),
              ),
            ),

            const Divider(color: TvTheme.borderSubtle, height: 1),

            // Tab Content Body
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isMobile ? 14 : 24),
                child: _buildTabContent(tvState, player),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? TvTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : TvTheme.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(TvStateProvider tvState, Player? player) {
    switch (_selectedTabIndex) {
      case 0:
        return _buildVideoQualityTab(tvState, player);
      case 1:
        return _buildAspectRatioTab(tvState);
      case 2:
        return _buildAudioTracksTab(player);
      case 3:
        return _buildSubtitlesTab(player);
      case 4:
        return _buildBufferAndSpeedTab(tvState, player);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildVideoQualityTab(TvStateProvider tvState, Player? player) {
    if (player == null) {
      return const Center(
        child: Text(
          'Player inactive or stream not started.',
          style: TextStyle(color: TvTheme.textMuted),
        ),
      );
    }

    final currentTrack = player.state.track.video;
    final allTracks = player.state.tracks.video;

    int? width = player.state.width ?? player.state.videoParams.w;
    int? height = player.state.height ?? player.state.videoParams.h;
    if ((width == null || width == 0) && currentTrack.w != null) {
      width = currentTrack.w;
    }
    if ((height == null || height == 0) && currentTrack.h != null) {
      height = currentTrack.h;
    }

    final double? fps = currentTrack.fps;
    final int? bitrate = currentTrack.bitrate;
    final String? codec = currentTrack.codec;
    final String? pixelformat = player.state.videoParams.pixelformat;
    final bool isAuto = currentTrack.id == 'auto';

    // Filter available manual renditions (excluding 'no' and 'auto')
    final variants = allTracks
        .where((t) => t.id != 'no' && t.id != 'auto')
        .toList();
    variants.sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));

    // Determine badge and color
    String badgeText = 'Live Stream';
    Color badgeColor = TvTheme.primary;
    if (height != null) {
      if (height >= 2160) {
        badgeText = '4K Ultra HD';
        badgeColor = const Color(0xFF9C27B0);
      } else if (height >= 1440) {
        badgeText = '2K QHD';
        badgeColor = const Color(0xFF3F51B5);
      } else if (height >= 1080) {
        badgeText = '1080p Full HD';
        badgeColor = const Color(0xFF00ACC1);
      } else if (height >= 720) {
        badgeText = '720p HD';
        badgeColor = const Color(0xFF43A047);
      } else if (height >= 480) {
        badgeText = '480p SD';
        badgeColor = const Color(0xFFFFA000);
      } else if (height > 0) {
        badgeText = '${height}p SD';
        badgeColor = Colors.blueGrey;
      }
    }

    return ListView(
      children: [
        // Live Stream Parameters Header Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                TvTheme.primary.withValues(alpha: 0.22),
                TvTheme.surfaceFocus.withValues(alpha: 0.35),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: TvTheme.primary.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: badgeColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          badgeText,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isAuto
                          ? Colors.greenAccent.withValues(alpha: 0.15)
                          : Colors.amberAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isAuto
                            ? Colors.greenAccent.withValues(alpha: 0.6)
                            : Colors.amberAccent.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      isAuto ? 'AUTO ADAPTIVE' : 'MANUAL LOCK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isAuto ? Colors.greenAccent : Colors.amberAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    width != null && height != null
                        ? '$width × $height'
                        : 'Demuxing Stream...',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildSpecChip(
                    Icons.aspect_ratio_rounded,
                    'Resolution',
                    width != null && height != null
                        ? '$width × $height'
                        : 'Demuxing',
                  ),
                  if (fps != null && fps > 0)
                    _buildSpecChip(
                      Icons.speed_rounded,
                      'Frame Rate',
                      '${fps.toStringAsFixed(0)} FPS',
                    ),
                  if (codec != null && codec.isNotEmpty)
                    _buildSpecChip(
                      Icons.memory_rounded,
                      'Codec',
                      codec.toUpperCase(),
                    ),
                  if (bitrate != null && bitrate > 0)
                    _buildSpecChip(
                      Icons.network_check_rounded,
                      'Bitrate',
                      _formatBitrate(bitrate),
                    ),
                  if (pixelformat != null && pixelformat.isNotEmpty)
                    _buildSpecChip(
                      Icons.color_lens_rounded,
                      'Pixel Format',
                      pixelformat,
                    ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),
        const Text(
          'SELECT VIDEO STREAM QUALITY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: TvTheme.textMuted,
          ),
        ),
        const SizedBox(height: 12),

        // 1. Auto (Adaptive Bitrate)
        _buildQualityOption(
          isSelected: isAuto,
          title: 'Auto (Adaptive Bitrate)',
          subtitle: width != null && height != null
              ? 'Currently streaming at ${height}p ($width × $height). Dynamically scales with network speed.'
              : 'Dynamically adapts resolution to match your network bandwidth.',
          badge: 'RECOMMENDED',
          badgeColor: Colors.greenAccent,
          icon: Icons.auto_mode_rounded,
          onTap: () async {
            await player.setVideoTrack(VideoTrack.auto());
            if (mounted) setState(() {});
          },
        ),

        // 2. Specific Video Renditions (if provided by master manifest / demuxer)
        if (variants.isNotEmpty) ...[
          ...variants.map((t) {
            final isSelected = !isAuto && currentTrack.id == t.id;
            final String tierName;
            if (t.h != null) {
              final fpsSuffix = (t.fps != null && t.fps! >= 50) ? '60' : '';
              if (t.h! >= 2160) {
                tierName = '4K Ultra HD (${t.h}p$fpsSuffix)';
              } else if (t.h! >= 1080) {
                tierName = 'Full HD (${t.h}p$fpsSuffix)';
              } else if (t.h! >= 720) {
                tierName = 'High Definition (${t.h}p$fpsSuffix)';
              } else {
                tierName = 'Standard Definition (${t.h}p)';
              }
            } else {
              tierName = t.title ?? 'Quality Level #${t.id}';
            }

            final details = [
              if (t.w != null && t.h != null) '${t.w} × ${t.h}',
              if (t.fps != null && t.fps! > 0) '${t.fps!.round()} fps',
              if (t.bitrate != null && t.bitrate! > 0)
                _formatBitrate(t.bitrate!),
              if (t.codec != null && t.codec!.isNotEmpty)
                t.codec!.toUpperCase(),
            ].join(' • ');

            return _buildQualityOption(
              isSelected: isSelected,
              title: tierName,
              subtitle: details.isNotEmpty
                  ? details
                  : 'Stream Rendition #${t.id}',
              badge: t.h != null ? '${t.h}p' : 'Track ${t.id}',
              badgeColor: TvTheme.primaryAccent,
              icon: Icons.hd_rounded,
              onTap: () async {
                await player.setVideoTrack(t);
                if (mounted) setState(() {});
              },
            );
          }),
        ] else ...[
          // Single-quality direct stream fallback explanation card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: TvTheme.borderSubtle),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: TvTheme.primaryAccent,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Direct Broadcast Source Quality',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        width != null && height != null
                            ? 'This channel is transmitted at a native source resolution of $width × $height. The broadcaster delivers this feed directly without sub-bitrate renditions.'
                            : 'This stream is delivered directly from the broadcaster feed at native source quality.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: TvTheme.textMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(
                                color: TvTheme.borderSubtle,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onPressed: () =>
                                setState(() => _selectedTabIndex = 1),
                            icon: const Icon(
                              Icons.aspect_ratio_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              'Aspect Ratio',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(
                                color: TvTheme.borderSubtle,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onPressed: () =>
                                setState(() => _selectedTabIndex = 4),
                            icon: const Icon(Icons.speed_rounded, size: 16),
                            label: const Text(
                              'Buffer Cache',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQualityOption({
    required bool isSelected,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? TvTheme.primary.withValues(alpha: 0.18)
            : Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? TvTheme.primaryAccent : TvTheme.borderSubtle,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          leading: Icon(
            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: isSelected ? TvTheme.primaryAccent : Colors.white54,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.white70,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: TvTheme.textMuted),
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _buildSpecChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: TvTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: TvTheme.textMuted),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 11, color: TvTheme.textMuted),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBitrate(int bitrate) {
    if (bitrate >= 1000000) {
      return '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
    } else if (bitrate >= 1000) {
      return '${(bitrate / 1000).round()} kbps';
    }
    return '$bitrate bps';
  }

  Widget _buildAspectRatioTab(TvStateProvider tvState) {
    final modes = [
      {
        'mode': VideoScaleMode.contain,
        'title': 'Contain (Original)',
        'desc':
            'Preserves native broadcast aspect ratio with black bars if necessary.',
      },
      {
        'mode': VideoScaleMode.cover,
        'title': 'Cover / Fill (16:9)',
        'desc': 'Stretches and fills entire screen without black borders.',
      },
      {
        'mode': VideoScaleMode.fitWidth,
        'title': 'Fit Width',
        'desc': 'Fits the video horizontally to the display width.',
      },
      {
        'mode': VideoScaleMode.fitHeight,
        'title': 'Fit Height',
        'desc': 'Fits the video vertically to the display height.',
      },
      {
        'mode': VideoScaleMode.fourThree,
        'title': 'Force 4:3 (Classic TV)',
        'desc': 'Forces vintage 4:3 SD broadcast aspect ratio.',
      },
      {
        'mode': VideoScaleMode.sixteenNine,
        'title': 'Force 16:9 (Widescreen)',
        'desc': 'Forces standard widescreen 16:9 framing.',
      },
    ];

    return ListView(
      children: [
        const Text(
          'SELECT DISPLAY FRAMING',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: TvTheme.textMuted,
          ),
        ),
        const SizedBox(height: 14),
        ...modes.map((item) {
          final mode = item['mode'] as VideoScaleMode;
          final isSelected = tvState.scaleMode == mode;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? TvTheme.primary.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? TvTheme.primary : TvTheme.borderSubtle,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: isSelected ? TvTheme.primaryAccent : Colors.white54,
                ),
                title: Text(
                  item['title'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.white70,
                  ),
                ),
                subtitle: Text(
                  item['desc'] as String,
                  style: const TextStyle(
                    fontSize: 12,
                    color: TvTheme.textMuted,
                  ),
                ),
                onTap: () {
                  tvState.setScaleMode(mode);
                },
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAudioTracksTab(Player? player) {
    if (player == null) {
      return const Center(
        child: Text(
          'Player not active',
          style: TextStyle(color: TvTheme.textMuted),
        ),
      );
    }

    final tracks = player.state.tracks.audio;
    final currentTrack = player.state.track.audio;

    return ListView(
      children: [
        const Text(
          'AVAILABLE AUDIO STREAMS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: TvTheme.textMuted,
          ),
        ),
        const SizedBox(height: 14),
        if (tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No multi-audio tracks detected for this stream. The default stream audio is playing.',
              style: TextStyle(color: TvTheme.textMuted, fontSize: 13),
            ),
          )
        else
          ...tracks.map((t) {
            final isSelected = currentTrack.id == t.id;
            final label = t.title ?? t.language ?? 'Track ${t.id}';
            final desc = [
              if (t.language != null) 'Lang: ${t.language}',
              if (t.codec != null) 'Codec: ${t.codec}',
              if (t.channels != null) '${t.channels} channels',
            ].join(' • ');

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? TvTheme.primary.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? TvTheme.primary : TvTheme.borderSubtle,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.volume_up_rounded
                        : Icons.audiotrack_rounded,
                    color: isSelected ? TvTheme.primaryAccent : Colors.white54,
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  subtitle: Text(
                    desc.isNotEmpty ? desc : 'Audio Stream #${t.id}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: TvTheme.textMuted,
                    ),
                  ),
                  onTap: () async {
                    await player.setAudioTrack(t);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSubtitlesTab(Player? player) {
    if (player == null) {
      return const Center(
        child: Text(
          'Player not active',
          style: TextStyle(color: TvTheme.textMuted),
        ),
      );
    }

    final tracks = player.state.tracks.subtitle;
    final currentTrack = player.state.track.subtitle;

    return ListView(
      children: [
        const Text(
          'SUBTITLES & CLOSED CAPTIONS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: TvTheme.textMuted,
          ),
        ),
        const SizedBox(height: 14),

        // Disable Subtitles Option
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: currentTrack.id == 'no'
                ? TvTheme.primary.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: currentTrack.id == 'no'
                  ? TvTheme.primary
                  : TvTheme.borderSubtle,
              width: currentTrack.id == 'no' ? 1.5 : 1.0,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              leading: Icon(
                currentTrack.id == 'no'
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: currentTrack.id == 'no'
                    ? TvTheme.primaryAccent
                    : Colors.white54,
              ),
              title: const Text(
                'Off (Subtitles Disabled)',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () async {
                await player.setSubtitleTrack(SubtitleTrack.no());
                if (mounted) setState(() {});
              },
            ),
          ),
        ),

        if (tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No embedded subtitle streams detected for this channel.',
              style: TextStyle(color: TvTheme.textMuted, fontSize: 13),
            ),
          )
        else
          ...tracks.map((st) {
            final isSelected = currentTrack.id == st.id;
            final label = st.title ?? st.language ?? 'Subtitle Track ${st.id}';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? TvTheme.primary.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? TvTheme.primary : TvTheme.borderSubtle,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: isSelected ? TvTheme.primaryAccent : Colors.white54,
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  subtitle: Text(
                    st.language != null
                        ? 'Language: ${st.language}'
                        : 'Embedded Subtitle',
                    style: const TextStyle(
                      fontSize: 12,
                      color: TvTheme.textMuted,
                    ),
                  ),
                  onTap: () async {
                    await player.setSubtitleTrack(st);
                    if (mounted) setState(() {});
                  },
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildBufferAndSpeedTab(TvStateProvider tvState, Player? player) {
    final bufferOptions = [
      {'bytes': 8 * 1024 * 1024, 'label': '8 MB (Low Latency / Live Sports)'},
      {
        'bytes': 32 * 1024 * 1024,
        'label': '32 MB (Standard / TiviMate Recommended)',
      },
      {'bytes': 64 * 1024 * 1024, 'label': '64 MB (Large / Anti-Stutter)'},
      {
        'bytes': 128 * 1024 * 1024,
        'label': '128 MB (Maximum Buffer / Slow Networks)',
      },
    ];

    final speedOptions = [0.75, 1.0, 1.25, 1.5, 2.0];

    return ListView(
      children: [
        const Text(
          'PLAYBACK RATE (SPEED)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: TvTheme.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: speedOptions.map((rate) {
            final isSelected = (tvState.playbackRate - rate).abs() < 0.05;
            return ChoiceChip(
              selected: isSelected,
              label: Text('${rate}x${rate == 1.0 ? ' (Normal)' : ''}'),
              selectedColor: TvTheme.primary,
              backgroundColor: Colors.black26,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (_) {
                tvState.setPlaybackRate(rate);
                if (mounted) setState(() {});
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 28),
        const Text(
          'DEMUXER CACHE & BUFFER SIZE (TIVIMATE LOADCONTROL)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: TvTheme.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        ...bufferOptions.map((opt) {
          final bytes = opt['bytes'] as int;
          final isSelected = tvState.bufferSizeBytes == bytes;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? TvTheme.primary.withValues(alpha: 0.15)
                  : Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? TvTheme.primary : TvTheme.borderSubtle,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: isSelected ? TvTheme.primaryAccent : Colors.white54,
                  size: 20,
                ),
                title: Text(
                  opt['label'] as String,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.white70,
                  ),
                ),
                onTap: () {
                  tvState.setBufferSize(bytes);
                  if (mounted) setState(() {});
                },
              ),
            ),
          );
        }),
      ],
    );
  }
}
