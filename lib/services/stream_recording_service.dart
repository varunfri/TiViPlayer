import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'app_platform.dart';
import '../models/recording_item.dart';
import 'database_service.dart';

typedef RecordingProgressCallback =
    void Function(int recordingId, int bytesRecorded);

/// Manages and executes live stream and HLS recordings directly to disk.
class StreamRecordingService {
  static final StreamRecordingService instance = StreamRecordingService._init();
  StreamRecordingService._init();

  final Map<int, _ActiveRecordingJob> _activeJobs = {};
  final DatabaseService _db = DatabaseService.instance;

  // Listeners for recording status changes across UI
  final ValueNotifier<int> activeRecordingsCount = ValueNotifier<int>(0);
  final ValueNotifier<Map<int, int>> activeBytesProgress =
      ValueNotifier<Map<int, int>>({});

  bool isRecordingChannel(int channelId) {
    return _activeJobs.values.any(
      (job) => job.item.channelId == channelId && !job.isStopped,
    );
  }

  RecordingItem? getActiveJobForChannel(int channelId) {
    for (final job in _activeJobs.values) {
      if (job.item.channelId == channelId && !job.isStopped) {
        return job.item;
      }
    }
    return null;
  }

  bool isJobActive(int recordingId) {
    return _activeJobs.containsKey(recordingId) &&
        !_activeJobs[recordingId]!.isStopped;
  }

  /// Resolves the default recording directory
  static Future<Directory> getRecordingsDirectory() async {
    if (AppPlatform.isWeb) {
      return Directory('Recordings');
    }
    final docDir = await getApplicationDocumentsDirectory();
    final recDir = Directory(p.join(docDir.path, 'Recordings'));
    if (!await recDir.exists()) {
      await recDir.create(recursive: true);
    }
    return recDir;
  }

  /// Starts recording a [RecordingItem]. If [item.id] is not yet set in DB, it will be inserted.
  Future<RecordingItem> startRecording(RecordingItem item) async {
    int recordingId = item.id ?? 0;
    RecordingItem currentItem = item;

    // Check if output file path is specified, otherwise generate
    String filePath = item.filePath;
    if (filePath.isEmpty) {
      final recDir = await getRecordingsDirectory();
      final sanitizedChannel = item.channelName.replaceAll(
        RegExp(r'[\\/:*?"<>| ]+'),
        '_',
      );
      final sanitizedTitle = item.programTitle.replaceAll(
        RegExp(r'[\\/:*?"<>| ]+'),
        '_',
      );
      final ts = DateTime.now().millisecondsSinceEpoch;
      filePath = p.join(
        recDir.path,
        '${sanitizedChannel}_${sanitizedTitle}_$ts.ts',
      );
    }

    if (recordingId == 0) {
      currentItem = item.copyWith(
        filePath: filePath,
        status: 'recording',
        createdAt: DateTime.now(),
      );
      recordingId = await _db.insertRecording(currentItem);
      currentItem = currentItem.copyWith(id: recordingId);
    } else {
      currentItem = currentItem.copyWith(
        filePath: filePath,
        status: 'recording',
      );
      await _db.updateRecordingStatus(recordingId, 'recording');
    }

    // Stop any existing job with the same ID
    if (_activeJobs.containsKey(recordingId)) {
      await _activeJobs[recordingId]?.stop();
    }

    final job = _ActiveRecordingJob(
      item: currentItem,
      onProgress: (bytes) {
        _notifyProgress(recordingId, bytes);
      },
      onComplete: (bytes, success, error) async {
        await _handleJobCompletion(recordingId, bytes, success, error);
      },
    );

    _activeJobs[recordingId] = job;
    activeRecordingsCount.value = _activeJobs.length;

    job.start();
    return currentItem;
  }

  /// Stops an ongoing recording job
  Future<void> stopRecording(int recordingId) async {
    final job = _activeJobs[recordingId];
    if (job != null) {
      await job.stop();
      _activeJobs.remove(recordingId);
      activeRecordingsCount.value = _activeJobs.length;

      final updatedProgress = Map<int, int>.from(activeBytesProgress.value);
      updatedProgress.remove(recordingId);
      activeBytesProgress.value = updatedProgress;
    }
  }

