import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../core/media_formats.dart';

/// بيشتغل في isolate: بيطلّع غلاف الألبوم المدمج في ملف الصوت (ID3 / MP4 / FLAC / OGG).
Future<Uint8List?> _extractAudioCover(String path) async {
  try {
    final dynamic r = readMetadata(File(path), getImage: true);
    final dynamic md = r is Future ? await r : r;
    final pics = md.pictures as List;
    if (pics.isEmpty) return null;
    final bytes = pics.first.bytes as Uint8List;
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> _videoFrame(String path) async {
  try {
    // AVFoundation على iOS بيدعم mp4/mov/m4v؛ mkv/avi/webm بترجع null ونعرض بديل.
    return await VideoThumbnail.thumbnailData(
      video: path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 360,
      quality: 75,
      timeMs: 1000,
    );
  } catch (_) {
    return null;
  }
}

class _Pool {
  _Pool(this.max);
  final int max;
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();

  Future<T> run<T>(Future<T> Function() job) async {
    if (_running >= max) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      return await job();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeFirst().complete();
    }
  }
}

/// صور مصغّرة بتتحفظ على القرص (كاش) وبتتولّد بالتدريج لما الصف يظهر.
class Thumbnails {
  Thumbnails._();

  static Directory? _dir;
  static final _pool = _Pool(2);

  static Future<Directory> _cacheDir() async {
    final base = await getApplicationCacheDirectory();
    final d = Directory(p.join(base.path, 'thumbs'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static String _key(String s) {
    var h = 0xcbf29ce484222325; // FNV-1a 64
    for (final b in utf8.encode(s)) {
      h = (h ^ b) * 0x100000001b3;
    }
    return h.toUnsigned(64).toRadixString(16);
  }

  /// مسار صورة JPG مصغّرة، أو null لو الملف مفيهوش غلاف.
  static Future<String?> get(String path) async {
    try {
      final dir = _dir ??= await _cacheDir();
      final st = File(path).statSync();
      final key = _key('$path|${st.modified.millisecondsSinceEpoch}|${st.size}');
      final img = File(p.join(dir.path, '$key.jpg'));
      final none = File(p.join(dir.path, '$key.none'));
      if (img.existsSync()) return img.path;
      if (none.existsSync()) return null;

      return await _pool.run(() async {
        final isVideo = MediaFormats.isVideo(path) ?? false;
        final bytes = isVideo
            ? await _videoFrame(path)
            : await compute(_extractAudioCover, path);
        if (bytes == null || bytes.isEmpty) {
          none.createSync();
          return null;
        }
        await img.writeAsBytes(bytes, flush: true);
        return img.path;
      });
    } catch (_) {
      return null;
    }
  }
}
