import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/channel.dart';
import '../../providers/tv_state_provider.dart';
import '../../ui/theme.dart';

class EpgGridView extends StatefulWidget {
  final TvStateProvider tvState;

  const EpgGridView({super.key, required this.tvState});

  @override
  State<EpgGridView> createState() => _EpgGridViewState();
}

class _EpgGridViewState extends State<EpgGridView> {
  final ScrollController _horizontalTimelineController = ScrollController();
  final ScrollController _verticalChannelsController = ScrollController();

  late DateTime _timelineStart;
  final int _totalHours = 12;
  final double _hourWidth = 320.0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _timelineStart = DateTime(now.year, now.month, now.day, now.hour - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveChannel();
    });
  }

  @override
  void didUpdateWidget(covariant EpgGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tvState.activePlayingChannel?.id !=
        widget.tvState.activePlayingChannel?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveChannel();
      });
    }
  }

  void _scrollToActiveChannel() {
    if (!_verticalChannelsController.hasClients) return;
    final activeId = widget.tvState.activePlayingChannel?.id ??
        widget.tvState.selectedChannel?.id;
    if (activeId == null) return;
    final index = widget.tvState.channels.indexWhere((c) => c.id == activeId);
    if (index >= 0) {
      const itemHeight = 64.0;
      final target = (index * itemHeight - 120.0).clamp(
        0.0,
        _verticalChannelsController.position.maxScrollExtent,
      );
      _verticalChannelsController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _horizontalTimelineController.dispose();
    _verticalChannelsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channels = widget.tvState.channels;
    final timeFormatter = DateFormat('hh:mm a');

    final isMobile = MediaQuery.sizeOf(context).width < 700;
    final channelColWidth = isMobile ? 120.0 : 210.0;

    return Column(
      children: [
        // Top Toolbar in EPG Grid: Focused Channel & Program Metadata
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 20,
            vertical: isMobile ? 8 : 12,
          ),
          color: TvTheme.surface.withValues(alpha: 0.95),
          child: Row(
            children: [
              // Program Detail for currently focused/selected channel
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: TvTheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.tvState.selectedChannel != null
                                ? '#${widget.tvState.selectedChannel!.channelNumber}  ${widget.tvState.selectedChannel!.name}'
                                : 'No Channel Selected',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (widget.tvState.selectedChannel?.hasDrm == true)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                            ),
                            child: Text(
                              widget.tvState.selectedChannel!.drmType?.toUpperCase() ?? 'DRM',
                              style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        Text(
                          widget.tvState.currentProgram != null
                              ? '${timeFormatter.format(widget.tvState.currentProgram!.startTime)} - ${timeFormatter.format(widget.tvState.currentProgram!.endTime)}'
                              : 'Live Transmission',
                          style: const TextStyle(
                            color: TvTheme.primaryAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.tvState.currentProgram?.title ?? 'No Program Information',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 15 : 18,
                      ),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.tvState.currentProgram?.description ??
                            'Select any program on the timeline grid to zap channels or view show information.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TvTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        const Divider(color: TvTheme.borderSubtle, height: 1),

        // Horizontal Timeline Ruler
        Container(
          height: 38,
          color: TvTheme.surfaceElevated,
          child: Row(
            children: [
              // Spacer matching channel column width
              Container(
                width: channelColWidth,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                child: const Text(
                  'CHANNEL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: TvTheme.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _horizontalTimelineController,
                  scrollDirection: Axis.horizontal,
                  itemCount: _totalHours * 2, // 30-min intervals
                  itemBuilder: (context, index) {
                    final slotTime = _timelineStart.add(
                      Duration(minutes: index * 30),
                    );
                    return Container(
                      width: _hourWidth / 2,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: TvTheme.borderSubtle,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Text(
                        timeFormatter.format(slotTime),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: TvTheme.textMuted,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        const Divider(color: TvTheme.borderSubtle, height: 1),

        // 2D EPG Rows: Left = Channel, Right = Program Blocks
        Expanded(
          child: ListView.builder(
            controller: _verticalChannelsController,
            itemCount: channels.length,
            itemBuilder: (context, channelIndex) {
              final channel = channels[channelIndex];
              final isPlaying =
                  widget.tvState.activePlayingChannel?.id == channel.id;
              final isSelected =
                  widget.tvState.selectedChannel?.id == channel.id;

              return Container(
                height: 64,
                decoration: BoxDecoration(
                  color: channelIndex % 2 == 0
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.02),
                  border: const Border(
                    bottom: BorderSide(color: TvTheme.borderSubtle, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    // Channel Header Cell
                    InkWell(
                      onTap: () => widget.tvState.playChannel(channel),
                      child: Container(
                        width: channelColWidth,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? TvTheme.surfaceFocus
                              : TvTheme.surface.withValues(alpha: 0.9),
                          border: Border(
                            left: BorderSide(
                              color: isPlaying
                                  ? Colors.redAccent
                                  : (isSelected
                                        ? TvTheme.primaryAccent
                                        : Colors.transparent),
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '${channel.channelNumber}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: TvTheme.textMuted,
                              ),
                            ),
                            SizedBox(width: isMobile ? 6 : 10),
                            Container(
                              width: isMobile ? 26 : 32,
                              height: isMobile ? 26 : 32,
                              decoration: BoxDecoration(
                                color: TvTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: channel.logoUrl != null
                                  ? Image.network(
                                      channel.logoUrl!,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.live_tv_rounded,
                                        size: 16,
                                        color: TvTheme.primaryAccent,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.live_tv_rounded,
                                      size: 16,
                                      color: TvTheme.primaryAccent,
                                    ),
                            ),
                            SizedBox(width: isMobile ? 6 : 10),
                            Expanded(
                              child: Text(
                                channel.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontSize: 13,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Program blocks row along timeline
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: _buildProgramBlocks(channel),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProgramBlocks(Channel channel) {
    // Generate or render timeline program blocks for this channel
    final programs = widget.tvState.upcomingPrograms;

    return Row(
      children: List.generate(8, (i) {
        final blockStart = _timelineStart.add(Duration(hours: i * 2));
        final blockEnd = blockStart.add(const Duration(hours: 2));
        final blockWidth = _hourWidth * 2;
        final isNow =
            DateTime.now().isAfter(blockStart) &&
            DateTime.now().isBefore(blockEnd);

        final title = (i < programs.length)
            ? programs[i].title
            : '${channel.name} Feature Presentation';

        return InkWell(
          onTap: () {
            widget.tvState.selectChannel(channel);
          },
          onDoubleTap: () {
            widget.tvState.playChannel(channel);
          },
          child: Container(
            width: blockWidth,
            height: 56,
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isNow
                  ? TvTheme.primary.withValues(alpha: 0.25)
                  : TvTheme.surfaceElevated.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isNow ? TvTheme.primaryAccent : TvTheme.borderSubtle,
                width: isNow ? 1.5 : 0.8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    if (isNow) ...[
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isNow ? FontWeight.bold : FontWeight.w500,
                          color: isNow ? Colors.white : Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('hh:mm a').format(blockStart)} - ${DateFormat('hh:mm a').format(blockEnd)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: TvTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
