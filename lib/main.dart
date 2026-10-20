import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'providers/tv_state_provider.dart';
import 'services/app_platform.dart';
import 'ui/screens/tv_home_screen.dart';
import 'ui/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppPlatform.isDesktop) {
    MediaKit.ensureInitialized();
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(800, 500));
  }
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => TvStateProvider())],
      child: const TiviPlayerApp(),
    ),
  );
}

class TiviPlayerApp extends StatelessWidget {
  const TiviPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TiviPlayer TV',
      debugShowCheckedModeBanner: false,
      theme: TvTheme.themeData,
      home: const TvHomeScreen(),
    );
  }
}
