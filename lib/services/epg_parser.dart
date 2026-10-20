import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/epg_program.dart';
import 'app_platform.dart';

class EpgFetchResult {
  final List<EpgProgram> programs;
  final String effectiveUrlOrPath;

  const EpgFetchResult({
    required this.programs,
    required this.effectiveUrlOrPath,
  });
}

/// High-performance, fault-tolerant XMLTV Electronic Program Guide (EPG) parser.
/// Supports both plain XML and GZip-compressed (.gz / .xml.gz) EPG feeds from remote URLs
/// or local files, with tolerant unescaped entity handling and smart 404 URL auto-recovery.
class EpgParser {
  /// Strips whitespace, surrounding quotes, and backticks from input URLs
  static String sanitizeUrl(String raw) {
    var s = raw.trim();
    while (s.startsWith('"') || s.startsWith("'") || s.startsWith('`')) {
      s = s.substring(1).trim();
    }
    while (s.endsWith('"') || s.endsWith("'") || s.endsWith('`')) {
      s = s.substring(0, s.length - 1).trim();
    }
    return s;
  }

  /// Generates sensible fallback candidate URLs if the primary EPG URL returns 404
  static List<String> getUrlCandidates(String originalUrl) {
    final sanitized = sanitizeUrl(originalUrl);
    if (sanitized.isEmpty) return [];

    final list = <String>[sanitized];

    void addCandidate(String c) {
      final s = c.trim();
      if (s.isNotEmpty && !list.contains(s)) {
        list.add(s);
      }
    }

    // 1. If ends with .xml (without .gz), try appending .gz
    if (sanitized.toLowerCase().endsWith('.xml')) {
      addCandidate('$sanitized.gz');
    }
    // 2. If ends with .xml.gz, try without .gz
    else if (sanitized.toLowerCase().endsWith('.xml.gz')) {
      addCandidate(sanitized.substring(0, sanitized.length - 3));
    }
    // 3. If ends with .gz (like epg.gz), try .xml.gz and without .gz
    else if (sanitized.toLowerCase().endsWith('.gz')) {
      final base = sanitized.substring(0, sanitized.length - 3);
      addCandidate(base);
      addCandidate('$base.xml.gz');
    }
    // 4. If path ends with /epg or /xmltv, probe common standard suffixes
    else if (sanitized.toLowerCase().endsWith('/epg')) {
      addCandidate('$sanitized.xml.gz');
      addCandidate('$sanitized.xml');
    } else if (sanitized.toLowerCase().endsWith('/xmltv')) {
      addCandidate('$sanitized.xml.gz');
      addCandidate('$sanitized.xml');
    }

    // 5. Protocol swaps (http <-> https)
    final protoVariants = <String>[];
    for (final c in list) {
      if (c.startsWith('http://')) {
        protoVariants.add('https://${c.substring(7)}');
      } else if (c.startsWith('https://')) {
        protoVariants.add('http://${c.substring(8)}');
      }
    }
    for (final pv in protoVariants) {
      addCandidate(pv);
    }

    return list;
  }

  /// Extracts embedded EPG URLs from M3U header tags (url-tvg or x-tvg-url)
  static String? extractEpgUrlFromM3u(String m3uContent) {
    final firstLines = m3uContent.split('\n').take(30).join('\n');
    final match = RegExp(
      r'(?:url-tvg|x-tvg-url)=["\x27]?([^"\x27\s,]+)["\x27]?',
      caseSensitive: false,
    ).firstMatch(firstLines);
    final raw = match?.group(1);
    return raw != null ? sanitizeUrl(raw) : null;
  }

  /// Fetches EPG from a remote URL or reads from a local file path,
  /// automatically decompressing gzip if needed, and returns parsed EpgPrograms.
  static Future<List<EpgProgram>> fetchAndParseEpg(String urlOrPath) async {
    final result = await fetchAndParseEpgWithResult(urlOrPath);
    return result.programs;
  }

