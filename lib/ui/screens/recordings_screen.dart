import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/channel.dart';
import '../../models/recording_item.dart';
import '../../providers/tv_state_provider.dart';
import '../../ui/theme.dart';
import '../widgets/tv_toast.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  String _selectedTab = 'all'; // 'all', 'completed', 'recording', 'scheduled'
  List<RecordingItem> _recordings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    setState(() => _isLoading = true);
    final tvState = context.read<TvStateProvider>();
    final items = await tvState.fetchAllRecordings();
    if (mounted) {
      setState(() {
        _recordings = items;
        _isLoading = false;
      });
    }
  }

  List<RecordingItem> get _filteredRecordings {
    if (_selectedTab == 'all') return _recordings;
    return _recordings.where((r) => r.status == _selectedTab).toList();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double dBytes = bytes.toDouble();
    while (dBytes >= 1024 && i < suffixes.length - 1) {
      dBytes /= 1024;
      i++;
    }
    return '${dBytes.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final tvState = context.watch<TvStateProvider>();
    final timeFormat = DateFormat('MMM d, h:mm a');
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 40,
        vertical: isMobile ? 18 : 30,
      ),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxWidth: 1000,
          maxHeight: math.min(size.height - 32, 720),
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
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.fiber_smart_record_rounded,
                                color: Colors.redAccent,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'DVR & Stream Recordings',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '${_recordings.length} total items',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: TvTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.refresh_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                              tooltip: 'Refresh',
                              onPressed: _loadRecordings,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                              tooltip: 'Close',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'all',
                                label: Text('All', style: TextStyle(fontSize: 11)),
                              ),
                              ButtonSegment(
                                value: 'recording',
                                label: Text('Active (REC)', style: TextStyle(fontSize: 11)),
                              ),
                              ButtonSegment(
                                value: 'completed',
                                label: Text('Completed', style: TextStyle(fontSize: 11)),
                              ),
                              ButtonSegment(
                                value: 'scheduled',
                                label: Text('Scheduled', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                            selected: {_selectedTab},
                            onSelectionChanged: (val) {
                              setState(() => _selectedTab = val.first);
                            },
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.resolveWith((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return TvTheme.primary;
                                }
                                return Colors.transparent;
                              }),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.fiber_smart_record_rounded,
                            color: Colors.redAccent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DVR & Stream Recordings',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_recordings.length} total recorded & scheduled programs',
                              style: const TextStyle(
                                fontSize: 12,
                                color: TvTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // Filter Tabs
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'all', label: Text('All')),
                            ButtonSegment(
                              value: 'recording',
                              label: Text('Active (REC)'),
                            ),
                            ButtonSegment(
                              value: 'completed',
                              label: Text('Completed'),
                            ),
                            ButtonSegment(
                              value: 'scheduled',
                              label: Text('Scheduled'),
                            ),
                          ],
                          selected: {_selectedTab},
                          onSelectionChanged: (val) {
                            setState(() => _selectedTab = val.first);
                          },
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return TvTheme.primary;
                              }
                              return Colors.transparent;
                            }),
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white70,
                          ),
                          tooltip: 'Refresh list',
                          onPressed: _loadRecordings,
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

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: TvTheme.primary),
                    )
                  : _filteredRecordings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.video_library_outlined,
                            size: 64,
                            color: TvTheme.borderSubtle,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No ${_selectedTab == 'all' ? '' : _selectedTab} recordings found',
                            style: const TextStyle(
                              fontSize: 16,
                              color: TvTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'You can record active broadcasts from the player OSD or schedule future programs from the TV Guide.',
                            style: TextStyle(
                              fontSize: 12,
                              color: TvTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.all(isMobile ? 12 : 20),
                      itemCount: _filteredRecordings.length,
                      separatorBuilder: (_, _) => SizedBox(height: isMobile ? 8 : 12),
                      itemBuilder: (context, index) {
                        final item = _filteredRecordings[index];
                        return _buildRecordingCard(
                          context,
                          item,
                          tvState,
                          timeFormat,
                          isMobile,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingCard(
    BuildContext context,
    RecordingItem item,
    TvStateProvider tvState,
    DateFormat timeFormat,
    bool isMobile,
  ) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (item.status) {
      case 'recording':
        statusColor = Colors.redAccent;
        statusLabel = 'RECORDING';
        statusIcon = Icons.fiber_manual_record_rounded;
        break;
      case 'completed':
        statusColor = Colors.greenAccent;
        statusLabel = 'COMPLETED';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'scheduled':
        statusColor = Colors.amberAccent;
        statusLabel = 'SCHEDULED';
        statusIcon = Icons.alarm_rounded;
        break;
      case 'cancelled':
        statusColor = Colors.white54;
        statusLabel = 'CANCELLED';
        statusIcon = Icons.cancel_outlined;
        break;
      default:
        statusColor = Colors.red;
        statusLabel = 'FAILED';
        statusIcon = Icons.error_outline_rounded;
    }

    final bytes = item.isRecording && item.id != null
        ? (tvState.currentChannelBytesRecorded > 0
              ? tvState.currentChannelBytesRecorded
              : item.bytesRecorded)
        : item.bytesRecorded;

    final logoWidget = Container(
      width: isMobile ? 42 : 50,
      height: isMobile ? 42 : 50,
      decoration: BoxDecoration(
        color: TvTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: item.channelLogo != null
          ? Image.network(
              item.channelLogo!,
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
    );

    final detailsWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: statusColor.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 11, color: statusColor),
                  const SizedBox(width: 4),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.channelName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: TvTheme.primaryAccent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          item.programTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Flexible(
              child: Text(
                '${timeFormat.format(item.startTime)} - ${DateFormat('h:mm a').format(item.endTime)} (${item.duration.inMinutes}m)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                ),
              ),
            ),
            if (bytes > 0) ...[
              const SizedBox(width: 8),
              Container(
                width: 3,
                height: 3,
                decoration: const BoxDecoration(
                  color: TvTheme.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatBytes(bytes),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
            ],
          ],
        ),
      ],
    );

    final actionsWidget = Row(
      mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: isMobile ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (item.isCompleted) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: TvTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              final channelToPlay = Channel(
                id: item.channelId,
                playlistId: 0,
                groupId: 0,
                channelNumber: 0,
                name: '[REC] ${item.programTitle}',
                streamUrl: item.filePath,
                logoUrl: item.channelLogo,
              );
              tvState.playChannel(channelToPlay);
              TvToast.success(
                context,
                'Playing recorded show: ${item.programTitle}',
              );
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('Watch', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
        ],

        if (item.isRecording) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              await tvState.stopActiveChannelRecording();
              await _loadRecordings();
            },
            icon: const Icon(Icons.stop_rounded, size: 16),
            label: const Text('Stop', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
        ],

        if (item.isScheduled) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: TvTheme.borderSubtle),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              if (item.id != null) {
                await tvState.cancelRecording(item.id!);
                await _loadRecordings();
              }
            },
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
        ],

        IconButton(
          tooltip: 'Delete recording and file',
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.white54,
            size: 20,
          ),
          onPressed: () => _confirmDelete(context, item, tvState),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isRecording
              ? Colors.redAccent.withValues(alpha: 0.6)
              : TvTheme.borderSubtle,
          width: item.isRecording ? 1.5 : 1.0,
        ),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    logoWidget,
                    const SizedBox(width: 12),
                    Expanded(child: detailsWidget),
                  ],
                ),
                const SizedBox(height: 8),
                actionsWidget,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                logoWidget,
                const SizedBox(width: 16),
                Expanded(child: detailsWidget),
                const SizedBox(width: 16),
                actionsWidget,
              ],
            ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    RecordingItem item,
    TvStateProvider tvState,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TvTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: TvTheme.borderSubtle),
        ),
        title: const Text(
          'Delete Recording?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${item.programTitle}"? The recorded video file on disk will be permanently removed.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await tvState.deleteRecording(item);
              await _loadRecordings();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