  void _notifyProgress(int recordingId, int bytes) {
    final updated = Map<int, int>.from(activeBytesProgress.value);
    updated[recordingId] = bytes;
    activeBytesProgress.value = updated;

    // Persist progress to DB occasionally (debounced via job logic)
    _db.updateRecordingProgress(recordingId, bytes);
  }

  Future<void> _handleJobCompletion(
    int recordingId,
    int bytes,
    bool success,
    String? error,
  ) async {
    final job = _activeJobs.remove(recordingId);
    activeRecordingsCount.value = _activeJobs.length;

    final updated = Map<int, int>.from(activeBytesProgress.value);
    updated.remove(recordingId);
    activeBytesProgress.value = updated;

    final finalStatus = success ? 'completed' : 'failed';
    final filePath = job?.item.filePath ?? '';

    await _db.updateRecordingFileAndStatus(
      recordingId,
      filePath,
      finalStatus,
      bytes,
    );
    debugPrint(
      '[DVR] Recording #$recordingId finished: status=$finalStatus, bytes=$bytes, err=$error',
    );
  }

  /// Cancels all active jobs (e.g., when app terminates)
  Future<void> dispose() async {
    for (final job in _activeJobs.values) {
      await job.stop();
    }
    _activeJobs.clear();
    activeRecordingsCount.value = 0;
    activeBytesProgress.value = {};
  }
}

/// Internal worker handling the network capture loop and file sink
class _ActiveRecordingJob {
  final RecordingItem item;
  final void Function(int bytes) onProgress;
  final void Function(int bytes, bool success, String? error) onComplete;

  bool _isStopped = false;
  bool get isStopped => _isStopped;

  http.Client? _client;
  IOSink? _fileSink;
  int _bytesRecorded = 0;
  Timer? _hlsPollTimer;
  final Set<String> _downloadedSegments = {};
  int _lastProgressSaveBytes = 0;

  static const String _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  _ActiveRecordingJob({
    required this.item,
    required this.onProgress,
    required this.onComplete,
  });

  Future<void> start() async {
    try {
      _client = http.Client();
      final file = File(item.filePath);
      await file.parent.create(recursive: true);
      _fileSink = file.openWrite(mode: FileMode.writeOnlyAppend);

      debugPrint('[DVR] Starting recording to: ${item.filePath}');
      debugPrint('[DVR] Stream URL: ${item.streamUrl}');

      // Detect stream type: inspect initial URL or request response
      await _detectAndStartStream();
    } catch (e, st) {
      debugPrint('[DVR] Error initializing recording: $e\n$st');
      await _finish(false, e.toString());
    }
  }

  Future<void> _detectAndStartStream() async {
    final uri = Uri.parse(item.streamUrl);
    final headers = {
      'User-Agent': _userAgent,
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };

    // First fetch head/initial chunk to see if it's M3U8 or progressive MPEG-TS
    final initialResp = await _client!.get(uri, headers: headers);
    if (initialResp.statusCode != 200) {
      throw Exception(
        'Server returned HTTP ${initialResp.statusCode}: ${initialResp.reasonPhrase}',
      );
    }

    final body = initialResp.body;
    if (body.contains('#EXTM3U')) {
      // It is an HLS playlist
      debugPrint('[DVR] Detected HLS stream. Starting HLS capture engine...');
      await _startHlsCapture(uri, body);
    } else {
      // It is a direct stream (MPEG-TS, progressive video, etc.)
      debugPrint(
        '[DVR] Detected direct progressive stream. Starting streaming capture...',
      );
      // Write already fetched initial bytes
      _fileSink?.add(initialResp.bodyBytes);
      _bytesRecorded += initialResp.bodyBytes.length;
      onProgress(_bytesRecorded);

      // Continue streaming with a StreamedResponse
      await _startDirectStreamCapture(uri, headers);
    }
  }

  /// Direct progressive MPEG-TS / HTTP stream capture
  Future<void> _startDirectStreamCapture(
    Uri uri,
    Map<String, String> headers,
  ) async {
    try {
      final request = http.Request('GET', uri)..headers.addAll(headers);
      final streamedResponse = await _client!.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          'Stream request failed with status: ${streamedResponse.statusCode}',
        );
      }

      await for (final chunk in streamedResponse.stream) {
        if (_isStopped) break;
        _fileSink?.add(chunk);
        _bytesRecorded += chunk.length;

        // Notify progress every ~256KB to avoid flooding the UI thread
        if (_bytesRecorded - _lastProgressSaveBytes >= 256 * 1024) {
          _lastProgressSaveBytes = _bytesRecorded;
          onProgress(_bytesRecorded);
        }
      }

