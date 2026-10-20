import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Diagnostic probe result from inspecting raw HLS manifest headers.
class HlsProbeResult {
  final bool isVod;
  final Duration? totalDuration;
  final int? targetDurationSeconds;
  final int? mediaSequence;
  final bool hasEndList;
  final String? playlistType;

  const HlsProbeResult({
    required this.isVod,
    this.totalDuration,
    this.targetDurationSeconds,
    this.mediaSequence,
    this.hasEndList = false,
    this.playlistType,
  });

  bool get isLive => !isVod;

  @override
  String toString() =>
      'HlsProbeResult(isVod: $isVod, duration: $totalDuration, targetDur: $targetDurationSeconds, endList: $hasEndList, type: $playlistType)';
}

class HlsManifestProber {
  static const Map<String, String> _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
    'Accept': '*/*',
  };

  static final http.Client _client = http.Client();

  /// Probes an HLS stream URL by fetching and parsing the manifest headers.
  /// Follows Master Playlist variants down to the first Media Playlist if needed.
  /// Streams at most 32 KB to avoid downloading large media files (e.g. MP4/TS).
  static Future<HlsProbeResult> probeStream(
    String streamUrl, {
    Map<String, String>? customHeaders,
    int maxRedirects = 3,
  }) async {
    try {
      final uri = Uri.parse(streamUrl);
      if (!uri.hasScheme || !uri.scheme.startsWith('http')) {
        return const HlsProbeResult(isVod: true);
      }

      final lowerUrl = streamUrl.toLowerCase();
      // Fast path: if the URL directly indicates a media container file, it cannot be an HLS manifest
      if (lowerUrl.contains('.mp4') ||
          lowerUrl.contains('.mkv') ||
          lowerUrl.contains('.avi') ||
          lowerUrl.contains('.mov') ||
          lowerUrl.contains('.wmv') ||
          lowerUrl.contains('.flv')) {
        return const HlsProbeResult(isVod: true);
      }

      final headers = {
        ..._defaultHeaders,
        ...?customHeaders,
        'Range': 'bytes=0-32767',
      };

      final request = http.Request('GET', uri)
        ..headers.addAll(headers)
        ..followRedirects = true
        ..maxRedirects = maxRedirects;

      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: 4));

      if (streamedResponse.statusCode < 200 ||
          streamedResponse.statusCode >= 400) {
        streamedResponse.stream.listen((_) {}).cancel();
        return const HlsProbeResult(isVod: true);
      }

      final contentType =
          streamedResponse.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.startsWith('video/') ||
          contentType.startsWith('audio/') ||
          contentType.contains('mp4') ||
          contentType.contains('octet-stream')) {
        // Definitely binary media data, not an HLS text manifest
        streamedResponse.stream.listen((_) {}).cancel();
        return const HlsProbeResult(isVod: true);
      }

      // Read at most 32 KB from the stream to verify #EXTM3U without buffering entire files
      final bytesBuilder = BytesBuilder();
      int totalBytes = 0;
      await for (final chunk in streamedResponse.stream) {
        bytesBuilder.add(chunk);
        totalBytes += chunk.length;
        if (totalBytes >= 32768) break;
      }

      final content = utf8.decode(bytesBuilder.toBytes(), allowMalformed: true);

      // Verify if valid HLS manifest
      if (!content.contains('#EXTM3U')) {
        return const HlsProbeResult(isVod: true);
      }

      // Check if this is a Master Playlist containing variants (#EXT-X-STREAM-INF)
      if (content.contains('#EXT-X-STREAM-INF') && maxRedirects > 0) {
        final variantUrl = _extractFirstVariantUrl(uri, content);
        if (variantUrl != null && variantUrl != streamUrl) {
          return await probeStream(
            variantUrl,
            customHeaders: customHeaders,
            maxRedirects: maxRedirects - 1,
          );
        }
      }

      // Analyze Media Playlist Manifest Tags
      return parseMediaPlaylist(content);
    } catch (e) {
      debugPrint(
        '[HlsManifestProber] Manifest probing error on $streamUrl: $e',
      );
      return const HlsProbeResult(isVod: true);
    }
  }

  /// Evaluates an HLS Media Playlist according to RFC 8216.
  static HlsProbeResult parseMediaPlaylist(String manifestContent) {
    bool hasEndList = manifestContent.contains('#EXT-X-ENDLIST');
    String? playlistType;
    int? targetDuration;
    int? mediaSequence;
    double calculatedDurationSeconds = 0.0;

    final lines = const LineSplitter().convert(manifestContent);

    for (final rawLine in lines) {
      final line = rawLine.trim();

      // Check #EXT-X-PLAYLIST-TYPE (e.g. VOD or EVENT)
      if (line.toUpperCase().startsWith('#EXT-X-PLAYLIST-TYPE:')) {
        playlistType = line.split(':')[1].trim().toUpperCase();
      }

      // Check #EXT-X-TARGETDURATION:<s>
      if (line.toUpperCase().startsWith('#EXT-X-TARGETDURATION:')) {
        targetDuration = int.tryParse(line.split(':')[1].trim());
      }

      // Check #EXT-X-MEDIA-SEQUENCE:<seq>
      if (line.toUpperCase().startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        mediaSequence = int.tryParse(line.split(':')[1].trim());
      }

      // Accumulate individual chunk lengths for total VOD duration
      if (line.toUpperCase().startsWith('#EXTINF:')) {
        final match = RegExp(
          r'^#EXTINF:\s*([0-9.]+)',
          caseSensitive: false,
        ).firstMatch(line);
        if (match != null) {
          final segDuration = double.tryParse(match.group(1) ?? '0') ?? 0.0;
          calculatedDurationSeconds += segDuration;
        }
      }
    }

    // RFC 8216 Section 4.3.3.5 & 4.3.4.4 Rules:
    // If Global #EXT-X-PLAYLIST-TYPE:VOD is not available, consider it as a VOD (not as LIVE),
    // unless the stream is explicitly an active rolling broadcast (e.g. #EXT-X-MEDIA-SEQUENCE > 0
    // or #EXT-X-PLAYLIST-TYPE:EVENT without #EXT-X-ENDLIST).
    final isExplicitLive =
        (playlistType == 'EVENT' && !hasEndList) ||
        (mediaSequence != null && mediaSequence > 0 && !hasEndList);

    final isVod = playlistType == 'VOD' || hasEndList || !isExplicitLive;

    return HlsProbeResult(
      isVod: isVod,
      hasEndList: hasEndList,
      playlistType: playlistType,
      targetDurationSeconds: targetDuration,
      mediaSequence: mediaSequence,
      totalDuration: isVod && calculatedDurationSeconds > 0
          ? Duration(milliseconds: (calculatedDurationSeconds * 1000).round())
          : null,
    );
  }

  /// Resolves relative or absolute URI for the first variant stream in a Master Playlist.
  static String? _extractFirstVariantUrl(Uri baseUri, String masterContent) {
    final lines = const LineSplitter().convert(masterContent);
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#EXT-X-STREAM-INF') && i + 1 < lines.length) {
        final targetLine = lines[i + 1].trim();
        if (targetLine.startsWith('http://') ||
            targetLine.startsWith('https://')) {
          return targetLine;
        } else if (!targetLine.startsWith('#') && targetLine.isNotEmpty) {
          return baseUri.resolve(targetLine).toString();
        }
      }
    }
    return null;
  }
}
