import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'services/audio_handler.dart';
import 'state/providers.dart';
import 'ui/library_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  final controller = PlayerController();

  // Control Center / شاشة القفل (مش متاح على Windows، فبنتخطاه هناك).
  if (Platform.isIOS || Platform.isAndroid || Platform.isMacOS) {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
    await AudioService.init(
      builder: () => ShaghalAudioHandler(controller),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.yalkhodary.shaghal.audio',
        androidNotificationChannelName: 'Shaghal',
      ),
    );
  }

  runApp(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(controller)],
      child: const ShaghalApp(),
    ),
  );
}

class ShaghalApp extends StatelessWidget {
  const ShaghalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shaghal - شغل',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0A84FF),
          surface: Colors.black,
        ),
        scaffoldBackgroundColor: Colors.black,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.white10,
      ),
      home: const LibraryPage(),
    );
  }
}
