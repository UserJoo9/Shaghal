import 'dart:io';

import 'package:dio/dio.dart';

import '../models/download_item.dart';

class HlsParser {
  HlsParser._();

  static Map<String, String> _parseAttrs(String line) {
    final map = <String, String>{};
    final re = RegExp(r'([A-Z0-9-]+)=("([^"]*)"|([^,]*))');
    for (final m in re.allMatches(line)) {
      final k = m.group(1)!;
      final v = m.group(3) ?? m.group(4) ?? '';
      map[k] = v;
    }
    return map;
  }

  static List<MediaFormatOption> parsePlaylist(
    String content,
    Uri baseUrl, {
    Map<String, String> headers = const {},
  }) {
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final isMaster = lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'));
    if (!isMaster) {
      final hasMap = lines.any((l) => l.startsWith('#EXT-X-MAP:'));
      final ext = hasMap ? 'mp4' : 'ts';
      return [
        MediaFormatOption(
          id: 'hls_default',
          label: 'HLS Auto',
          isVideo: true,
          ext: ext,
          codecLabel: 'HLS · ${ext.toUpperCase()}',
          url: baseUrl.toString(),
          isHls: true,
          headers: headers,
        ),
        MediaFormatOption(
          id: 'hls_audio_extract',
          label: 'M4A (استخراج الصوت)',
          isVideo: false,
          ext: 'm4a',
          codecLabel: 'AAC · M4A',
          url: baseUrl.toString(),
          isHls: true,
          needsAudioExtract: true,
          headers: headers,
        ),
      ];
    }

    // مسارات الصوت المنفصلة في #EXT-X-MEDIA:TYPE=AUDIO
    final audioTracks = <String, List<({String name, String url})>>{};
    for (final l in lines) {
      if (!l.startsWith('#EXT-X-MEDIA:')) continue;
      final attrs = _parseAttrs(l);
      if (attrs['TYPE'] != 'AUDIO') continue;
      final uri = attrs['URI'];
      if (uri == null || uri.isEmpty) continue;
      final group = attrs['GROUP-ID'] ?? '';
      final name = attrs['NAME'] ?? attrs['LANGUAGE'] ?? 'Audio';
      audioTracks
          .putIfAbsent(group, () => [])
          .add((name: name, url: baseUrl.resolve(uri).toString()));
    }

    final options = <MediaFormatOption>[];
    final seenHeights = <String>{};

    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!l.startsWith('#EXT-X-STREAM-INF:')) continue;
      String? variantUrl;
      for (var j = i + 1; j < lines.length; j++) {
        if (!lines[j].startsWith('#')) {
          variantUrl = baseUrl.resolve(lines[j]).toString();
          break;
        }
      }
      if (variantUrl == null) continue;

      final attrs = _parseAttrs(l.substring('#EXT-X-STREAM-INF:'.length));
      final bw = int.tryParse(attrs['BANDWIDTH'] ?? '') ?? 0;
      final res = attrs['RESOLUTION'] ?? '';
      final fps = double.tryParse(attrs['FRAME-RATE'] ?? '')?.round() ?? 0;
      var height = 0;
      if (res.contains('x')) {
        height = int.tryParse(res.split('x').last) ?? 0;
      }
      final label = height > 0
          ? '${height}p${fps >= 50 ? '$fps' : ''}'
          : (bw > 0 ? '${(bw / 1000).round()} kbps' : 'HLS');
      final dedupKey = '$height|$fps|${(bw / 100000).round()}';
      if (!seenHeights.add(dedupKey)) continue;

      final audioGroup = attrs['AUDIO'];
      final audioUrl =
          audioGroup != null ? audioTracks[audioGroup]?.firstOrNull?.url : null;

