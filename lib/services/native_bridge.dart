import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/services.dart';

class NativeBridge {
  NativeBridge._();
  static final NativeBridge instance = NativeBridge._();

  static const _channel = MethodChannel('com.yalkhodary.shaghal/native');
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  bool _initialized = false;

  Future<void> initShareListener(void Function(String url) onSharedUrl) async {
    if (_initialized) return;
    _initialized = true;

    void handleUri(Uri? uri) {
      if (uri == null) return;
      final q = uri.queryParameters['url'];
      if (q != null && q.trim().isNotEmpty) {
        onSharedUrl(q.trim());
        return;
      }
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        onSharedUrl(uri.toString());
      }
    }

    if (Platform.isIOS) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onSharedUrl') {
          final arg = call.arguments;
          if (arg is String && arg.trim().isNotEmpty) {
            onSharedUrl(arg.trim());
          }
        }
      });
      try {
        final pending =
            await _channel.invokeMethod<String>('consumePendingSharedUrl');
        if (pending != null && pending.trim().isNotEmpty) {
          onSharedUrl(pending.trim());
        }
      } catch (_) {}
    }

    try {
      handleUri(await _appLinks.getInitialLink());
    } catch (_) {}

    _linkSub = _appLinks.uriLinkStream.listen(
      handleUri,
      onError: (_) {},
    );
  }

  Future<void> muxVideoAndAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
  }) async {
    if (Platform.isIOS) {
      await _channel.invokeMethod('muxVideoAndAudio', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
      });
      return;
    }

    final res = await Process.run('ffmpeg', [
      '-y',
      '-i',
      videoPath,
      '-i',
      audioPath,
      '-c',
      'copy',
      outputPath,
    ]);
    if (res.exitCode != 0) {
      throw Exception('ffmpeg mux failed: ${res.stderr}');
    }
  }

  Future<void> extractAudio({
    required String inputPath,
    required String outputPath,
  }) async {
    if (Platform.isIOS) {
      await _channel.invokeMethod('extractAudio', {
        'inputPath': inputPath,
        'outputPath': outputPath,
      });
      return;
    }

    final res = await Process.run('ffmpeg', [
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      outputPath,
    ]);
    if (res.exitCode != 0) {
      throw Exception('ffmpeg audio extract failed: ${res.stderr}');
    }
  }

  void dispose() {
    _linkSub?.cancel();
    _linkSub = null;
  }
}
