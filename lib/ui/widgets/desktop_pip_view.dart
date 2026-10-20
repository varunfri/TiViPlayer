import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../providers/tv_state_provider.dart';

class DesktopPipView extends StatefulWidget {
  final Widget playerWidget;

  const DesktopPipView({super.key, required this.playerWidget});

  @override
  State<DesktopPipView> createState() => _DesktopPipViewState();
}

class _DesktopPipViewState extends State<DesktopPipView> {
  bool _showControls = false;
  Timer? _hideTimer;

  void _onHover() {
    if (!_showControls) {
      setState(() => _showControls = true);
    }
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tvState = context.watch<TvStateProvider>();
    final channel = tvState.activePlayingChannel;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.keyP) {
            tvState.exitDesktopPip();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.keyK ||
              key == LogicalKeyboardKey.mediaPlayPause) {
            tvState.togglePlayPause();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.keyM ||
              key == LogicalKeyboardKey.audioVolumeMute) {
            tvState.toggleMute();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.pageUp ||
              key == LogicalKeyboardKey.channelUp) {
            tvState.playPreviousChannel();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.pageDown ||
              key == LogicalKeyboardKey.channelDown) {
            tvState.playNextChannel();
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.equal ||
              key == LogicalKeyboardKey.numpadAdd ||
              key == LogicalKeyboardKey.bracketRight ||
              key == LogicalKeyboardKey.audioVolumeUp) {
            tvState.setVolume((tvState.volume + 0.05).clamp(0.0, 1.0));
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.minus ||
              key == LogicalKeyboardKey.numpadSubtract ||
              key == LogicalKeyboardKey.bracketLeft ||
              key == LogicalKeyboardKey.audioVolumeDown) {
            tvState.setVolume((tvState.volume - 0.05).clamp(0.0, 1.0));
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => _onHover(),
        onHover: (_) => _onHover(),
        onExit: (_) {
          _hideTimer?.cancel();
          if (mounted) setState(() => _showControls = false);
        },
        child: GestureDetector(
          onDoubleTap: () => tvState.exitDesktopPip(),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                // 1. Live Video Surface
                Positioned.fill(child: widget.playerWidget),

                // 2. Drag Area Header (allows dragging window across desktop)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 48,
                  child: DragToMoveArea(
                    child: Container(color: Colors.transparent),
                  ),
                ),

                // 3. Floating Overlay Controls (appears on hover)
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Stack(
                      children: [
                        // Subtle gradient scrim
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xB3000000),
                                  Colors.transparent,
                                  Color(0xB3000000),
                                ],
                                stops: [0.0, 0.45, 1.0],
                              ),
                            ),
                          ),
                        ),

                        // Top Title Bar & Close / Restore
                        Positioned(
                          top: 8,
                          left: 12,
                          right: 10,
                          child: Row(
                            children: [
                              // Drag Handle Icon
                              const DragToMoveArea(
                                child: Padding(
                                  padding: EdgeInsets.only(right: 6),
                                  child: Icon(
                                    Icons.drag_indicator_rounded,
                                    size: 16,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              // Channel Info
                              Expanded(
                                child: DragToMoveArea(
                                  child: Text(
                                    channel != null
                                        ? '#${channel.channelNumber} ${channel.name}'
                                        : 'TiviPlayer PiP',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              // Expand / Restore Button
                              IconButton(
                                icon: const Icon(
                                  Icons.open_in_full_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                tooltip: 'Restore Window (Esc)',
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => tvState.exitDesktopPip(),
                              ),
                              const SizedBox(width: 4),
                              // Close PiP Button
                              IconButton(
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Colors.white70,
                                ),
                                tooltip: 'Close PiP',
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  tvState.exitDesktopPip();
                                },
                              ),
                            ],
                          ),
                        ),

                        // Bottom Action Controls (Play/Pause, Mute, Prev/Next)
                        Positioned(
                          bottom: 8,
                          left: 12,
                          right: 12,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Previous Channel
                              IconButton(
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                                tooltip: 'Previous Channel',
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => tvState.playPreviousChannel(),
                              ),
                              const SizedBox(width: 8),
                              // Play / Pause
                              IconButton(
                                icon: Icon(
                                  tvState.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  size: 24,
                                  color: Colors.white,
                                ),
                                tooltip: tvState.isPlaying ? 'Pause' : 'Play',
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => tvState.togglePlayPause(),
                              ),
                              const SizedBox(width: 8),
                              // Next Channel
                              IconButton(
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                                tooltip: 'Next Channel',
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => tvState.playNextChannel(),
                              ),
                              const Spacer(),
                              // Mute / Unmute
                              IconButton(
                                icon: Icon(
                                  tvState.isMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  size: 18,
                                  color: tvState.isMuted
                                      ? Colors.redAccent
                                      : Colors.white,
                                ),
                                tooltip: tvState.isMuted ? 'Unmute' : 'Mute',
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: () => tvState.toggleMute(),
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
          ),
        ),
      ),
    );
  }
}
