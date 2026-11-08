import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_design/liquid_design.dart' show LiquidGlassService, LiquidGlassStyle;
import 'package:media_kit/media_kit.dart';

import 'services/audio_handler.dart';
import 'state/providers.dart';
import 'ui/library_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // حركة الزجاج (ضغط/سحب/ارتداد) أقوى شوية من الافتراضي، قريبة من تطبيقات النظام.
  // الشفافية نفسها (شفاف/ملوّن) بتيجي من إعدادات النظام ومش بنتحكم فيها من التطبيق.
  LiquidGlassService.instance
    ..setStyle(LiquidGlassStyle.clear) // زجاج شفاف (UIGlassEffect clear)
    ..setOpacity(1.0)
    ..setInteractionStrength(1.3);

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
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: _NoParallaxTransitions(),
      TargetPlatform.android: _NoParallaxTransitions(),
    }),
  );
}

/// نفس انتقال iOS (انزلاق + سحب من الحافة للرجوع) لكن من غير ما الصفحة اللي تحت تتحرك.
/// الصفحة اللي تحت فيها زجاج نيتيف (navbar والمشغّل)، وتحريكه مع كل frame هو سبب الرعشة.
class _NoParallaxTransitions extends PageTransitionsBuilder {
  const _NoParallaxTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return const CupertinoPageTransitionsBuilder().buildTransitions<T>(
      route,
      context,
      animation,
      const AlwaysStoppedAnimation<double>(0),
      child,
    );
  }
}

class ShaghalApp extends ConsumerWidget {
  const ShaghalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
