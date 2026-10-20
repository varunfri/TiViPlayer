import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/channel.dart';
import '../models/epg_program.dart';
import 'epg_parser.dart';

class ParsedPlaylistBundle {
  final Map<String, List<Channel>> groups;
  final String? epgUrl;

  const ParsedPlaylistBundle({
    required this.groups,
    this.epgUrl,
  });
}

class PlaylistParser {
  static Future<Map<String, List<Channel>>> parseM3uFromUrl(String url) async {
    final bundle = await parseM3uBundleFromUrl(url);
    return bundle.groups;
  }

  static Future<ParsedPlaylistBundle> parseM3uBundleFromUrl(String url) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent': 'TiviMate/5.1.0 (Android TV; Linux; OKHttp/5.4.0)',
        'Accept': '*/*',
      },
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode == 200) {
      return parseM3uWithMetadata(utf8.decode(response.bodyBytes));
    } else {
      throw Exception('Failed to load playlist: HTTP ${response.statusCode}');
    }
  }

  static Future<Map<String, List<Channel>>> parseM3uFromFile(String filePath) async {
    final bundle = await parseM3uBundleFromFile(filePath);
    return bundle.groups;
  }

  static Future<ParsedPlaylistBundle> parseM3uBundleFromFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    return parseM3uWithMetadata(content);
  }

  static Map<String, List<Channel>> parseM3uFromBytes(Uint8List bytes) {
    return parseM3uWithMetadata(utf8.decode(bytes)).groups;
  }

  static Map<String, List<Channel>> parseM3uContent(String content) {
    return parseM3uWithMetadata(content).groups;
  }

  static ParsedPlaylistBundle parseM3uWithMetadata(String content) {
    final Map<String, List<Channel>> groups = {};
    final lines = LineSplitter.split(content).toList();
    String? headerEpgUrl;

    String currentName = '';
    String? currentLogo;
    String? currentTvgId;
    String currentGroup = 'General';
    String? currentDrmType;
    String? currentDrmLicenseUrl;
    String? currentDrmHeaders;
    int channelIndex = 1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.toUpperCase().startsWith('#EXTM3U')) {
        final match = RegExp(
          r'(?:url-tvg|x-tvg-url)=["\x27]?([^"\x27\s,]+)["\x27]?',
          caseSensitive: false,
        ).firstMatch(line);
        final raw = match?.group(1);
        headerEpgUrl = raw != null ? EpgParser.sanitizeUrl(raw) : null;
        continue;
      }

      if (line.startsWith('#EXTINF:')) {
        // Extract group-title
        final groupMatch = RegExp(r'group-title="([^"]+)"', caseSensitive: false).firstMatch(line);
        currentGroup = groupMatch?.group(1)?.trim() ?? 'General';

        // Extract tvg-logo
        final logoMatch = RegExp(r'tvg-logo="([^"]+)"', caseSensitive: false).firstMatch(line);
        currentLogo = logoMatch?.group(1)?.trim();

        // Extract tvg-id (with tvg-name fallback)
        final idMatch = RegExp(r'tvg-id="([^"]+)"', caseSensitive: false).firstMatch(line);
        currentTvgId = idMatch?.group(1)?.trim();
        if (currentTvgId == null || currentTvgId.isEmpty) {
          final nameMatch = RegExp(r'tvg-name="([^"]+)"', caseSensitive: false).firstMatch(line);
          currentTvgId = nameMatch?.group(1)?.trim();
        }

        // Extract channel name (after the last comma)
        final commaIndex = line.lastIndexOf(',');
        if (commaIndex != -1 && commaIndex < line.length - 1) {
          currentName = line.substring(commaIndex + 1).trim();
        } else {
          currentName = 'Channel $channelIndex';
        }
      } else if (line.toUpperCase().startsWith('#KODIPROP:')) {
        // Extract Kodi InputStream.adaptive DRM directives
        final propContent = line.substring(10).trim();
        if (propContent.startsWith('inputstream.adaptive.license_type=')) {
          final rawType = propContent.split('=')[1].trim().toLowerCase();
          if (rawType.contains('widevine')) {
            currentDrmType = 'widevine';
          } else if (rawType.contains('playready')) {
            currentDrmType = 'playready';
          } else if (rawType.contains('clearkey')) {
            currentDrmType = 'clearkey';
          } else {
            currentDrmType = rawType;
          }
        } else if (propContent.startsWith('inputstream.adaptive.license_key=')) {
          final rawKey = propContent.substring('inputstream.adaptive.license_key='.length).trim();
          // Check if headers are piped (URL|Header1=Val1&Header2=Val2)
          if (rawKey.contains('|')) {
            final parts = rawKey.split('|');
            currentDrmLicenseUrl = parts[0].trim();
            final headerParams = parts.sublist(1).join('|').split('&');
            final Map<String, String> headersMap = {};
            for (final param in headerParams) {
              final kv = param.split('=');
              if (kv.length == 2) {
                headersMap[kv[0].trim()] = Uri.decodeComponent(kv[1].trim());
              }
            }
            if (headersMap.isNotEmpty) {
              currentDrmHeaders = jsonEncode(headersMap);
            }
          } else {
            currentDrmLicenseUrl = rawKey;
          }
        }
      } else if (!line.startsWith('#')) {
        // It's a stream URL
        if (line.startsWith('http://') || line.startsWith('https://') || line.startsWith('rtmp://')) {
          final channel = Channel(
            playlistId: 1,
            groupId: 0,
            channelNumber: channelIndex++,
            name: currentName.isNotEmpty ? currentName : 'Channel $channelIndex',
            streamUrl: line,
            logoUrl: currentLogo,
            tvgId: currentTvgId ?? currentName.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
            drmType: currentDrmType,
            drmLicenseUrl: currentDrmLicenseUrl,
            drmHeaders: currentDrmHeaders,
          );

          groups.putIfAbsent(currentGroup, () => []).add(channel);
        }

        // Reset state for next channel
        currentName = '';
        currentLogo = null;
        currentTvgId = null;
        currentGroup = 'General';
        currentDrmType = null;
        currentDrmLicenseUrl = null;
        currentDrmHeaders = null;
      }
    }

    return ParsedPlaylistBundle(
      groups: groups,
      epgUrl: headerEpgUrl,
    );
  }

  /// Built-in verified high-quality public live streams for instant testing and demonstration
  static Map<String, List<Channel>> getDemoPlaylists() {
    return {
      'News': [
        Channel(
          playlistId: 1,
          groupId: 1,
          channelNumber: 1,
          name: 'DW News English',
          streamUrl: 'https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8',
          logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/7/75/Deutsche_Welle_logo.svg/320px-Deutsche_Welle_logo.svg.png',
          tvgId: 'dw_news',
        ),
        Channel(
          playlistId: 1,
          groupId: 1,
          channelNumber: 2,
          name: 'France 24 English',
          streamUrl: 'https://static.france24.com/live/F24_EN_HI_HLS/live_tv.m3u8',
          logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/8/87/France_24_logo.svg/320px-France_24_logo.svg.png',
          tvgId: 'france_24',
        ),
        Channel(
          playlistId: 1,
          groupId: 1,
          channelNumber: 3,
          name: 'TRT World HD',
          streamUrl: 'https://tv-trtworld.medya.trt.com.tr/master.m3u8',
          logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/TRT_World_logo.svg/320px-TRT_World_logo.svg.png',
          tvgId: 'trt_world',
        ),
      ],
      'Science & Space': [
        Channel(
          playlistId: 1,
          groupId: 2,
          channelNumber: 4,
          name: 'NASA TV Live HD',
          streamUrl: 'https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8',
          logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e5/NASA_logo.svg/320px-NASA_logo.svg.png',
          tvgId: 'nasa_tv',
        ),
      ],
      'Sports & Lifestyle': [
        Channel(
          playlistId: 1,
          groupId: 3,
          channelNumber: 5,
          name: 'Red Bull TV Live',
          streamUrl: 'https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8',
          logoUrl: 'https://upload.wikimedia.org/wikipedia/en/thumb/f/f5/Red_Bull_TV_logo.svg/320px-Red_Bull_TV_logo.svg.png',
          tvgId: 'redbull_tv',
        ),
      ],
      'Movies & Cinema': [
        Channel(
          playlistId: 1,
          groupId: 4,
          channelNumber: 6,
          name: 'Big Buck Bunny HD',
          streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
          logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c5/Big_buck_bunny_poster_big.jpg/320px-Big_buck_bunny_poster_big.jpg',
          tvgId: 'bbb_cinema',
        ),
        Channel(
          playlistId: 1,
          groupId: 4,
          channelNumber: 7,
          name: 'Tears of Steel Sci-Fi',
          streamUrl: 'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8',
          logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/01/Tears_of_Steel_poster.jpg/320px-Tears_of_Steel_poster.jpg',
          tvgId: 'tears_steel',
        ),
      ],
    };
  }

  /// Generates demo EPG schedule around current time for built-in channels
  static List<EpgProgram> generateDemoEpg() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final List<EpgProgram> programs = [];

    final scheduleMap = {
      'dw_news': [
        ('DW News Hour', 'In-depth reporting from Germany, Europe, and global correspondents.'),
        ('Conflict Zone: The Interview', 'Hard-hitting political interviews with global leaders.'),
        ('Eco Africa: Environmental Stories', 'Innovative green tech and conservation projects in Africa.'),
        ('Made in Germany: Industry & Tech', 'German engineering, automotive transition and enterprise.'),
      ],
      'sky_news': [
        ('Sky News Live Bulletin', 'Breaking international news, real-time alerts and financial analysis.'),
        ('Global Political Hour', 'In-depth analysis of government policy, trade summits and elections.'),
        ('World Sports Report', 'Highlights and live coverage from football, cricket and tennis.'),
        ('Tech & Future Trends', 'Silicon Valley insights, AI transformation and green energy.'),
      ],
      'trt_world': [
        ('The Newsmakers', 'Hard-hitting debate program delving into headline international stories.'),
        ('Roundtable Discussions', 'Academics and foreign diplomats break down geopolitical shifts.'),
        ('Off the Grid: Feature Documentary', 'Investigative reporters travel into global conflict zones.'),
        ('Beyond the Game: Sports Digest', 'Inspiring athlete profiles and championship previews.'),
      ],
      'nasa_tv': [
        ('ISS Space Station Live Earth Views', 'Real-time high definition video downlink from the orbital laboratory.'),
        ('Artemis Lunar Mission Briefing', 'Engineers explain Space Launch System avionics and capsule tests.'),
        ('Hubble & Webb Telescope Discoveries', 'Astronomers unveil deep field exoplanet spectral analyses.'),
        ('Astronaut Training & Spacewalk Prep', 'Neutral Buoyancy Lab underwater simulations at Johnson Space Center.'),
      ],
      'redbull_tv': [
        ('Red Bull Rampage: Downhill MTB', 'Extreme freeride mountain biking competition in the Utah canyons.'),
        ('Formula 1: Trackside Tech Talk', 'Aerodynamics breakdown of ground-effect floors and tire wear.'),
        ('Surf Odyssey: Nazaré Giant Waves', 'Big-wave surfers conquer 80-foot swells in Portugal.'),
        ('Red Bull Dance Your Style Finals', 'Street dancers battle in global knockout competition.'),
      ],
      'bbb_cinema': [
        ('Big Buck Bunny: Feature Animation', 'Classic open-source computer-animated comedy film by Blender Foundation.'),
        ('Open Movie Special: Blender Pipeline', 'Behind-the-scenes 3D rendering and rigging workflow showcase.'),
        ('CGI Showcase: Fur & Physics Simulation', 'Deep dive into rendering techniques for digital animation.'),
        ('Short Film Marathon', 'Award-winning computer animated short movies from international creators.'),
      ],
      'tears_steel': [
        ('Tears of Steel: VFX Sci-Fi Thriller', 'Dystopian science fiction open-movie filmed in Amsterdam with live-action CGI.'),
        ('VFX Breakdown: Amsterdam Future', 'Visual effects artists show motion tracking and 3D composites.'),
        ('Cybernetics & Synthetics: Behind the Lore', 'The story and conceptual art behind the machine apocalypse.'),
        ('Cinema Masterclass: Color Grading & Audio', 'Cinematographers discuss 4K mastering and Dolby sound design.'),
      ],
    };

    for (final entry in scheduleMap.entries) {
      final tvgId = entry.key;
      final showList = entry.value;

      // Create 2-hour blocks starting from 6 hours ago to 18 hours in the future
      for (int i = 0; i < 12; i++) {
        final start = today.add(Duration(hours: (now.hour - 4) + (i * 2)));
        final end = start.add(const Duration(hours: 2));
        final show = showList[i % showList.length];

        programs.add(EpgProgram(
          channelTvgId: tvgId,
          title: show.$1,
          description: show.$2,
          startTime: start,
          endTime: end,
          category: 'Broadcast',
        ));
      }
    }

    return programs;
  }
}
