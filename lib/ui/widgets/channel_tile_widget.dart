import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/channel.dart';
import '../../models/epg_program.dart';
import '../../ui/theme.dart';

class ChannelTileWidget extends StatefulWidget {
  final Channel channel;
  final EpgProgram? currentProgram;
  final bool isSelected;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onInfoTap;

  const ChannelTileWidget({
    super.key,
    required this.channel,
    this.currentProgram,
    this.isSelected = false,
    this.isPlaying = false,
    required this.onTap,
    required this.onToggleFavorite,
    this.onInfoTap,
  });

  @override
  State<ChannelTileWidget> createState() => _ChannelTileWidgetState();
}

class _ChannelTileWidgetState extends State<ChannelTileWidget> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final hasFocus = _isFocused || widget.isSelected;

    return Focus(
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            // color: hasFocus ? TvTheme.surfaceFocus : TvTheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasFocus ? TvTheme.primaryAccent : Colors.transparent,
              width: 2,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: TvTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            children: [
              // Channel Number
              Container(
                width: 38,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${widget.channel.channelNumber}',
                  style: TextStyle(
                    color: hasFocus ? TvTheme.textBright : TvTheme.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),

              // Channel Logo or Placeholder Icon
              Container(
                width: 44,
                height: 44,
                margin: const EdgeInsets.only(right: 14),
                decoration: BoxDecoration(
                  color: TvTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: widget.channel.logoUrl != null
                    ? Image.network(
                        widget.channel.logoUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.live_tv_rounded,
                          color: TvTheme.primaryAccent,
                          size: 24,
                        ),
                      )
                    : const Icon(
                        Icons.live_tv_rounded,
                        color: TvTheme.primaryAccent,
                        size: 24,
                      ),
              ),

              // Channel & EPG Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: hasFocus
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  color: hasFocus
                                      ? TvTheme.textBright
                                      : Colors.white,
                                ),
                          ),
                        ),
                        if (widget.isPlaying) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'LIVE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),

                    if (widget.currentProgram != null) ...[
                      // Current Program Title
                      Text(
                        widget.currentProgram!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: hasFocus
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),

                      // Timing row: Start - End • remaining min left
                      Builder(
                        builder: (context) {
                          final prog = widget.currentProgram!;
                          final startStr = DateFormat(
                            'h:mm a',
                          ).format(prog.startTime);
                          final endStr = DateFormat(
                            'h:mm a',
                          ).format(prog.endTime);
                          final remaining = prog.remainingMinutes;
                          final timingText = remaining > 0
                              ? '$startStr - $endStr • ${remaining}m left'
                              : '$startStr - $endStr';
                          return Text(
                            timingText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasFocus
                                  ? TvTheme.primaryAccent
                                  : TvTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 5),

                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: widget.currentProgram!.progress,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            hasFocus ? TvTheme.primaryAccent : TvTheme.primary,
                          ),
                          minHeight: 3,
                        ),
                      ),
                    ] else ...[
                      // Category or fallback
                      Text(
                        widget.channel.groupName ?? 'Live Broadcast',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: hasFocus ? Colors.white70 : TvTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Info / EPG Schedule Button (especially useful on mobile)
              if (widget.onInfoTap != null)
                IconButton(
                  tooltip: 'Details & Schedule',
                  icon: const Icon(
                    Icons.info_outline_rounded,
                    color: TvTheme.textMuted,
                    size: 20,
                  ),
                  onPressed: widget.onInfoTap,
                ),

              // Favorite Star Icon Button
              IconButton(
                icon: Icon(
                  widget.channel.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: widget.channel.isFavorite
                      ? TvTheme.accentGold
                      : TvTheme.textMuted,
                  size: 22,
                ),
                onPressed: widget.onToggleFavorite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
