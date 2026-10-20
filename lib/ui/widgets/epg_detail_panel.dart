import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/channel.dart';
import '../../models/epg_program.dart';
import '../../providers/tv_state_provider.dart';
import '../../ui/theme.dart';
import 'tv_toast.dart';

class EpgDetailPanel extends StatelessWidget {
  final Channel? channel;
  final EpgProgram? currentProgram;
  final List<EpgProgram> upcomingPrograms;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleFullscreen;

  const EpgDetailPanel({
    super.key,
    required this.channel,
    required this.currentProgram,
    required this.upcomingPrograms,
    required this.onToggleFavorite,
    required this.onToggleFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    if (channel == null) {
      return Container(
        color: TvTheme.surface.withValues(alpha: 0.95),
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: Text(
            'No Channel Selected',
            style: TextStyle(color: TvTheme.textMuted),
          ),
        ),
      );
    }

    final timeFormatter = DateFormat('hh:mm a');

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: const Border(
          left: BorderSide(color: TvTheme.borderSubtle, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Channel Title & Actions Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel!.name,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Channel #${channel!.channelNumber} • ${channel!.groupName ?? "Live TV"}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TvTheme.primaryAccent,
                      ),
                    ),
                    if (channel!.hasDrm) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.lock_rounded,
                                  size: 11,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'DRM: ${channel!.drmType?.toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  channel!.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: channel!.isFavorite
                      ? TvTheme.accentGold
                      : TvTheme.textMuted,
                  size: 26,
                ),
                onPressed: onToggleFavorite,
                tooltip: 'Toggle Favorite',
              ),
              IconButton(
                icon: const Icon(
                  Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: onToggleFullscreen,
                tooltip: 'Fullscreen Player',
              ),
            ],
          ),

          const Divider(color: TvTheme.borderSubtle, height: 28),

          // Currently Live Program
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NOW PLAYING',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.redAccent.withValues(alpha: 0.9),
                ),
              ),
              Consumer<TvStateProvider>(
                builder: (context, tvState, _) {
                  final isRec =
                      channel!.id != null &&
                      tvState.isRecordingChannel(channel!.id!);
                  if (!isRec) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: const Text(
                      'RECORDING',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            currentProgram?.title ?? 'Live Transmission',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),

          if (currentProgram != null) ...[
            const SizedBox(height: 4),
            Text(
              '${timeFormatter.format(currentProgram!.startTime)} - ${timeFormatter.format(currentProgram!.endTime)} (${currentProgram!.durationMinutes} min)',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: currentProgram!.progress,
                backgroundColor: Colors.white12,
                color: TvTheme.primary,
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              currentProgram!.description ?? 'No program description provided.',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 12),
            Consumer<TvStateProvider>(
              builder: (context, tvState, _) {
                final isRec =
                    channel!.id != null &&
                    tvState.isRecordingChannel(channel!.id!);
                return Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRec
                            ? Colors.redAccent
                            : TvTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (isRec) {
                          tvState.stopActiveChannelRecording();
                          TvToast.success(
                            context,
                            'Recording stopped and saved to DVR library',
                          );
                        } else {
                          tvState.startInstantRecording(
                            duration: Duration(
                              minutes: currentProgram!.remainingMinutes.clamp(
                                5,
                                360,
                              ),
                            ),
                          );
                          TvToast.success(
                            context,
                            'Started recording "${currentProgram!.title}"',
                          );
                        }
                      },
                      icon: Icon(
                        isRec
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record_rounded,
                        size: 16,
                      ),
                      label: Text(
                        isRec ? 'Stop Recording' : 'Record Program',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],

          const Divider(color: TvTheme.borderSubtle, height: 28),

          // Upcoming Schedule
          Text(
            'UPCOMING SCHEDULE',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: TvTheme.textMuted,
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: upcomingPrograms.isEmpty
                ? const Text(
                    'No upcoming schedule metadata available for this channel.',
                    style: TextStyle(color: TvTheme.textMuted, fontSize: 13),
                  )
                : ListView.separated(
                    itemCount: upcomingPrograms.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final prog = upcomingPrograms[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: TvTheme.surfaceElevated.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    timeFormatter.format(prog.startTime),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: TvTheme.primaryAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    prog.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Consumer<TvStateProvider>(
                              builder: (context, tvState, _) => IconButton(
                                icon: const Icon(
                                  Icons.alarm_add_rounded,
                                  color: TvTheme.primaryAccent,
                                  size: 20,
                                ),
                                tooltip: 'Schedule Recording',
                                onPressed: () => _showScheduleDialog(
                                  context,
                                  channel!,
                                  prog,
                                  tvState,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showScheduleDialog(
    BuildContext context,
    Channel channel,
    EpgProgram prog,
    TvStateProvider tvState,
  ) {
    int preRoll = 2;
    int postRoll = 5;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
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
                            color: TvTheme.primary.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.timer_outlined,
                            color: TvTheme.primaryAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Schedule Program Recording',
                                style: TextStyle(
                                  fontSize: 17,
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
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prog.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat('MMM d, h:mm a').format(prog.startTime)} - ${DateFormat('h:mm a').format(prog.endTime)} (${prog.durationMinutes} min)',
                            style: const TextStyle(
                              color: TvTheme.primaryAccent,
                              fontSize: 13,
                            ),
                          ),
                          if (prog.description != null &&
                              prog.description!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              prog.description!,
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
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pre-roll padding',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                initialValue: preRoll,
                                dropdownColor: TvTheme.surfaceElevated,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.black26,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 0,
                                    child: Text(
                                      'None',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 1,
                                    child: Text(
                                      '1 min',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 2,
                                    child: Text(
                                      '2 min',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 5,
                                    child: Text(
                                      '5 min',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setDialogState(() => preRoll = v ?? 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Post-roll padding',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                initialValue: postRoll,
                                dropdownColor: TvTheme.surfaceElevated,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.black26,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 0,
                                    child: Text(
                                      'None',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 2,
                                    child: Text(
                                      '2 min',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 5,
                                    child: Text(
                                      '5 min',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 10,
                                    child: Text(
                                      '10 min',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setDialogState(() => postRoll = v ?? 5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TvTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await tvState.scheduleProgramRecording(
                              channel,
                              prog,
                              preRoll: preRoll,
                              postRoll: postRoll,
                            );
                            if (context.mounted) {
                              TvToast.success(
                                context,
                                'Scheduled recording for "${prog.title}"',
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Confirm Schedule',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
