import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/channel.dart';

class XtreamService {
  final String serverUrl;
  final String username;
  final String password;

  XtreamService({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  String get _cleanServerUrl {
    var url = serverUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }

  String get epgUrl =>
      '$_cleanServerUrl/xmltv.php?username=$username&password=$password';

  Future<bool> authenticate() async {
    try {
      final uri = Uri.parse(
        '$_cleanServerUrl/player_api.php?username=$username&password=$password',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data is Map && data['user_info'] != null) {
          final auth = data['user_info']['auth'];
          return auth == 1 || auth == '1';
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, List<Channel>>> fetchLiveStreams() async {
    // 1. Fetch Categories
    final catUri = Uri.parse(
      '$_cleanServerUrl/player_api.php?username=$username&password=$password&action=get_live_categories',
    );
    final catRes = await http.get(catUri).timeout(const Duration(seconds: 20));
    final Map<String, String> categoryNames = {};

    if (catRes.statusCode == 200) {
      final catData = json.decode(catRes.body);
      if (catData is List) {
        for (final item in catData) {
          final catId = item['category_id']?.toString() ?? '';
          final catName = item['category_name']?.toString() ?? 'General';
          if (catId.isNotEmpty) {
            categoryNames[catId] = catName;
          }
        }
      }
    }

    // 2. Fetch Streams
    final streamUri = Uri.parse(
      '$_cleanServerUrl/player_api.php?username=$username&password=$password&action=get_live_streams',
    );
    final streamRes = await http
        .get(streamUri)
        .timeout(const Duration(seconds: 30));
    final Map<String, List<Channel>> groupedChannels = {};

    if (streamRes.statusCode == 200) {
      final streamData = json.decode(streamRes.body);
      if (streamData is List) {
        int index = 1;
        for (final item in streamData) {
          final streamId = item['stream_id']?.toString() ?? '';
          final name = item['name']?.toString() ?? 'Channel $index';
          final catId = item['category_id']?.toString() ?? '';
          final logo = item['stream_icon']?.toString();
          final tvgId = item['epg_channel_id']?.toString();
          final groupName = categoryNames[catId] ?? 'All Channels';

          final streamUrl =
              '$_cleanServerUrl/live/$username/$password/$streamId.ts';

          final channel = Channel(
            playlistId: 1,
            groupId: 0,
            channelNumber: item['num'] is int ? item['num'] : index++,
            name: name,
            streamUrl: streamUrl,
            logoUrl: (logo != null && logo.isNotEmpty) ? logo : null,
            tvgId: tvgId,
          );

          groupedChannels.putIfAbsent(groupName, () => []).add(channel);
        }
      }
    }

    return groupedChannels;
  }
}
