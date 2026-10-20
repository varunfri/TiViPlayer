import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:tv_player_app/main.dart';
import 'package:tv_player_app/models/channel.dart';
import 'package:tv_player_app/providers/tv_state_provider.dart';
import 'package:tv_player_app/services/database_service.dart';
import 'package:tv_player_app/ui/screens/stream_settings_dialog.dart';

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

  test('TvStateProvider persists player settings (volume, scale, buffer, speed, view mode)', () {
    final tvState = TvStateProvider();
    tvState.setVolume(0.75);
    expect(tvState.volume, 0.75);
    expect(tvState.persistedSettings['volume'], '0.75');

    tvState.setScaleMode(VideoScaleMode.sixteenNine);
    expect(tvState.scaleMode, VideoScaleMode.sixteenNine);
    expect(tvState.persistedSettings['video_scale_mode'], VideoScaleMode.sixteenNine.name);

    tvState.setBufferSize(64 * 1024 * 1024);
    expect(tvState.bufferSizeBytes, 64 * 1024 * 1024);
    expect(tvState.persistedSettings['buffer_size_bytes'], (64 * 1024 * 1024).toString());

    tvState.setViewMode(TvViewMode.epgGrid);
    expect(tvState.viewMode, TvViewMode.epgGrid);
    expect(tvState.persistedSettings['view_mode'], TvViewMode.epgGrid.name);

    tvState.setPlaybackRate(1.25);
    expect(tvState.playbackRate, 1.25);
    expect(tvState.persistedSettings['playback_rate'], '1.25');

    tvState.toggleMute();
    expect(tvState.isMuted, isTrue);
    expect(tvState.persistedSettings['is_muted'], '1');
  });

  test('TvStateProvider persists last played channel and group details for resume', () {
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
    expect(tvState.persistedSettings['last_channel_stream_url'], 'https://example.com/bbc.m3u8');
  });

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
}