  /// Fetches EPG and also returns the effective URL or path that succeeded.
  static Future<EpgFetchResult> fetchAndParseEpgWithResult(String urlOrPath) async {
    final sanitized = sanitizeUrl(urlOrPath);
    if (sanitized.isEmpty) {
      return const EpgFetchResult(programs: [], effectiveUrlOrPath: '');
    }

    Uint8List rawBytes;
    String effectivePath = sanitized;

    if (sanitized.startsWith('http://') || sanitized.startsWith('https://')) {
      final candidates = getUrlCandidates(sanitized);
      http.Response? successfulResponse;
      String workingUrl = sanitized;
      String lastErrorStatus = '';

      for (final candidate in candidates) {
        try {
          final uri = Uri.parse(candidate);
          final response = await http.get(
            uri,
            headers: {
              'User-Agent': 'TiviMate/5.1.0 (Android TV; Linux; OKHttp/5.4.0)',
              'Accept': '*/*',
              'Accept-Encoding': 'gzip, deflate',
            },
          ).timeout(const Duration(seconds: 40));

          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            successfulResponse = response;
            workingUrl = candidate;
            if (candidate != sanitized) {
              debugPrint('[EpgParser] Auto-recovered from 404 using fallback URL: $candidate');
            }
            break;
          } else {
            lastErrorStatus = 'HTTP ${response.statusCode}';
            debugPrint('[EpgParser] Candidate failed ($candidate): ${response.statusCode}');
          }
        } catch (e) {
          lastErrorStatus = '$e';
          debugPrint('[EpgParser] Candidate network error ($candidate): $e');
        }
      }

      if (successfulResponse == null) {
        throw Exception(
          'EPG download failed ($lastErrorStatus) for "$sanitized". '
          'Please verify the EPG server is reachable and ends with .xml or .xml.gz.',
        );
      }

      rawBytes = successfulResponse.bodyBytes;
      effectivePath = workingUrl;
    } else {
      if (AppPlatform.isWeb) {
        throw Exception('Local file paths are not supported on Web. Please provide an HTTP/HTTPS EPG URL.');
      }
      final file = File(sanitized);
      if (!await file.exists()) {
        throw Exception('Local EPG file not found: $sanitized');
      }
      rawBytes = await file.readAsBytes();
    }

