import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import '../../models/channel.dart';
import '../../models/epg_program.dart';
import '../../providers/tv_state_provider.dart';
import '../../ui/theme.dart';
import '../screens/stream_settings_dialog.dart';
import 'tv_toast.dart';

class PlayerControlsOsd extends StatefulWidget {
  final Channel? channel;
  final EpgProgram? currentProgram;
  final TvStateProvider tvState;
  final VoidCallback onOpenGuide;

  const PlayerControlsOsd({
    super.key,
    required this.channel,
    required this.currentProgram,
    required this.tvState,
    required this.onOpenGuide,
  });

  @override
  State<PlayerControlsOsd> createState() => _PlayerControlsOsdState();
}

class _PlayerControlsOsdState extends State<PlayerControlsOsd> {
  final FocusNode _scrubberFocusNode = FocusNode();
  bool _isDragging = false;
  double? _dragFraction;
  bool _showRemaining = false;

  @override
  void dispose() {
    _scrubberFocusNode.dispose();
    super.dispose();
  }

  Widget _buildVodProgressBar({required bool isMobile}) {
    final tvState = widget.tvState;
    final duration = tvState.playbackDuration;
    final position = _isDragging && _dragFraction != null
        ? Duration(
            milliseconds: (_dragFraction! * duration.inMilliseconds).round(),
          )
        : tvState.playbackPosition;
    final progress = _isDragging && _dragFraction != null
        ? _dragFraction!
        : tvState.playbackProgressFraction;
    final buffer = tvState.playbackBufferFraction;

    final elapsedStr = TvStateProvider.formatDuration(
      position,
      referenceDuration: duration,
    );
    final totalStr = TvStateProvider.formatDuration(duration);
    final remaining = duration - position;
    final remainingStr =
        '-${TvStateProvider.formatDuration(remaining.isNegative ? Duration.zero : remaining, referenceDuration: duration)}';

    return Focus(
      focusNode: _scrubberFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          tvState.seekRelative(const Duration(seconds: -10));
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          tvState.seekRelative(const Duration(seconds: 10));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 6 : 10,
              vertical: isMobile ? 3 : 5,
            ),
            decoration: BoxDecoration(
              color: isFocused
                  ? TvTheme.surfaceFocus.withValues(alpha: 0.7)
                  : Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: isFocused
                  ? Border.all(color: TvTheme.primaryAccent, width: 2)
                  : Border.all(color: Colors.white12, width: 1),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: TvTheme.primaryAccent.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                if (!isMobile) ...[
                  IconButton(
                    tooltip: 'Rewind 10s (Left Arrow / J)',
                    icon: const Icon(
                      Icons.replay_10_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: () =>
                        tvState.seekRelative(const Duration(seconds: -10)),
                  ),
                  IconButton(
                    tooltip: tvState.isPlaying
                        ? 'Pause (Space / K)'
                        : 'Play (Space / K)',
                    icon: Icon(
                      tvState.isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: tvState.isPlaying
                          ? TvTheme.primaryAccent
                          : Colors.greenAccent,
                      size: 28,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: () => tvState.togglePlayPause(),
                  ),
                  IconButton(
                    tooltip: 'Forward 10s (Right Arrow / L)',
                    icon: const Icon(
                      Icons.forward_10_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    onPressed: () =>
                        tvState.seekRelative(const Duration(seconds: 10)),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
                      final currentIdx = speeds.indexOf(tvState.playbackRate);
                      final nextSpeed =
                          speeds[(currentIdx + 1) % speeds.length];
                      tvState.setPlaybackRate(nextSpeed);
                      TvToast.info(context, 'Speed: ${nextSpeed}x');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: Text(
                        '${tvState.playbackRate}x',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Elapsed time badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    elapsedStr,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 11 : 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Interactive Scrubber Slider
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: isFocused ? 6.0 : (isMobile ? 4.0 : 5.0),
                      activeTrackColor: TvTheme.primaryAccent,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                      secondaryActiveTrackColor: Colors.white.withValues(
                        alpha: 0.42,
                      ),
                      thumbColor: Colors.white,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: isFocused
                            ? 9.0
                            : (isMobile ? 6.0 : 7.5),
                      ),
                      overlayColor: TvTheme.primaryAccent.withValues(
                        alpha: 0.25,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16.0,
                      ),
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      secondaryTrackValue: buffer > 0.0
                          ? buffer.clamp(0.0, 1.0)
                          : null,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (val) {
                        setState(() {
                          _isDragging = true;
                          _dragFraction = val;
                        });
                      },
                      onChangeEnd: (val) {
                        setState(() {
                          _isDragging = false;
                          _dragFraction = null;
                        });
                        if (duration > Duration.zero) {
                          final targetMs = (val * duration.inMilliseconds)
                              .round();
                          tvState.seekTo(Duration(milliseconds: targetMs));
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Total or remaining duration
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    setState(() {
                      _showRemaining = !_showRemaining;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _showRemaining ? remainingStr : totalStr,
                      style: TextStyle(
                        color: _showRemaining
                            ? TvTheme.primaryAccent
                            : Colors.white70,
                        fontSize: isMobile ? 11 : 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final currentProgram = widget.currentProgram;
    final tvState = widget.tvState;
    final onOpenGuide = widget.onOpenGuide;

    if (channel == null) return const SizedBox.shrink();

    final isMobile = MediaQuery.sizeOf(context).width < 700;

    if (isMobile) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.95),
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Channel logo, title, LIVE badge, and Guide button
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: TvTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: channel.logoUrl != null
                        ? Image.network(
                            channel.logoUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.live_tv_rounded,
                              color: TvTheme.primaryAccent,
                              size: 22,
                            ),
                          )
                        : const Icon(
                            Icons.live_tv_rounded,
                            color: TvTheme.primaryAccent,
                            size: 22,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '#${channel.channelNumber}  ${channel.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                gradient: tvState.isVodStream
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF8B5CF6),
                                          Color(0xFF06B6D4),
                                        ],
                                      )
                                    : null,
                                color: tvState.isVodStream
                                    ? null
                                    : Colors.redAccent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tvState.isVodStream ? 'VOD' : 'LIVE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => const StreamSettingsDialog(
                                    initialTabIndex: 0,
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: TvTheme.primary.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: TvTheme.primaryAccent.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _getVideoQualityBadge(tvState.activePlayer),
                                  style: const TextStyle(
                                    color: TvTheme.primaryAccent,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentProgram?.title ?? 'Live Broadcast',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: TvTheme.primaryAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tvState.showBottomChannelList
                          ? TvTheme.primaryAccent.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.15),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      side: tvState.showBottomChannelList
                          ? const BorderSide(
                              color: TvTheme.primaryAccent,
                              width: 1,
                            )
                          : null,
                    ),
                    onPressed: () => tvState.toggleBottomChannelList(),
                    icon: const Icon(Icons.view_carousel_rounded, size: 16),
                    label: const Text(
                      'Channels',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TvTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: onOpenGuide,
                    icon: const Icon(Icons.grid_view_rounded, size: 16),
                    label: const Text('Guide', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),

              if (tvState.isVodStream) ...[
                const SizedBox(height: 8),
                _buildVodProgressBar(isMobile: true),
              ] else if (currentProgram != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: currentProgram.progress,
                    backgroundColor: Colors.white24,
                    color: TvTheme.primary,
                    minHeight: 3,
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // Row 2: Touch action controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (tvState.isVodStream) ...[
                    IconButton(
                      icon: const Icon(
                        Icons.replay_10_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      tooltip: 'Rewind 10s',
                      onPressed: () =>
                          tvState.seekRelative(const Duration(seconds: -10)),
                    ),
                    IconButton(
                      icon: Icon(
                        tvState.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: tvState.isPlaying
                            ? TvTheme.primaryAccent
                            : Colors.greenAccent,
                        size: 34,
                      ),
                      tooltip: tvState.isPlaying ? 'Pause' : 'Play',
                      onPressed: () => tvState.togglePlayPause(),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.forward_10_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      tooltip: 'Forward 10s',
                      onPressed: () =>
                          tvState.seekRelative(const Duration(seconds: 10)),
                    ),
                  ] else ...[
                    IconButton(
                      icon: const Icon(
                        Icons.skip_previous_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      tooltip: 'Previous Channel',
                      onPressed: () => tvState.playPreviousChannel(),
                    ),
                    IconButton(
                      icon: Icon(
                        tvState.isPlaying
                            ? Icons.stop_circle_rounded
                            : Icons.play_circle_fill_rounded,
                        color: tvState.isPlaying
                            ? Colors.redAccent
                            : Colors.greenAccent,
                        size: 34,
                      ),
                      tooltip: tvState.isPlaying ? 'Stop' : 'Play',
                      onPressed: () => tvState.togglePlayPause(),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                      tooltip: 'Next Channel',
                      onPressed: () => tvState.playNextChannel(),
                    ),
                  ],
                  IconButton(
                    icon: const Icon(
                      Icons.picture_in_picture,
                      color: Colors.white,
                      size: 22,
                    ),
                    tooltip: 'Picture-in-Picture (P)',
                    onPressed: () => tvState.enterSystemPip(context: context),
                  ),
                  IconButton(
                    icon: Icon(
                      tvState.isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: tvState.isMuted ? Colors.redAccent : Colors.white,
                      size: 24,
                    ),
                    tooltip: tvState.isMuted ? 'Unmute' : 'Mute',
                    onPressed: () => tvState.toggleMute(),
                  ),
                  IconButton(
                    icon: Icon(
                      tvState.isCurrentChannelRecording
                          ? Icons.fiber_smart_record_rounded
                          : Icons.fiber_manual_record_rounded,
                      color: tvState.isCurrentChannelRecording
                          ? Colors.redAccent
                          : Colors.white,
                      size: 26,
                    ),
                    tooltip: 'Record Stream',
                    onPressed: () => _showRecordDialog(context, tvState),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.settings_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                    tooltip: 'Video Quality & Settings',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) =>
                            const StreamSettingsDialog(initialTabIndex: 0),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.90),
            Colors.black.withValues(alpha: 0.50),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Channel & Program Header Row
          Row(
            children: [
              // Channel Logo
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: TvTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: channel.logoUrl != null
                    ? Image.network(
                        channel.logoUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.live_tv_rounded,
                          color: TvTheme.primaryAccent,
                          size: 28,
                        ),
                      )
                    : const Icon(
                        Icons.live_tv_rounded,
                        color: TvTheme.primaryAccent,
                        size: 28,
                      ),
              ),
              const SizedBox(width: 14),

              // Title and Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '#${channel.channelNumber}  ${channel.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            gradient: tvState.isVodStream
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF8B5CF6),
                                      Color(0xFF06B6D4),
                                    ],
                                  )
                                : null,
                            color: tvState.isVodStream
                                ? null
                                : Colors.redAccent,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: tvState.isVodStream
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF8B5CF6,
                                      ).withValues(alpha: 0.4),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            tvState.isVodStream ? 'VOD' : 'LIVE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (channel.hasDrm) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Text(
                              channel.drmType?.toUpperCase() ?? 'DRM',
                              style: const TextStyle(
                                color: Colors.amber,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentProgram?.title ?? 'Live Broadcast',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: TvTheme.primaryAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // Quick Actions
              // IconButton(
              //   tooltip: 'Previous Channel (Up)',
              //   icon: const Icon(
              //     Icons.skip_previous_rounded,
              //     color: Colors.white,
              //     size: 28,
              //   ),
              //   onPressed: () => tvState.playPreviousChannel(),
              // ),
              // IconButton(
              //   tooltip: tvState.isPlaying
              //       ? 'Stop Broadcast (Space)'
              //       : 'Play Broadcast (Space)',
              //   icon: Icon(
              //     tvState.isPlaying
              //         ? Icons.stop_circle_rounded
              //         : Icons.play_circle_fill_rounded,
              //     color: tvState.isPlaying
              //         ? Colors.redAccent
              //         : Colors.greenAccent,
              //     size: 32,
              //   ),
              //   onPressed: () => tvState.togglePlayPause(),
              // ),
              // IconButton(
              //   tooltip: 'Next Channel (Down)',
              //   icon: const Icon(
              //     Icons.skip_next_rounded,
              //     color: Colors.white,
              //     size: 28,
              //   ),
              //   onPressed: () => tvState.playNextChannel(),
              // ),
              IconButton(
                tooltip:
                    'Aspect Ratio (${tvState.scaleMode.name.toUpperCase()})',
                icon: const Icon(
                  Icons.aspect_ratio_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () => tvState.cycleScaleMode(),
              ),
              IconButton(
                tooltip: 'Picture-in-Picture',
                onPressed: () => tvState.enterSystemPip(context: context),
                icon: const Icon(Icons.picture_in_picture),
              ),
              IconButton(
                tooltip: tvState.isMuted ? 'Unmute (M)' : 'Mute (M)',
                icon: Icon(
                  tvState.isMuted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: tvState.isMuted ? Colors.redAccent : Colors.white,
                  size: 26,
                ),
                onPressed: () => tvState.toggleMute(),
              ),
              IconButton(
                tooltip: tvState.isCurrentChannelRecording
                    ? 'Recording in progress (Click for options)'
                    : 'Record stream (R)',
                icon: Icon(
                  tvState.isCurrentChannelRecording
                      ? Icons.fiber_smart_record_rounded
                      : Icons.fiber_manual_record_rounded,
                  color: tvState.isCurrentChannelRecording
                      ? Colors.redAccent
                      : Colors.white,
                  size: 28,
                ),
                onPressed: () => _showRecordDialog(context, tvState),
              ),
              const SizedBox(width: 4),
              // Video Quality Selector Button
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) =>
                        const StreamSettingsDialog(initialTabIndex: 0),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: TvTheme.primaryAccent.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.high_quality_rounded,
                        color: TvTheme.primaryAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _getVideoQualityBadge(tvState.activePlayer),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // IconButton(
              //   tooltip: 'Video Quality & Stream Settings (S)',
              //   icon: const Icon(
              //     Icons.settings_rounded,
              //     color: Colors.white,
              //     size: 26,
              //   ),
              //   onPressed: () {
              //     showDialog(
              //       context: context,
              //       builder: (_) => const StreamSettingsDialog(
              //         initialTabIndex: 0,
              //       ),
              //     );
              //   },
              // ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: tvState.showBottomChannelList
                      ? TvTheme.primaryAccent.withValues(alpha: 0.35)
                      : Colors.white.withValues(alpha: 0.15),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: tvState.showBottomChannelList
                      ? const BorderSide(
                          color: TvTheme.primaryAccent,
                          width: 1.2,
                        )
                      : null,
                ),
                onPressed: () => tvState.toggleBottomChannelList(),
                child: const Icon(Icons.view_carousel_rounded, size: 18),
                // label: const Text('Channels (C)'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: TvTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onOpenGuide,
                child: const Icon(Icons.grid_view_rounded, size: 18),
                // label: const Text('TV Guide (F)'),
              ),
            ],
          ),

          if (tvState.isVodStream) ...[
            const SizedBox(height: 12),
            _buildVodProgressBar(isMobile: false),
          ] else if (currentProgram != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: currentProgram.progress,
                backgroundColor: Colors.white24,
                color: TvTheme.primary,
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showRecordDialog(BuildContext context, TvStateProvider tvState) {
    final channel = widget.channel;
    final currentProgram = widget.currentProgram;
    if (channel == null) return;
    final isRecording = tvState.isCurrentChannelRecording;
    final bytes = tvState.currentChannelBytesRecorded;
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: TvTheme.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: TvTheme.borderSubtle, width: 1.5),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (isRecording ? Colors.redAccent : TvTheme.primary)
                                .withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isRecording
                            ? Icons.fiber_smart_record_rounded
                            : Icons.fiber_manual_record_rounded,
                        color: isRecording
                            ? Colors.redAccent
                            : TvTheme.primaryAccent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isRecording
                                ? 'Stream Recording in Progress'
                                : 'Record Broadcast Stream',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            channel.name,
                            style: const TextStyle(
                              fontSize: 13,
                              color: TvTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                if (isRecording) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Data Captured:',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          '$mb MB',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text(
                          'Keep Recording',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          tvState.stopActiveChannelRecording();
                          Navigator.of(ctx).pop();
                          TvToast.success(
                            context,
                            'Recording stopped and saved to DVR library',
                          );
                        },
                        icon: const Icon(Icons.stop_rounded, size: 18),
                        label: const Text(
                          'Stop Recording',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  if (currentProgram != null) ...[
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      tileColor: TvTheme.surfaceElevated,
                      leading: const Icon(
                        Icons.schedule_rounded,
                        color: TvTheme.primaryAccent,
                      ),
                      title: Text(
                        'Record Until Program Ends',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${currentProgram.title} (${currentProgram.remainingMinutes}m remaining)',
                        style: const TextStyle(
                          color: TvTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        tvState.startInstantRecording(
                          duration: Duration(
                            minutes: currentProgram.remainingMinutes.clamp(
                              5,
                              360,
                            ),
                          ),
                        );
                        Navigator.of(ctx).pop();
                        TvToast.success(
                          context,
                          'Started recording "${currentProgram.title}"',
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tileColor: TvTheme.surfaceElevated,
                    leading: const Icon(
                      Icons.timelapse_rounded,
                      color: TvTheme.primaryAccent,
                    ),
                    title: const Text(
                      'Record for 30 Minutes',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    onTap: () {
                      tvState.startInstantRecording(
                        duration: const Duration(minutes: 30),
                      );
                      Navigator.of(ctx).pop();
                      TvToast.success(
                        context,
                        'Started recording for 30 minutes',
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tileColor: TvTheme.surfaceElevated,
                    leading: const Icon(
                      Icons.timer_rounded,
                      color: TvTheme.primaryAccent,
                    ),
                    title: const Text(
                      'Record for 1 Hour',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    onTap: () {
                      tvState.startInstantRecording(
                        duration: const Duration(hours: 1),
                      );
                      Navigator.of(ctx).pop();
                      TvToast.success(context, 'Started recording for 1 hour');
                    },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tileColor: TvTheme.surfaceElevated,
                    leading: const Icon(
                      Icons.more_time_rounded,
                      color: TvTheme.primaryAccent,
                    ),
                    title: const Text(
                      'Record for 2 Hours',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    onTap: () {
                      tvState.startInstantRecording(
                        duration: const Duration(hours: 2),
                      );
                      Navigator.of(ctx).pop();
                      TvToast.success(context, 'Started recording for 2 hours');
                    },
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _getVideoQualityBadge(Player? player) {
    if (player == null) return 'HD';
    final h =
        player.state.height ??
        player.state.videoParams.h ??
        player.state.track.video.h;
    if (h != null && h >= 2160) return '4K';
    if (h != null && h >= 1440) return '2K';
    if (h != null && h >= 1080) return '1080p';
    if (h != null && h >= 720) return '720p';
    if (h != null && h >= 480) return '480p';
    if (h != null && h > 0) return '${h}p';
    return 'HD';
  }
}
