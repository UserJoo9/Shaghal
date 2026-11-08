import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? Colors.black : const Color(0xFFF2F2F7);
  return ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: dark
        ? const ColorScheme.dark(
            primary: Color(0xFF0A84FF),
            surface: Colors.black,
          )
        : const ColorScheme.light(
            primary: Color(0xFF0A84FF),
            surface: Color(0xFFF2F2F7),
          ),
    scaffoldBackgroundColor: bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: dark ? Colors.white10 : Colors.black12,
  );
}

class ShaghalApp extends ConsumerWidget {
  const ShaghalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(glassClearProvider); // بيطبّق نمط الزجاج المحفوظ
    ref.watch(glassOpacityProvider); // وشفافيته المحفوظة
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shaghal - شغل',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: mode,
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const LibraryPage(),
    );
  }
}
