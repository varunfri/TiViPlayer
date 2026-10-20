import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/recording_item.dart';
import 'database_service.dart';
import 'stream_recording_service.dart';

/// Coordinates scheduled recording timers, pre-roll/post-roll triggers,
/// and automated termination of completed jobs.
class RecordingScheduler {
  static final RecordingScheduler instance = RecordingScheduler._init();
  RecordingScheduler._init();

  final DatabaseService _db = DatabaseService.instance;
  final StreamRecordingService _streamRecorder = StreamRecordingService.instance;

  Timer? _schedulerTimer;
  bool _isChecking = false;

  /// Initializes the scheduler, repairs stale recordings from previous runs, and starts heartbeat.
  Future<void> initialize() async {
    await _recoverStaleRecordings();
    _startSchedulerHeartbeat();
  }

  void _startSchedulerHeartbeat() {
    _schedulerTimer?.cancel();
    _schedulerTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      checkAndTriggerScheduledRecordings();
    });
  }

  /// Recovers any recordings that were interrupted by app termination
  Future<void> _recoverStaleRecordings() async {
    try {
      final activeOrScheduled = await _db.getActiveOrScheduledRecordings();
      final now = DateTime.now();

      for (final item in activeOrScheduled) {
        if (item.id == null) continue;

        if (item.status == 'recording') {
          // App restarted while recording was marked active
          final file = File(item.filePath);
          final exists = await file.exists();
          final bytes = exists ? await file.length() : 0;

          if (bytes > 0) {
            await _db.updateRecordingFileAndStatus(item.id!, item.filePath, 'completed', bytes);
          } else {
            await _db.updateRecordingStatus(item.id!, 'failed');
          }
        } else if (item.status == 'scheduled' && now.isAfter(item.effectiveEndTime)) {
          // Missed schedule
          await _db.updateRecordingStatus(item.id!, 'failed');
        }
      }
    } catch (e) {
      debugPrint('[Scheduler] Error recovering stale recordings: $e');
    }
  }

  /// Checks DB for any programs due to start or finish
  Future<void> checkAndTriggerScheduledRecordings() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      final activeOrScheduled = await _db.getActiveOrScheduledRecordings();
      final now = DateTime.now();

      for (final item in activeOrScheduled) {
        if (item.id == null) continue;

        // Check 1: Scheduled items that need to start
        if (item.status == 'scheduled') {
          if (now.isAfter(item.effectiveStartTime) && now.isBefore(item.effectiveEndTime)) {
            debugPrint('[Scheduler] Triggering scheduled recording: "${item.programTitle}" on ${item.channelName}');
            await _streamRecorder.startRecording(item);
          } else if (now.isAfter(item.effectiveEndTime)) {
            // Already past end time, mark failed/missed
            await _db.updateRecordingStatus(item.id!, 'failed');
          }
        }

        // Check 2: Active items that have reached their effective end time
        if (item.status == 'recording' && _streamRecorder.isJobActive(item.id!)) {
          if (now.isAfter(item.effectiveEndTime)) {
            debugPrint('[Scheduler] Ending completed recording: "${item.programTitle}" on ${item.channelName}');
            await _streamRecorder.stopRecording(item.id!);
          }
        }
      }
    } catch (e) {
      debugPrint('[Scheduler] Heartbeat error: $e');
    } finally {
      _isChecking = false;
    }
  }

  /// Starts an instant recording for the currently playing channel
  Future<RecordingItem> startInstantRecording({
    required Channel channel,
    EpgProgram? currentProgram,
    Duration duration = const Duration(minutes: 60),
  }) async {
    final now = DateTime.now();
    final endTime = currentProgram != null && currentProgram.endTime.isAfter(now)
        ? currentProgram.endTime
        : now.add(duration);

    final title = currentProgram?.title ?? 'Live Recording (${channel.name})';
    final desc = currentProgram?.description;

    final item = RecordingItem(
      channelId: channel.id ?? 0,
      channelName: channel.name,
      channelLogo: channel.logoUrl,
      streamUrl: channel.streamUrl,
      programTitle: title,
      programDescription: desc,
      startTime: now,
      endTime: endTime,
      preRollMinutes: 0,
      postRollMinutes: 0,
      filePath: '',
      status: 'recording',
      createdAt: now,
    );

    return await _streamRecorder.startRecording(item);
  }

  /// Stops instant recording on a specific channel
  Future<void> stopRecordingForChannel(int channelId) async {
    final activeJob = _streamRecorder.getActiveJobForChannel(channelId);
    if (activeJob?.id != null) {
      await _streamRecorder.stopRecording(activeJob!.id!);
    }
  }

  /// Schedules a future program recording
  Future<RecordingItem> scheduleProgramRecording({
    required Channel channel,
    required EpgProgram program,
    int preRollMinutes = 2,
    int postRollMinutes = 5,
  }) async {
    final now = DateTime.now();
    final item = RecordingItem(
      channelId: channel.id ?? 0,
      channelName: channel.name,
      channelLogo: channel.logoUrl,
      streamUrl: channel.streamUrl,
      programTitle: program.title,
      programDescription: program.description,
      startTime: program.startTime,
      endTime: program.endTime,
      preRollMinutes: preRollMinutes,
      postRollMinutes: postRollMinutes,
      filePath: '',
      status: 'scheduled',
      createdAt: now,
    );

    final id = await _db.insertRecording(item);
    final savedItem = item.copyWith(id: id);

    // If start time is already due, start immediately
    if (now.isAfter(savedItem.effectiveStartTime) && now.isBefore(savedItem.effectiveEndTime)) {
      await _streamRecorder.startRecording(savedItem);
    }

    return savedItem;
  }

  /// Cancels a scheduled or active recording
  Future<void> cancelRecording(int recordingId) async {
    if (_streamRecorder.isJobActive(recordingId)) {
      await _streamRecorder.stopRecording(recordingId);
    }
    await _db.updateRecordingStatus(recordingId, 'cancelled');
  }

  /// Completely deletes a recording entry and removes the .ts file from disk
  Future<void> deleteRecordingWithFile(RecordingItem item) async {
    if (item.id != null) {
      if (_streamRecorder.isJobActive(item.id!)) {
        await _streamRecorder.stopRecording(item.id!);
      }
      await _db.deleteRecording(item.id!);
    }

    if (item.filePath.isNotEmpty) {
      final file = File(item.filePath);
      if (await file.exists()) {
        try {
          await file.delete();
          debugPrint('[DVR] Deleted file: ${item.filePath}');
        } catch (e) {
          debugPrint('[DVR] Could not delete recording file: $e');
        }
      }
    }
  }

  void dispose() {
    _schedulerTimer?.cancel();
    _streamRecorder.dispose();
  }
}
