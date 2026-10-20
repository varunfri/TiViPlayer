import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:tv_player_app/main.dart';
import 'package:tv_player_app/models/channel.dart';
import 'package:tv_player_app/providers/tv_state_provider.dart';
import 'package:tv_player_app/services/database_service.dart';
import 'package:tv_player_app/ui/screens/stream_settings_dialog.dart';
import 'package:tv_player_app/ui/screens/tv_home_screen.dart';
import 'package:tv_player_app/ui/widgets/video_player_widget.dart';
import 'package:tv_player_app/ui/widgets/player_controls_osd.dart';
import 'package:tv_player_app/services/playlist_parser.dart';
import 'package:tv_player_app/services/hls_manifest_prober.dart';

void main() {
  testWidgets('App initialization smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => TvStateProvider())],
        child: const TiviPlayerApp(),
      ),
    );
    expect(find.byType(TiviPlayerApp), findsOneWidget);
  });

  testWidgets('StreamSettingsDialog displays Video Quality tab by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [ChangeNotifierProvider(create: (_) => TvStateProvider())],
          child: const Scaffold(body: StreamSettingsDialog()),
        ),
      ),
    );

    // Verify dialog header
    expect(find.text('Stream & Playback Settings'), findsOneWidget);

    // Verify tab buttons
    expect(find.text('Video Quality'), findsOneWidget);
    expect(find.text('Aspect Ratio'), findsOneWidget);
    expect(find.text('Audio Tracks'), findsOneWidget);

    // When activePlayer is null (in unit test environment), verify inactive state is shown
    expect(find.text('Player inactive or stream not started.'), findsOneWidget);

    // Switch to Aspect Ratio tab
    await tester.tap(find.text('Aspect Ratio'));
    await tester.pump();

    // Verify aspect ratio content is displayed
    expect(find.text('SELECT DISPLAY FRAMING'), findsOneWidget);
    expect(find.text('Contain (Original)'), findsOneWidget);
  });

  test('TvStateProvider toggles isPlaying properly', () {
    final tvState = TvStateProvider();
    expect(tvState.isPlaying, isTrue);
    tvState.togglePlayPause();
    expect(tvState.isPlaying, isFalse);
    tvState.togglePlayPause();
    expect(tvState.isPlaying, isTrue);
  });

  test(
    'TvStateProvider persists player settings (volume, scale, buffer, speed, view mode)',
    () {
      final tvState = TvStateProvider();
      tvState.setVolume(0.75);
      expect(tvState.volume, 0.75);
      expect(tvState.persistedSettings['volume'], '0.75');

      tvState.setScaleMode(VideoScaleMode.sixteenNine);
      expect(tvState.scaleMode, VideoScaleMode.sixteenNine);
      expect(
        tvState.persistedSettings['video_scale_mode'],
        VideoScaleMode.sixteenNine.name,
      );

      tvState.setBufferSize(64 * 1024 * 1024);
      expect(tvState.bufferSizeBytes, 64 * 1024 * 1024);
      expect(
        tvState.persistedSettings['buffer_size_bytes'],
        (64 * 1024 * 1024).toString(),
      );

      tvState.setViewMode(TvViewMode.epgGrid);
      expect(tvState.viewMode, TvViewMode.epgGrid);
      expect(tvState.persistedSettings['view_mode'], TvViewMode.epgGrid.name);

      tvState.setPlaybackRate(1.25);
      expect(tvState.playbackRate, 1.25);
      expect(tvState.persistedSettings['playback_rate'], '1.25');

      tvState.toggleMute();
      expect(tvState.isMuted, isTrue);
      expect(tvState.persistedSettings['is_muted'], '1');
    },
  );

  test(
    'TvStateProvider persists last played channel and group details for resume',
    () {
      final tvState = TvStateProvider();

      final channel = Channel(
        id: 42,
        playlistId: 1,
        groupId: 10,
        channelNumber: 101,
        name: 'BBC News HD',
        streamUrl: 'https://example.com/bbc.m3u8',
      );

      tvState.playChannel(channel);

      expect(tvState.activePlayingChannel?.id, 42);
      expect(tvState.persistedSettings['last_channel_id'], '42');
      expect(tvState.persistedSettings['last_channel_name'], 'BBC News HD');
      expect(
        tvState.persistedSettings['last_channel_stream_url'],
        'https://example.com/bbc.m3u8',
      );
    },
  );

  test('TvStateProvider persists group and favorites filter selection', () {
    final tvState = TvStateProvider();

    tvState.toggleFavoritesFilter();
    expect(tvState.isFavoritesOnly, isTrue);
    expect(tvState.persistedSettings['is_favorites_only'], '1');

    tvState.toggleFavoritesFilter();
    expect(tvState.isFavoritesOnly, isFalse);
    expect(tvState.persistedSettings['is_favorites_only'], '0');
  });

  test('DatabaseService persists and retrieves settings in SQLite', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async => '.',
        );

    final db = DatabaseService.instance;
    await db.saveSetting('test_resume_channel', '101');
    final val = await db.getSetting('test_resume_channel');
    expect(val, '101');

    await db.saveSettings({'p1': 'v1', 'p2': 'v2'});
    final all = await db.getAllSettings();
    expect(all['p1'], 'v1');
    expect(all['p2'], 'v2');

    await db.deleteSetting('test_resume_channel');
    expect(await db.getSetting('test_resume_channel'), isNull);

    await db.deleteSettingsWithPrefix('p');
    final after = await db.getAllSettings();
    expect(after.containsKey('p1'), isFalse);
    expect(after.containsKey('p2'), isFalse);
  });

  testWidgets('VideoPlayerWidget accepts onErrorChanged callback', (
    WidgetTester tester,
  ) async {
    bool hasErrorReceived = false;
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => TvStateProvider())],
        child: MaterialApp(
          home: Scaffold(
            body: VideoPlayerWidget(
              channel: null,
              onErrorChanged: (val) {
                hasErrorReceived = val;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.byType(VideoPlayerWidget), findsOneWidget);
    expect(hasErrorReceived, isFalse);
  });

  test('TvStateProvider VOD stream detection and duration calculations', () {
    final tvState = TvStateProvider();

    // Default state: no playback duration
    expect(tvState.isVodStream, isFalse);
    expect(tvState.playbackProgressFraction, 0.0);
    expect(tvState.playbackBufferFraction, 0.0);

    // Update with positive media duration (e.g., 1 hour 45 min movie)
    tvState.updatePlaybackProgress(
      position: const Duration(minutes: 30, seconds: 15),
      duration: const Duration(hours: 1, minutes: 45),
      buffer: const Duration(minutes: 40),
    );

    expect(tvState.isVodStream, isTrue);
    expect(tvState.formattedPlaybackPosition, '00:30:15');
    expect(tvState.formattedPlaybackDuration, '01:45:00');
    expect(tvState.formattedPlaybackRemaining, '-01:14:45');

    // Expected progress fraction: (30*60 + 15) / (105*60) = 1815 / 6300 ≈ 0.288
    expect(tvState.playbackProgressFraction, closeTo(0.288, 0.005));
    // Expected buffer fraction: (40*60) / (105*60) = 2400 / 6300 ≈ 0.3809
    expect(tvState.playbackBufferFraction, closeTo(0.381, 0.005));

    // Reset progress returns to zero
    tvState.resetPlaybackProgress();
    expect(tvState.playbackPosition, Duration.zero);
    expect(tvState.playbackDuration, Duration.zero);
    expect(tvState.isVodStream, isFalse);
  });

  test('TvStateProvider VOD detection via channel metadata fallback', () {
    final tvState = TvStateProvider();

    // VOD stream URL ending with .mp4
    final vodChannel = Channel(
      id: 99,
      playlistId: 1,
      groupId: 2,
      channelNumber: 1,
      name: 'Interstellar',
      streamUrl: 'https://example.com/vod/interstellar.mp4',
    );
    tvState.playChannel(vodChannel);
    expect(tvState.isVodStream, isTrue);

    // Live stream without VOD indicators
    final liveChannel = Channel(
      id: 100,
      playlistId: 1,
      groupId: 3,
      channelNumber: 2,
      name: 'Sky Sports F1',
      streamUrl: 'https://example.com/live/f1.m3u8',
    );
    tvState.playChannel(liveChannel);
    expect(tvState.isVodStream, isFalse);
    tvState.dispose();
  });

  test(
    'TvStateProvider seekTo and seekRelative invoke registered seek callback',
    () async {
      final tvState = TvStateProvider();
      Duration? seekTarget;

      tvState.registerSeekCallback((target) async {
        seekTarget = target;
      });

      tvState.updatePlaybackProgress(
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 300),
      );

      await tvState.seekTo(const Duration(seconds: 120));
      expect(seekTarget, const Duration(seconds: 120));
      expect(tvState.playbackPosition, const Duration(seconds: 120));

      // Seek relative +10s
      await tvState.seekRelative(const Duration(seconds: 10));
      expect(seekTarget, const Duration(seconds: 130));
      expect(tvState.playbackPosition, const Duration(seconds: 130));

      // Seek relative -20s
      await tvState.seekRelative(const Duration(seconds: -20));
      expect(seekTarget, const Duration(seconds: 110));
      expect(tvState.playbackPosition, const Duration(seconds: 110));

      // Seek relative past 0 clamps to 0
      await tvState.seekRelative(const Duration(seconds: -200));
      expect(seekTarget, Duration.zero);
      expect(tvState.playbackPosition, Duration.zero);
      tvState.dispose();
    },
  );

  testWidgets(
    'PlayerControlsOsd renders VOD badge, slider, and timestamps for VOD stream',
    (WidgetTester tester) async {
      final tvState = TvStateProvider();

      final channel = Channel(
        id: 1,
        playlistId: 1,
        groupId: 1,
        channelNumber: 1,
        name: 'The Matrix (1999)',
        streamUrl: 'https://example.com/vod/matrix.mkv',
      );

      tvState.updatePlaybackProgress(
        position: const Duration(hours: 1, minutes: 15),
        duration: const Duration(hours: 2, minutes: 16),
        buffer: const Duration(hours: 1, minutes: 30),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControlsOsd(
              channel: channel,
              currentProgram: null,
              tvState: tvState,
              onOpenGuide: () {},
            ),
          ),
        ),
      );

      // Verify VOD badge is displayed
      expect(find.text('VOD'), findsWidgets);

      // Verify progress slider is rendered
      expect(find.byType(Slider), findsOneWidget);

      // Verify timestamp labels are rendered
      expect(find.text('01:15:00'), findsOneWidget);
      expect(find.text('02:16:00'), findsOneWidget);

      // Verify Rewind 10 and Forward 10 buttons are present
      expect(find.byIcon(Icons.replay_10_rounded), findsWidgets);
      expect(find.byIcon(Icons.forward_10_rounded), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      tvState.dispose();
    },
  );

  test('PlaylistParser Live vs VOD stream classification rules', () {
    // 1. Duration < 0 (Live broadcast)
    expect(
      PlaylistParser.classifyIsLive(
        duration: -1,
        groupTitle: 'General',
        title: 'BBC One',
        streamUrl: 'https://example.com/live/bbc1.m3u8',
      ),
      isTrue,
    );

    // 2. Duration < 0 with explicit Live group
    expect(
      PlaylistParser.classifyIsLive(
        duration: -1,
        groupTitle: 'Live Sports',
        title: 'Sky Sports F1',
        streamUrl: 'https://example.com/live/f1.m3u8',
      ),
      isTrue,
    );

    // 3. Duration == 0 with VOD group title -> VOD
    expect(
      PlaylistParser.classifyIsLive(
        duration: 0,
        groupTitle: 'Movies',
        title: 'Interstellar (2014)',
        streamUrl: 'https://example.com/stream/interstellar',
      ),
      isFalse,
    );

    // 4. Positive duration (> 0) -> VOD
    expect(
      PlaylistParser.classifyIsLive(
        duration: 7200,
        groupTitle: 'Drama',
        title: 'Inception',
        streamUrl: 'https://example.com/movie/inception.m3u8',
      ),
      isFalse,
    );

    // 5. Container extension (.mp4, .mkv) -> VOD
    expect(
      PlaylistParser.classifyIsLive(
        duration: -1,
        groupTitle: 'General',
        title: 'Sample Video',
        streamUrl: 'https://example.com/files/video.mp4',
      ),
      isFalse,
    );

    // 6. Global playlist VOD directive overrides
    expect(
      PlaylistParser.classifyIsLive(
        duration: -1,
        groupTitle: 'News',
        title: 'Archive Broadcast',
        streamUrl: 'https://example.com/archive.m3u8',
        playlistIsVod: true,
      ),
      isFalse,
    );
  });

  test(
    'PlaylistParser parseM3uWithMetadata correctly assigns isLive and duration',
    () {
      const sampleM3u = '''#EXTM3U
#EXTINF:-1 group-title="News" tvg-id="cnn_hd",CNN International
https://example.com/live/cnn.m3u8
#EXTINF:0 group-title="Movies" tvg-id="vod_1",Inception
https://example.com/vod/inception.m3u8
#EXTINF:5400 group-title="Cinema" tvg-id="vod_2",The Dark Knight
https://example.com/stream/dark_knight
''';

      final bundle = PlaylistParser.parseM3uWithMetadata(sampleM3u);
      expect(bundle.groups.containsKey('News'), isTrue);
      expect(bundle.groups.containsKey('Movies'), isTrue);
      expect(bundle.groups.containsKey('Cinema'), isTrue);

      final cnn = bundle.groups['News']!.first;
      expect(cnn.isLive, isTrue);
      expect(cnn.isVod, isFalse);
      expect(cnn.durationSeconds, isNull);

      final inception = bundle.groups['Movies']!.first;
      expect(inception.isLive, isFalse);
      expect(inception.isVod, isTrue);
      expect(inception.durationSeconds, 0);

      final tdk = bundle.groups['Cinema']!.first;
      expect(tdk.isLive, isFalse);
      expect(tdk.isVod, isTrue);
      expect(tdk.durationSeconds, 5400);
    },
  );

  test('HlsManifestProber classifies RFC 8216 VOD vs Live streams', () async {
    // 1. Resilient probe on unreachable or non-HLS URL defaults to VOD
    final probe = await HlsManifestProber.probeStream(
      'https://example.com/invalid.m3u8',
    );
    expect(probe.isVod, isTrue);
    expect(probe.isLive, isFalse);

    // 2. VOD manifest with #EXT-X-PLAYLIST-TYPE:VOD and #EXT-X-ENDLIST
    const vodManifest = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:10.0,
segment1.ts
#EXTINF:9.5,
segment2.ts
#EXT-X-ENDLIST
''';

    expect(vodManifest.contains('#EXT-X-PLAYLIST-TYPE:VOD'), isTrue);
    expect(vodManifest.contains('#EXT-X-ENDLIST'), isTrue);

    // 3. Manifest where Global #EXT-X-PLAYLIST-TYPE:VOD is NOT available -> considered VOD
    const noGlobalVodTagManifest = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXTINF:10.0,
segment1.ts
#EXTINF:10.0,
segment2.ts
''';
    expect(
      noGlobalVodTagManifest.contains('#EXT-X-PLAYLIST-TYPE:VOD'),
      isFalse,
    );
    final noVodTagResult = HlsManifestProber.parseMediaPlaylist(
      noGlobalVodTagManifest,
    );
    expect(noVodTagResult.isVod, isTrue);
    expect(noVodTagResult.isLive, isFalse);

    // 4. Live sliding window manifest with #EXT-X-MEDIA-SEQUENCE and no #EXT-X-ENDLIST
    const liveManifest = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:1050
#EXTINF:6.0,
live1050.ts
#EXTINF:6.0,
live1051.ts
''';

    expect(liveManifest.contains('#EXT-X-MEDIA-SEQUENCE'), isTrue);
    expect(liveManifest.contains('#EXT-X-ENDLIST'), isFalse);
    final liveResult = HlsManifestProber.parseMediaPlaylist(liveManifest);
    expect(liveResult.isVod, isFalse);
    expect(liveResult.isLive, isTrue);
  });

  test(
    'TvStateProvider dynamically updates when manifest probe determines stream type',
    () {
      final tvState = TvStateProvider();

      // Default live channel without duration
      final channel = Channel(
        id: 55,
        playlistId: 1,
        groupId: 1,
        channelNumber: 55,
        name: 'Channel 55',
        streamUrl: 'https://example.com/stream/55.m3u8',
        isLive: true,
      );
      tvState.playChannel(channel);
      expect(tvState.isVodStream, isFalse);

      // Manifest probe discovers #EXT-X-PLAYLIST-TYPE:VOD
      tvState.setManifestStreamType(
        isVod: true,
        probedDuration: const Duration(hours: 1, minutes: 30),
      );
      expect(tvState.isVodStream, isTrue);
      expect(tvState.playbackDuration, const Duration(hours: 1, minutes: 30));

      // Manifest probe discovers live rolling window (#EXT-X-MEDIA-SEQUENCE)
      tvState.setManifestStreamType(isVod: false);
      expect(tvState.isVodStream, isFalse);

      tvState.dispose();
    },
  );

  testWidgets('TvHomeScreen handles keyboard shortcuts without double-firing', (
    WidgetTester tester,
  ) async {
    final tvState = TvStateProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: tvState)],
        child: const MaterialApp(home: TvHomeScreen()),
      ),
    );

    // Verify Space toggles play/pause once
    final initialPlaying = tvState.isPlaying;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(tvState.isPlaying, !initialPlaying);

    // Verify M toggles mute once
    final initialMute = tvState.isMuted;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    expect(tvState.isMuted, !initialMute);

    // Verify C toggles bottom channel drawer once
    final initialDrawer = tvState.showBottomChannelList;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    expect(tvState.showBottomChannelList, !initialDrawer);

    // Advance past sqflite internal transaction timeout timers
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpWidget(const SizedBox());
    tvState.dispose();
  });

  test(
    'HlsManifestProber fast-paths direct media files (.mp4/.mkv) directly as VOD',
    () async {
      final mp4Probe = await HlsManifestProber.probeStream(
        'https://varun.myddns.me:8000/teleplay/stream/4.mp4',
      );
      expect(mp4Probe.isVod, isTrue);
      expect(mp4Probe.isLive, isFalse);

      final mkvProbe = await HlsManifestProber.probeStream(
        'https://varun.myddns.me:8000/teleplay/movie.mkv',
      );
      expect(mkvProbe.isVod, isTrue);
      expect(mkvProbe.isLive, isFalse);
    },
  );
}