      await _finish(true, null);
    } catch (e) {
      if (!_isStopped) {
        debugPrint('[DVR] Direct stream capture error: $e');
        await _finish(false, e.toString());
      }
    }
  }

  /// HLS capture engine: resolves master/media playlist, polls chunks and appends raw .ts
  Future<void> _startHlsCapture(Uri initialUri, String initialContent) async {
    Uri mediaPlaylistUri = initialUri;

    // Check if initial content is a Master Playlist
    if (initialContent.contains('#EXT-X-STREAM-INF')) {
      final resolvedMediaUri = _resolveMasterPlaylist(
        initialUri,
        initialContent,
      );
      if (resolvedMediaUri != null) {
        mediaPlaylistUri = resolvedMediaUri;
        debugPrint(
          '[DVR] Resolved media playlist from master: $mediaPlaylistUri',
        );
      }
    }

    // Initial fetch of media segments
    await _pollMediaPlaylist(mediaPlaylistUri);

    // Schedule regular polling loop
    _hlsPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_isStopped) {
        timer.cancel();
        return;
      }
      await _pollMediaPlaylist(mediaPlaylistUri);
    });
  }

  Uri? _resolveMasterPlaylist(Uri masterUri, String content) {
    final lines = content.split('\n');
    String? bestVariantUri;
    int highestBandwidth = -1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        // Extract BANDWIDTH attribute
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        final bandwidth = bwMatch != null
            ? int.tryParse(bwMatch.group(1) ?? '0') ?? 0
            : 0;

        // Next line contains the variant URI
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (nextLine.isNotEmpty && !nextLine.startsWith('#')) {
            if (bandwidth >= highestBandwidth) {
              highestBandwidth = bandwidth;
              bestVariantUri = nextLine;
            }
          }
        }
      }
    }

    if (bestVariantUri != null) {
      return masterUri.resolve(bestVariantUri);
    }
    return null;
  }

  Future<void> _pollMediaPlaylist(Uri playlistUri) async {
    if (_isStopped) return;

    try {
      final resp = await _client!.get(
        playlistUri,
        headers: {'User-Agent': _userAgent, 'Accept': '*/*'},
      );

      if (resp.statusCode != 200) {
        debugPrint(
          '[DVR] Warning: HLS playlist poll returned status ${resp.statusCode}',
        );
        return;
      }

      final lines = resp.body.split('\n');
      final List<Uri> segmentsToDownload = [];

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#EXTINF:')) {
          // Find following segment URL
          for (int j = i + 1; j < lines.length; j++) {
            final next = lines[j].trim();
            if (next.isEmpty || next.startsWith('#')) continue;
            final segmentUri = playlistUri.resolve(next);
            segmentsToDownload.add(segmentUri);
            break;
          }
        }
      }

      // Download any new segments
      for (final segUri in segmentsToDownload) {
        if (_isStopped) break;
        final segKey = segUri.toString();

        if (!_downloadedSegments.contains(segKey)) {
          _downloadedSegments.add(segKey);

          // Keep segment history set memory bounded
          if (_downloadedSegments.length > 500) {
            _downloadedSegments.remove(_downloadedSegments.first);
          }

          final segResp = await _client!.get(
            segUri,
            headers: {'User-Agent': _userAgent, 'Accept': '*/*'},
          );

          if (segResp.statusCode == 200 && !_isStopped) {
            _fileSink?.add(segResp.bodyBytes);
            _bytesRecorded += segResp.bodyBytes.length;

            if (_bytesRecorded - _lastProgressSaveBytes >= 128 * 1024) {
              _lastProgressSaveBytes = _bytesRecorded;
              onProgress(_bytesRecorded);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DVR] Error during HLS poll: $e');
    }
  }

  Future<void> stop() async {
    if (_isStopped) return;
    _isStopped = true;
    _hlsPollTimer?.cancel();
    _hlsPollTimer = null;
    await _finish(true, null);
  }

  Future<void> _finish(bool success, String? error) async {
    try {
      await _fileSink?.flush();
      await _fileSink?.close();
      _fileSink = null;
    } catch (_) {}

    try {
      _client?.close();
      _client = null;
    } catch (_) {}

    onProgress(_bytesRecorded);
    onComplete(_bytesRecorded, success, error);
  }
}