    // Auto-detect GZip compression by extension or magic header bytes (0x1F 0x8B)
    final xmlContent = decompressIfNeeded(rawBytes, effectivePath);
    final programs = parseXmlTv(xmlContent);
    return EpgFetchResult(programs: programs, effectiveUrlOrPath: effectivePath);
  }

  /// Auto-detects and decompresses GZip bytes if needed, returning the UTF-8 XML string.
  static String decompressIfNeeded(List<int> rawBytes, [String? pathOrUrl]) {
    final isGzip = (rawBytes.length >= 2 && rawBytes[0] == 0x1F && rawBytes[1] == 0x8B) ||
        (pathOrUrl != null && pathOrUrl.toLowerCase().endsWith('.gz'));

    if (isGzip) {
      try {
        final decompressed = GZipDecoder().decodeBytes(rawBytes);
        return utf8.decode(decompressed, allowMalformed: true);
      } catch (e) {
        debugPrint('[EpgParser] GZip decompression fallback: $e');
        return utf8.decode(rawBytes, allowMalformed: true);
      }
    } else {
      return utf8.decode(rawBytes, allowMalformed: true);
    }
  }

  /// Parses XMLTV format string into a list of EpgProgram items.
  /// Uses a streaming regex scanner that is resilient against IPTV unescaped XML entities.
  static List<EpgProgram> parseXmlTv(String xml) {
    final List<EpgProgram> programs = [];

    // Match <programme ...>...</programme> or self-closing <programme .../>
    final programmeRegex = RegExp(
      r'<programme\s+([^>]+)>(.*?)</programme>|<programme\s+([^>]+)/>',
      dotAll: true,
      caseSensitive: false,
    );

    final titleRegex = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false);
    final descRegex = RegExp(r'<desc[^>]*>(.*?)</desc>', dotAll: true, caseSensitive: false);
    final catRegex = RegExp(r'<category[^>]*>(.*?)</category>', dotAll: true, caseSensitive: false);

    final attrChannelRegex = RegExp(r'channel=["\x27]([^"\x27]+)["\x27]', caseSensitive: false);
    final attrStartRegex = RegExp(r'start=["\x27]([^"\x27]+)["\x27]', caseSensitive: false);
    final attrStopRegex = RegExp(r'stop=["\x27]([^"\x27]+)["\x27]', caseSensitive: false);

    final matches = programmeRegex.allMatches(xml);

    for (final m in matches) {
      final attrs = m.group(1) ?? m.group(3) ?? '';
      final body = m.group(2) ?? '';

      final channelMatch = attrChannelRegex.firstMatch(attrs);
      final startMatch = attrStartRegex.firstMatch(attrs);
      final stopMatch = attrStopRegex.firstMatch(attrs);

      if (channelMatch == null || startMatch == null || stopMatch == null) {
        continue;
      }

      final channelId = channelMatch.group(1)?.trim();
      final startRaw = startMatch.group(1)?.trim();
      final stopRaw = stopMatch.group(1)?.trim();

      if (channelId == null || channelId.isEmpty || startRaw == null || stopRaw == null) {
        continue;
      }

      final startTime = parseXmlTvDate(startRaw);
      final stopTime = parseXmlTvDate(stopRaw);

      if (startTime == null || stopTime == null) continue;

      String title = 'Program';
      final titleMatch = titleRegex.firstMatch(body);
      if (titleMatch != null) {
        title = _unescapeXml(titleMatch.group(1)!.trim());
      }

      String? desc;
      final descMatch = descRegex.firstMatch(body);
      if (descMatch != null) {
        desc = _unescapeXml(descMatch.group(1)!.trim());
      }

      String? category;
      final catMatch = catRegex.firstMatch(body);
      if (catMatch != null) {
        category = _unescapeXml(catMatch.group(1)!.trim());
      }

      programs.add(EpgProgram(
        channelTvgId: channelId,
        title: title,
        description: desc,
        startTime: startTime,
        endTime: stopTime,
        category: category,
      ));
    }

    return programs;
  }

  /// Converts standard XMLTV datetime string into local DateTime object.
  /// Formats handled:
  ///   - 20261016020000 +0000
  ///   - 20261016020000 -0400
  ///   - 20261016020000
  ///   - 202610160200
  ///   - ISO8601 (2026-10-16T02:00:00Z)
  static DateTime? parseXmlTvDate(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return null;

    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(?:(\d{2}))?(?:\s*([+-]\d{4}))?',
    ).firstMatch(cleaned);

    if (match != null) {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final hour = int.parse(match.group(4)!);
      final minute = int.parse(match.group(5)!);
      final second = match.group(6) != null ? int.parse(match.group(6)!) : 0;
      final tz = match.group(7);

      DateTime dt = DateTime.utc(year, month, day, hour, minute, second);

      if (tz != null && tz.length == 5) {
        final isNegative = tz[0] == '-';
        final tzHours = int.tryParse(tz.substring(1, 3)) ?? 0;
        final tzMins = int.tryParse(tz.substring(3, 5)) ?? 0;
        final totalMinutes = tzHours * 60 + tzMins;
        if (isNegative) {
          dt = dt.add(Duration(minutes: totalMinutes));
        } else {
          dt = dt.subtract(Duration(minutes: totalMinutes));
        }
      }
      return dt.toLocal();
    }

    return DateTime.tryParse(cleaned)?.toLocal();
  }

  static String _unescapeXml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .trim();
  }
}
