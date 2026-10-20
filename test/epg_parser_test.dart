import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_player_app/models/channel.dart';
import 'package:tv_player_app/services/epg_parser.dart';
import 'package:tv_player_app/services/playlist_parser.dart';

void main() {
  group('EpgParser Tests', () {
    test('parses standard XMLTV with timezone offsets and entities', () {
      const xmltvSample = '''<?xml version="1.0" encoding="UTF-8"?>
<tv generator-info-name="TestGenerator">
  <channel id="cnn.us">
    <display-name>CNN USA</display-name>
  </channel>
  <programme start="20261016120000 +0000" stop="20261016130000 +0000" channel="cnn.us">
    <title lang="en">CNN Newsroom &amp; Live Updates</title>
    <desc lang="en">Breaking news &amp; analysis from around the globe.</desc>
  </programme>
  <programme start="20261016130000 +0530" stop="20261016140000 +0530" channel="cnn.us">
    <title>The Situation Room with Wolf Blitzer</title>
    <desc>Happenings in Washington D.C.</desc>
  </programme>
</tv>''';

      final programs = EpgParser.parseXmlTv(xmltvSample);
      expect(programs.length, 2);

      final p1 = programs[0];
      expect(p1.channelTvgId, 'cnn.us');
      expect(p1.title, 'CNN Newsroom & Live Updates');
      expect(p1.description, 'Breaking news & analysis from around the globe.');
      expect(p1.startTime.toUtc(), DateTime.utc(2026, 10, 16, 12, 0, 0));
      expect(p1.endTime.toUtc(), DateTime.utc(2026, 10, 16, 13, 0, 0));

      final p2 = programs[1];
      expect(p2.channelTvgId, 'cnn.us');
      expect(p2.title, 'The Situation Room with Wolf Blitzer');
      // 13:00 +0530 = 07:30 UTC
      expect(p2.startTime.toUtc(), DateTime.utc(2026, 10, 16, 7, 30, 0));
    });

    test(
      'parses fault-tolerant XMLTV with unescaped ampersands and quotes',
      () {
        const dirtyXmltv = '''
<tv>
  <programme start="20261016180000" stop="20261016190000" channel="sports.1">
    <title>Football: Real Madrid & Barcelona Live</title>
    <desc>El Clásico live coverage > HD stream</desc>
  </programme>
</tv>''';

        final programs = EpgParser.parseXmlTv(dirtyXmltv);
        expect(programs.length, 1);
        expect(programs.first.title, 'Football: Real Madrid & Barcelona Live');
        expect(programs.first.channelTvgId, 'sports.1');
      },
    );

    test('decompresses gzip XMLTV byte stream', () {
      const xmltvSample = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <programme start="20261016100000 +0000" stop="20261016110000 +0000" channel="discovery.hd">
    <title>MythBusters</title>
    <desc>Explosive science experiments.</desc>
  </programme>
</tv>''';

      final uncompressedBytes = utf8.encode(xmltvSample);
      final compressedBytes = gzip.encode(uncompressedBytes);

      final decompressedString = EpgParser.decompressIfNeeded(compressedBytes);
      final programs = EpgParser.parseXmlTv(decompressedString);

      expect(programs.length, 1);
      expect(programs.first.title, 'MythBusters');
      expect(programs.first.channelTvgId, 'discovery.hd');
    });
  });

  group('M3U Header & EPG Extraction Tests', () {
    test('extracts url-tvg from M3U header', () {
      const m3uWithUrlTvg = '''#EXTM3U url-tvg="https://iptv-epg.org/epg.xml.gz"
#EXTINF:-1 tvg-id="bbc1.uk" tvg-name="BBC One" group-title="UK",BBC One HD
http://stream.example.com/live/bbc1.m3u8''';

      final bundle = PlaylistParser.parseM3uWithMetadata(m3uWithUrlTvg);
      expect(bundle.epgUrl, 'https://iptv-epg.org/epg.xml.gz');
      expect(bundle.groups['UK']?.length, 1);
      expect(bundle.groups['UK']?.first.tvgId, 'bbc1.uk');
      expect(bundle.groups['UK']?.first.name, 'BBC One HD');
    });

    test('extracts x-tvg-url from M3U header', () {
      const m3uWithXTvgUrl =
          '''#EXTM3U x-tvg-url="http://xmltv.myprovider.net/guide.xml"
#EXTINF:-1 tvg-name="CNN" group-title="News",CNN News
http://stream.example.com/live/cnn.m3u8''';

      final bundle = PlaylistParser.parseM3uWithMetadata(m3uWithXTvgUrl);
      expect(bundle.epgUrl, 'http://xmltv.myprovider.net/guide.xml');
      expect(bundle.groups['News']?.length, 1);
      // tvg-id fallback to tvg-name
      expect(bundle.groups['News']?.first.tvgId, 'CNN');
    });

    test(
      'generates accurate webPlayerUrl and inAppWebPlayerUrl for JioTV Go and other channels',
      () {
        final ch = Channel(
          playlistId: 1,
          groupId: 1,
          channelNumber: 760,
          name: 'Maa Movies HD',
          streamUrl: 'https://varun.myddns.me:5000/live/mpd/760',
          tvgId: '760',
          drmType: 'com.widevine.alpha',
        );
        expect(ch.webPlayerUrl, 'https://varun.myddns.me:5000/play/760');
        expect(
          ch.inAppWebPlayerUrl,
          'https://varun.myddns.me:5000/mpd/760?q=auto&pm=hd',
        );
        expect(ch.hasDrm, true);

        final ch2 = Channel(
          playlistId: 1,
          groupId: 1,
          channelNumber: 151,
          name: 'Movies Now HD',
          streamUrl: 'https://varun.myddns.me:5000/live/mpd/151',
        );
        expect(ch2.webPlayerUrl, 'https://varun.myddns.me:5000/play/151');
        expect(
          ch2.inAppWebPlayerUrl,
          'https://varun.myddns.me:5000/mpd/151?q=auto&pm=hd',
        );
      },
    );
  });
}