      options.add(MediaFormatOption(
        id: 'hls_${options.length}_$height',
        label: label,
        isVideo: true,
        ext: 'mp4',
        codecLabel:
            'HLS${bw > 0 ? ' · ${(bw / 1000).round()} kbps' : ''}',
        height: height,
        fps: fps,
        bitrateBps: bw,
        url: variantUrl,
        audioPairUrl: audioUrl,
        audioPairExt: audioUrl != null ? 'ts' : null,
        isHls: true,
        headers: headers,
      ));
    }

    options.sort((a, b) {
      final h = b.height.compareTo(a.height);
      if (h != 0) return h;
      return b.bitrateBps.compareTo(a.bitrateBps);
    });

    // إضافة مسارات الصوت المنفصلة إن وُجدت، وإلا خيار استخراج الصوت من أعلى جودة
    var addedAudio = false;
    for (final entry in audioTracks.entries) {
      for (final track in entry.value) {
        addedAudio = true;
        options.add(MediaFormatOption(
          id: 'hls_aud_${options.length}',
          label: track.name,
          isVideo: false,
          ext: 'm4a',
          codecLabel: 'HLS Audio · M4A',
          url: track.url,
          isHls: true,
          needsAudioExtract: true,
          headers: headers,
        ));
      }
    }
    if (!addedAudio && options.isNotEmpty) {
      options.add(MediaFormatOption(
        id: 'hls_audio_extract',
        label: 'M4A · Audio',
        isVideo: false,
        ext: 'm4a',
        codecLabel: 'AAC · M4A',
        url: options.first.url,
        audioPairUrl: options.first.audioPairUrl,
        isHls: true,
        needsAudioExtract: true,
        headers: headers,
      ));
    }

    return options;
  }
}

class HlsDownloader {
  HlsDownloader._();

  /// يحمّل قائمة تشغيل HLS (وإذا كانت master يختار أعلى جودة) إلى ملف واحد.
  static Future<String> download({
    required Dio dio,
    required String playlistUrl,
    required String outputBasePath,
    required Map<String, String> headers,
    required CancelToken cancelToken,
    required void Function(double progress, int receivedBytes) onProgress,
  }) async {
    var currentUri = Uri.parse(playlistUrl);
    var body = await _fetchText(dio, currentUri.toString(), headers, cancelToken);

    if (body.contains('#EXT-X-STREAM-INF')) {
      final parsed = HlsParser.parsePlaylist(body, currentUri, headers: headers);
      final firstVideo = parsed.where((o) => o.isVideo && o.url != null).firstOrNull;
      if (firstVideo == null) {
        throw Exception('No playable stream in HLS master playlist');
      }
      currentUri = Uri.parse(firstVideo.url!);
      body = await _fetchText(dio, currentUri.toString(), headers, cancelToken);
    }

    final lines = body
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (final l in lines) {
      if (l.startsWith('#EXT-X-KEY:') &&
          !l.contains('METHOD=NONE')) {
        if (l.contains('SAMPLE-AES') || l.contains('FAIRPLAY')) {
          throw Exception('DRM-protected stream cannot be downloaded');
        }
      }
    }

    String? initUri;
    final segments = <String>[];
    for (final l in lines) {
      if (l.startsWith('#EXT-X-MAP:')) {
        final m = RegExp(r'URI="([^"]+)"').firstMatch(l);
        if (m != null) initUri = currentUri.resolve(m.group(1)!).toString();
      } else if (!l.startsWith('#')) {
        segments.add(currentUri.resolve(l).toString());
      }
    }

    if (segments.isEmpty) {
      throw Exception('HLS playlist contains no media segments');
    }

    final outExt = initUri != null ? 'mp4' : 'ts';
    final outPath = '$outputBasePath.$outExt';
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    final sink = outFile.openWrite();

    var received = 0;
    try {
      if (initUri != null) {
        final initBytes = await _fetchBytes(dio, initUri, headers, cancelToken);
        sink.add(initBytes);
        received += initBytes.length;
      }

      const batchSize = 4;
      for (var i = 0; i < segments.length; i += batchSize) {
        if (cancelToken.isCancelled) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: playlistUrl),
            reason: 'Cancelled',
          );
        }
        final end = (i + batchSize < segments.length)
            ? i + batchSize
            : segments.length;
        final batch = segments.sublist(i, end);
        final chunks = await Future.wait([
          for (final seg in batch) _fetchBytes(dio, seg, headers, cancelToken),
        ]);
        for (final c in chunks) {
          sink.add(c);
          received += c.length;
        }
        onProgress(end / segments.length, received);
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await outFile.exists()) await outFile.delete();
      rethrow;
    }
    await sink.close();
    return outPath;
  }

  static Future<String> _fetchText(
    Dio dio,
    String url,
    Map<String, String> headers,
    CancelToken cancelToken,
  ) async {
    final res = await dio.get<String>(
      url,
      cancelToken: cancelToken,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
        followRedirects: true,
      ),
    );
    return res.data ?? '';
  }

  static Future<List<int>> _fetchBytes(
    Dio dio,
    String url,
    Map<String, String> headers,
    CancelToken cancelToken,
  ) async {
    final res = await dio.get<List<int>>(
      url,
      cancelToken: cancelToken,
      options: Options(
        headers: headers,
        responseType: ResponseType.bytes,
        followRedirects: true,
      ),
    );
    return res.data ?? const [];
  }
}
