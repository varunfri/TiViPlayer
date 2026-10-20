import 'package:flutter/material.dart';
import '../../models/channel.dart';
import '../../providers/tv_state_provider.dart';
import '../theme.dart';

class BottomChannelScrollListWidget extends StatefulWidget {
  final TvStateProvider tvState;
  final VoidCallback? onClose;
  final bool isStandalone;

  const BottomChannelScrollListWidget({
    super.key,
    required this.tvState,
    this.onClose,
    this.isStandalone = false,
  });

  @override
  State<BottomChannelScrollListWidget> createState() =>
      _BottomChannelScrollListWidgetState();
}

class _BottomChannelScrollListWidgetState
    extends State<BottomChannelScrollListWidget> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _categoriesScrollController = ScrollController();

  static const double _cardWidth = 195.0;
  static const double _cardHeight = 100.0;
  static const double _spacing = 10.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveChannel();
      _scrollToActiveCategory();
    });
  }

  @override
  void didUpdateWidget(covariant BottomChannelScrollListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tvState.activePlayingChannel?.id !=
        widget.tvState.activePlayingChannel?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveChannel();
      });
    }
    if (oldWidget.tvState.selectedGroup?.id !=
        widget.tvState.selectedGroup?.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveCategory();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _categoriesScrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveChannel() {
    if (!_scrollController.hasClients) return;
    final channels = widget.tvState.channels;
    final activeId = widget.tvState.activePlayingChannel?.id;
    if (activeId == null) return;

    final index = channels.indexWhere((c) => c.id == activeId);
    if (index >= 0) {
      final target = (index * (_cardWidth + _spacing) - 40.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollToActiveCategory() {
    if (!_categoriesScrollController.hasClients) return;
    final groupId = widget.tvState.selectedGroup?.id;
    if (groupId == null) return;
    final index = widget.tvState.groups.indexWhere((g) => g.id == groupId);
    if (index >= 0) {
      final chipIndex = index + 1;
      const chipWidth = 110.0;
      final target = (chipIndex * chipWidth - 40.0).clamp(
        0.0,
        _categoriesScrollController.position.maxScrollExtent,
      );
      _categoriesScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tvState = widget.tvState;
    final channels = tvState.channels;
    final groups = tvState.groups;
    final isMobile = MediaQuery.sizeOf(context).shortestSide < 600;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .3),
        // color: Colors.black.withValues(alpha: 0.90),
        // border: const Border(top: BorderSide(color: Colors.grey, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Title, Category Filter Chips & Close Button
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
              child: Row(
                children: [
                  // Title Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: TvTheme.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: TvTheme.primary.withValues(alpha: 0.6),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.view_carousel_rounded,
                          size: 14,
                          color: TvTheme.primaryAccent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'CHANNELS (${channels.length})',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Category Filter Chips
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: ListView(
                        controller: _categoriesScrollController,
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildCategoryChip(
                            label: 'All',
                            isSelected: tvState.selectedGroup == null,
                            onTap: () => tvState.selectGroup(null),
                          ),
                          for (final group in groups)
                            _buildCategoryChip(
                              label: group.name,
                              isSelected: tvState.selectedGroup?.id == group.id,
                              onTap: () => tvState.selectGroup(group),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Close / Dismiss Button (if in overlay/closeable mode)
                  if (widget.onClose != null || !widget.isStandalone)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      tooltip: 'Close Channel Bar',
                      onPressed: () {
                        if (widget.onClose != null) {
                          widget.onClose!();
                        } else {
                          tvState.setBottomChannelList(false);
                        }
                      },
                    ),
                ],
              ),
            ),

            // Horizontal Scrolling Channel Cards
            SizedBox(
              height: isMobile ? 96 : _cardHeight,
              child: channels.isEmpty
                  ? Center(
                      child: Text(
                        'No channels found in this category',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      itemCount: channels.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: _spacing),
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        final isPlaying =
                            tvState.activePlayingChannel?.id == channel.id;
                        final isSelected =
                            tvState.selectedChannel?.id == channel.id;

                        return _buildChannelCard(
                          context,
                          channel,
                          isPlaying: isPlaying,
                          isSelected: isSelected,
                          tvState: tvState,
                          isMobile: isMobile,
                        );
                      },
                    ),
            ),

            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? TvTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? TvTheme.primaryAccent : Colors.white12,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelCard(
    BuildContext context,
    Channel channel, {
    required bool isPlaying,
    required bool isSelected,
    required TvStateProvider tvState,
    required bool isMobile,
  }) {
    final width = isMobile ? 180.0 : _cardWidth;
    final liveProgram = isSelected && tvState.currentProgram != null
        ? tvState.currentProgram
        : tvState.getLiveProgramForChannel(channel);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          tvState.playChannel(channel);
          tvState.selectChannel(channel);
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.transparent,
            // color: isPlaying
            //     ? TvTheme.surfaceElevated.withValues(alpha: 0.95)
            //     : TvTheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPlaying
                  ? TvTheme.primaryAccent
                  : isSelected
                  ? Colors.white38
                  : Colors.white10,
              width: isPlaying ? 2.0 : 1.0,
            ),
            boxShadow: isPlaying
                ? [
                    BoxShadow(
                      color: TvTheme.primaryAccent.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Row 1: Logo, Number & LIVE / Playing Badge + Favorite
              Row(
                children: [
                  // Logo container
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
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
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.live_tv_rounded,
                            size: 16,
                            color: TvTheme.primaryAccent,
                          ),
                  ),

                  const SizedBox(width: 6),

                  // Channel Number Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: isPlaying
                          ? TvTheme.primaryAccent.withValues(alpha: 0.2)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#${channel.channelNumber}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        // color: isPlaying
                        //     ? TvTheme.primaryAccent
                        //     : Colors.white70,
                      ),
                    ),
                  ),

                  const Spacer(),

                  if (isPlaying)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  const SizedBox(width: 4),

                  // Favorite Star Button
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tvState.toggleFavorite(channel),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        channel.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 16,
                        color: channel.isFavorite
                            ? TvTheme.accentGold
                            : Colors.white38,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              // Channel Name
              Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.w600,
                  color: isPlaying
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.9),
                ),
              ),

              // Program Title
              Text(
                liveProgram != null
                    ? liveProgram.title
                    : (channel.groupName ?? 'Live Broadcast'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  // color: isPlaying
                  //     ? TvTheme.primaryAccent
                  //     : Colors.white.withValues(alpha: 0.75),
                  fontWeight: isPlaying ? FontWeight.w500 : FontWeight.normal,
                ),
              ),

              if (liveProgram != null) ...[
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(1.5),
                  child: LinearProgressIndicator(
                    value: liveProgram.progress,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isPlaying ? TvTheme.primaryAccent : TvTheme.primary,
                    ),
                    minHeight: 2.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
