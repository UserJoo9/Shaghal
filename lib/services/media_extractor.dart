import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../core/media_formats.dart';
import '../models/download_item.dart';
import 'hls_downloader.dart';

class MediaExtractor {
  MediaExtractor({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              followRedirects: true,
              headers: const {
                'User-Agent':
                    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
                        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
                        'Version/18.0 Mobile/15E148 Safari/604.1',
              },
            ));

  final Dio _dio;

  static String? extractYouTubeId(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if (host.contains('youtube.com') || host.contains('youtube-nocookie.com')) {
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
      final segs = uri.pathSegments;
      if (segs.length >= 2 &&
          const {'shorts', 'embed', 'live', 'v'}.contains(segs[0])) {
        return segs[1];
      }
    }
    return null;
  }

  static String normalizeUrl(String raw) {
    var s = raw.trim();
    if (!s.contains('://') && !s.startsWith('about:')) {
      s = 'https://$s';
    }
    return s;
  }

  Future<ExtractedMedia> extract(
    String rawUrl, {
    String? customApiBase,
    Map<String, String> headers = const {},
  }) async {
    final url = normalizeUrl(rawUrl);

    // 1. YouTube: استخراج مباشر لكل الجودات (صوت وفيديو)
    final ytId = extractYouTubeId(url);
    if (ytId != null) {
      return _extractYouTube(ytId, url);
    }

    // 2. سيرفر خارجي اختياري (Cobalt / yt-dlp API) لو المستخدم فعّله في الإعدادات
    if (customApiBase != null && customApiBase.trim().isNotEmpty) {
      final viaApi = await _tryCustomApi(customApiBase.trim(), url);
      if (viaApi != null && viaApi.options.isNotEmpty) {
        return viaApi;
      }
    }

    // 3. قائمة HLS (.m3u8)
    final uri = Uri.parse(url);
    if (uri.path.toLowerCase().endsWith('.m3u8')) {
      final body = await _fetchText(url, headers);
      final opts = HlsParser.parsePlaylist(body, uri, headers: headers);
      return ExtractedMedia(
        title: _titleFromUri(uri),
        sourceUrl: url,
        options: opts,
      );
    }

    // 4. فحص الرابط هل هو ملف ميديا مباشر (HEAD ثم فحص الامتداد)
    final direct = await _tryDirectMedia(uri, headers);
    if (direct != null) return direct;

    // 5. استخراج مبدئي من HTML الصفحة (لو فشل، نطلب فتح المتصفح الداخلي للالتقاط)
    return _tryWebPageHtml(uri, headers);
  }

  Future<ExtractedMedia> _extractYouTube(String videoId, String sourceUrl) async {
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(videoId);
      StreamManifest manifest;
      try {
        manifest = await yt.videos.streams.getManifest(
          videoId,
          ytClients: [
            YoutubeApiClient.androidVr,
            YoutubeApiClient.ios,
            YoutubeApiClient.mweb,
          ],
        );
      } catch (_) {
        manifest = await yt.videos.streams.getManifest(videoId);
      }

      final audioStreams = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));

      final bestM4a = audioStreams
          .where((a) => a.container.name.toLowerCase() == 'mp4' ||
              a.audioCodec.toLowerCase().contains('mp4a'))
          .firstOrNull;
      final bestAnyAudio = audioStreams.firstOrNull;

      final options = <MediaFormatOption>[];

      // تجميع جودات الفيديو (Adaptive videoOnly + Muxed) مع تفضيل MP4 لنفس الدقة/الفريمات
      final bestByRes = <String,
          ({
            StreamInfo stream,
            int height,
            int fps,
            String qualityLabel,
            String videoCodec,
            bool isMuxed,
          })>{};

      for (final v in manifest.muxed) {
        final h = v.videoResolution.height;
        final fps = v.framerate.framesPerSecond.round();
        final key = '${h}_$fps';
        bestByRes[key] = (
          stream: v,
          height: h,
          fps: fps,
          qualityLabel: v.qualityLabel,
          videoCodec: v.videoCodec,
          isMuxed: true,
        );
      }

      for (final v in manifest.videoOnly) {
        final h = v.videoResolution.height;
        final fps = v.framerate.framesPerSecond.round();
        final key = '${h}_$fps';
        final existing = bestByRes[key];

        if (existing == null) {
          bestByRes[key] = (
            stream: v,
            height: h,
            fps: fps,
            qualityLabel: v.qualityLabel,
            videoCodec: v.videoCodec,
            isMuxed: false,
          );
        } else if (!existing.isMuxed) {
          final newScore = _videoStreamScore(v.container.name, v.videoCodec);
          final oldScore = _videoStreamScore(
            existing.stream.container.name,
            existing.videoCodec,
          );
          if (newScore > oldScore ||
              (newScore == oldScore &&
                  v.bitrate.bitsPerSecond >
                      existing.stream.bitrate.bitsPerSecond)) {
            bestByRes[key] = (
              stream: v,
              height: h,
              fps: fps,
              qualityLabel: v.qualityLabel,
              videoCodec: v.videoCodec,
              isMuxed: false,
            );
          }
        }
      }

      final sortedVideo = bestByRes.values.toList()
        ..sort((a, b) {
          final h = b.height.compareTo(a.height);
          if (h != 0) return h;
          final f = b.fps.compareTo(a.fps);
          if (f != 0) return f;
          return b.stream.bitrate.bitsPerSecond
              .compareTo(a.stream.bitrate.bitsPerSecond);
        });

      for (final entry in sortedVideo) {
        final v = entry.stream;
        final isMuxed = entry.isMuxed;
        final container = v.container.name.toLowerCase();
        final audioPair = isMuxed
            ? null
            : (container == 'mp4' ? (bestM4a ?? bestAnyAudio) : bestAnyAudio);
        final totalBytes = v.size.totalBytes + (audioPair?.size.totalBytes ?? 0);
        final codecShort = _shortVideoCodec(entry.videoCodec);
        final outExt = isMuxed ? container : (container == 'mp4' ? 'mp4' : 'webm');

        options.add(MediaFormatOption(
          id: 'yt_v_${v.tag}',
          label: entry.qualityLabel,
          isVideo: true,
          ext: outExt,
          codecLabel:
              '${outExt.toUpperCase()} · $codecShort${isMuxed ? '' : ' + Audio'}',
          height: entry.height,
          fps: entry.fps,
          bitrateBps: v.bitrate.bitsPerSecond,
          sizeBytes: totalBytes,
          url: v.url.toString(),
          ytVideoStream: v,
          ytAudioStream: audioPair,
        ));
      }

      // كل جودات الصوت (M4A / OPUS / WebM) من الأعلى للأقل
      final seenAudio = <String>{};
      for (final a in audioStreams) {
        final container = a.container.name.toLowerCase();
        final isOpus = a.audioCodec.toLowerCase().contains('opus');
        final outExt = isOpus ? 'opus' : (container == 'mp4' ? 'm4a' : container);
        final kbps = (a.bitrate.bitsPerSecond / 1000).round();
        final dedup = '$outExt|${(kbps / 8).round()}';
        if (!seenAudio.add(dedup)) continue;

        final codecName = isOpus
            ? 'OPUS'
            : (a.audioCodec.toLowerCase().contains('mp4a')
                ? 'AAC · M4A'
                : outExt.toUpperCase());

        options.add(MediaFormatOption(
          id: 'yt_a_${a.tag}',
          label: '$kbps kbps',
          isVideo: false,
          ext: outExt,
          codecLabel: codecName,
          bitrateBps: a.bitrate.bitsPerSecond,
          sizeBytes: a.size.totalBytes,
          url: a.url.toString(),
          ytAudioStream: a,
        ));
      }

      return ExtractedMedia(
        title: video.title,
        sourceUrl: sourceUrl,
        thumbnailUrl: video.thumbnails.highResUrl,
        author: video.author,
        options: options,
      );
    } finally {
      yt.close();
    }
  }

  int _videoStreamScore(String containerName, String videoCodec) {
    final isMp4 = containerName.toLowerCase() == 'mp4';
    final c = videoCodec.toLowerCase();
    if (isMp4 && c.startsWith('avc')) return 4;
    if (isMp4 && (c.startsWith('hev') || c.startsWith('hvc'))) return 3;
    if (isMp4) return 2;
    return 1;
  }

  String _shortVideoCodec(String codec) {
    final c = codec.toLowerCase();
    if (c.startsWith('avc')) return 'H.264';
    if (c.startsWith('hev') || c.startsWith('hvc')) return 'HEVC';
    if (c.startsWith('av01')) return 'AV1';
    if (c.startsWith('vp9') || c.startsWith('vp09')) return 'VP9';
    return codec.split('.').first.toUpperCase();
  }

  Future<ExtractedMedia?> _tryDirectMedia(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final pathExt = _extFromPath(uri.path);
    String? contentType;
    int? contentLength;

    try {
      final head = await _dio.head<void>(
        uri.toString(),
        options: Options(headers: headers),
      );
      contentType = head.headers.value('content-type')?.toLowerCase();
      contentLength =
          int.tryParse(head.headers.value('content-length') ?? '');
    } catch (_) {
      // بعض السيرفرات بتمنع HEAD، فنكتفي بفحص الامتداد
    }

    if (contentType != null &&
        (contentType.contains('mpegurl') || contentType.contains('m3u8'))) {
      final body = await _fetchText(uri.toString(), headers);
      final opts = HlsParser.parsePlaylist(body, uri, headers: headers);
      return ExtractedMedia(
        title: _titleFromUri(uri),
        sourceUrl: uri.toString(),
        options: opts,
      );
    }

    final isVideoByExt = pathExt != null && MediaFormats.video.contains(pathExt);
    final isAudioByExt = pathExt != null && MediaFormats.audio.contains(pathExt);
    final isVideoByMime = contentType != null && contentType.startsWith('video/');
    final isAudioByMime = contentType != null && contentType.startsWith('audio/');

    if (!isVideoByExt && !isAudioByExt && !isVideoByMime && !isAudioByMime) {
      return null;
    }

    final isVideo = isVideoByExt || (isVideoByMime && !isAudioByExt);
    final ext = pathExt ?? (isVideo ? 'mp4' : 'mp3');

    final options = <MediaFormatOption>[
      MediaFormatOption(
        id: 'direct_0',
        label: isVideo ? 'الجودة الأصلية (${ext.toUpperCase()})' : ext.toUpperCase(),
        isVideo: isVideo,
        ext: ext,
        codecLabel: ext.toUpperCase(),
        sizeBytes: contentLength,
        url: uri.toString(),
        headers: headers,
      ),
      if (isVideo)
        MediaFormatOption(
          id: 'direct_audio_extract',
          label: 'M4A (استخراج الصوت)',
          isVideo: false,
          ext: 'm4a',
          codecLabel: 'AAC · M4A',
          url: uri.toString(),
          needsAudioExtract: true,
          headers: headers,
        ),
    ];

    return ExtractedMedia(
      title: _titleFromUri(uri),
      sourceUrl: uri.toString(),
      options: options,
    );
  }

  Future<ExtractedMedia> _tryWebPageHtml(
    Uri uri,
    Map<String, String> headers,
  ) async {
    String html;
    try {
      html = await _fetchText(uri.toString(), headers);
    } catch (_) {
      return ExtractedMedia(
        title: uri.host,
        sourceUrl: uri.toString(),
        needsBrowserSniff: true,
      );
    }

    final title = _extractMeta(html, 'og:title') ??
        _extractHtmlTitle(html) ??
        uri.host;
    final thumb = _extractMeta(html, 'og:image');

    final found = <String>{};
    for (final prop in const [
      'og:video:secure_url',
      'og:video:url',
      'og:video',
      'twitter:player:stream',
      'og:audio',
      'og:audio:secure_url',
    ]) {
      final v = _extractMeta(html, prop);
      if (v != null && v.startsWith('http')) found.add(v);
    }

    final unescaped = html
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll('&amp;', '&');
    final mediaRegex = RegExp(
      r'''https?://[^\s"'<>\\]+\.(?:mp4|m3u8|webm|m4a|mp3|opus|aac|mov)(?:\?[^\s"'<>\\]*)?''',
      caseSensitive: false,
    );
    for (final m in mediaRegex.allMatches(unescaped)) {
      final u = m.group(0)!;
      if (!u.contains('.js') && !u.contains('.css')) {
        found.add(u);
      }
    }

    if (found.isEmpty) {
      return ExtractedMedia(
        title: title,
        sourceUrl: uri.toString(),
        thumbnailUrl: thumb,
        needsBrowserSniff: true,
      );
    }

    return buildFromSniffedUrls(
      pageUrl: uri.toString(),
      title: title,
      thumbnailUrl: thumb,
      urls: found.toList(),
      headers: {...headers, 'Referer': uri.toString()},
    );
  }

  /// يبني قائمة الجودات من الروابط التي التقطها المتصفح الداخلي أو من HTML.
  Future<ExtractedMedia> buildFromSniffedUrls({
    required String pageUrl,
    required String title,
    String? thumbnailUrl,
    required List<String> urls,
    Map<String, String> headers = const {},
  }) async {
    final options = <MediaFormatOption>[];
    final seen = <String>{};

    for (final raw in urls) {
      final clean = raw.trim();
      if (clean.isEmpty || !seen.add(clean)) continue;
      final u = Uri.tryParse(clean);
      if (u == null) continue;
      final lowerPath = u.path.toLowerCase();

      if (lowerPath.endsWith('.m3u8') || clean.toLowerCase().contains('.m3u8?')) {
        try {
          final body = await _fetchText(clean, headers);
          final hlsOpts = HlsParser.parsePlaylist(body, u, headers: headers);
          for (final o in hlsOpts) {
            options.add(o);
          }
          continue;
        } catch (_) {
          options.add(MediaFormatOption(
            id: 'sniff_hls_${options.length}',
            label: 'HLS Stream',
            isVideo: true,
            ext: 'ts',
            codecLabel: 'HLS · TS',
            url: clean,
            isHls: true,
            headers: headers,
          ));
          continue;
        }
      }

      final ext = _extFromPath(lowerPath) ??
          (clean.contains('mime=audio') ? 'm4a' : 'mp4');
      final isAudio = MediaFormats.audio.contains(ext);
      final isVideo = MediaFormats.video.contains(ext) || !isAudio;

      int? size;
      try {
        final head = await _dio.head<void>(
          clean,
          options: Options(headers: headers),
        );
        size = int.tryParse(head.headers.value('content-length') ?? '');
      } catch (_) {}

      final qHint = _guessQualityFromUrl(clean);
      options.add(MediaFormatOption(
        id: 'sniff_${options.length}',
        label: qHint ?? (isVideo ? 'فيديو ${ext.toUpperCase()}' : ext.toUpperCase()),
        isVideo: isVideo,
        ext: ext,
        codecLabel: ext.toUpperCase(),
        height: _heightFromHint(qHint),
        sizeBytes: size,
        url: clean,
        headers: headers,
      ));
    }

    // لو فيه فيديو فقط ومافيش خيارات صوت مستقلة، نضيف خيار استخراج الصوت M4A
    final hasVideo = options.any((o) => o.isVideo);
    final hasAudio = options.any((o) => !o.isVideo);
    if (hasVideo && !hasAudio) {
      final bestVid = options.firstWhere((o) => o.isVideo);
      options.add(MediaFormatOption(
        id: 'sniff_audio_extract',
        label: 'M4A (استخراج الصوت)',
        isVideo: false,
        ext: 'm4a',
        codecLabel: 'AAC · M4A',
        url: bestVid.url,
        audioPairUrl: bestVid.audioPairUrl,
        isHls: bestVid.isHls,
        needsAudioExtract: true,
        headers: bestVid.headers,
      ));
    }

    // ترتيب: الفيديو الأعلى دقة أولاً ثم الصوت
    final videos = options.where((o) => o.isVideo).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    final audios = options.where((o) => !o.isVideo).toList()
      ..sort((a, b) => b.bitrateBps.compareTo(a.bitrateBps));

    return ExtractedMedia(
      title: title.isEmpty ? _titleFromUri(Uri.parse(pageUrl)) : title,
      sourceUrl: pageUrl,
      thumbnailUrl: thumbnailUrl,
      options: [...videos, ...audios],
    );
  }

  /// دعم اختياري لسيرفر Cobalt / yt-dlp API لو المستخدم أضاف رابطه في الإعدادات.
  Future<ExtractedMedia?> _tryCustomApi(String apiBase, String targetUrl) async {
    try {
      final endpoint = apiBase.endsWith('/') ? apiBase : '$apiBase/';
      final res = await _dio.post<dynamic>(
        endpoint,
        data: jsonEncode({'url': targetUrl}),
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
      );
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (data is! Map<String, dynamic>) return null;
      final dlUrl = data['url'] as String?;
      final picker = data['picker'] as List?;
      final opts = <MediaFormatOption>[];

      if (dlUrl != null && dlUrl.isNotEmpty) {
        final fn = (data['filename'] as String?) ?? 'download.mp4';
        final ext = _extFromPath(fn) ?? 'mp4';
        final isVid = MediaFormats.video.contains(ext) || !MediaFormats.audio.contains(ext);
        opts.add(MediaFormatOption(
          id: 'api_main',
          label: isVid ? 'أفضل جودة (${ext.toUpperCase()})' : ext.toUpperCase(),
          isVideo: isVid,
          ext: ext,
          codecLabel: ext.toUpperCase(),
          url: dlUrl,
        ));
        if (isVid) {
          opts.add(MediaFormatOption(
            id: 'api_audio_extract',
            label: 'M4A (استخراج الصوت)',
            isVideo: false,
            ext: 'm4a',
            codecLabel: 'AAC · M4A',
            url: dlUrl,
            needsAudioExtract: true,
          ));
        }
      }
      if (picker != null) {
        for (var i = 0; i < picker.length; i++) {
          final pItem = picker[i];
          if (pItem is Map<String, dynamic> && pItem['url'] is String) {
            final u = pItem['url'] as String;
            final type = pItem['type'] as String? ?? 'video';
            final isVid = type != 'audio';
            opts.add(MediaFormatOption(
              id: 'api_pick_$i',
              label: isVid ? 'فيديو ${i + 1}' : 'صوت ${i + 1}',
              isVideo: isVid,
              ext: isVid ? 'mp4' : 'm4a',
              codecLabel: isVid ? 'MP4' : 'M4A',
              url: u,
            ));
          }
        }
      }
      if (opts.isEmpty) return null;
      return ExtractedMedia(
        title: (data['filename'] as String?)?.replaceAll(RegExp(r'\.[^.]+$'), '') ??
            _titleFromUri(Uri.parse(targetUrl)),
        sourceUrl: targetUrl,
        options: opts,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _fetchText(String url, Map<String, String> headers) async {
    final res = await _dio.get<String>(
      url,
      options: Options(headers: headers, responseType: ResponseType.plain),
    );
    return res.data ?? '';
  }

  String? _extractMeta(String html, String name) {
    final escaped = RegExp.escape(name);
    final r1 = RegExp(
      '<meta[^>]+(?:property|name)=["\']$escaped["\'][^>]+content=["\']([^"\']+)["\']',
      caseSensitive: false,
    );
    final r2 = RegExp(
      '<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name)=["\']$escaped["\']',
      caseSensitive: false,
    );
    return r1.firstMatch(html)?.group(1) ?? r2.firstMatch(html)?.group(1);
  }

  String? _extractHtmlTitle(String html) {
    final m = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
        .firstMatch(html);
    return m?.group(1)?.trim();
  }

  String? _extFromPath(String path) {
    final clean = path.split('?').first.split('#').first;
    final dot = clean.lastIndexOf('.');
    if (dot < 0 || dot == clean.length - 1) return null;
    final ext = clean.substring(dot + 1).toLowerCase();
    return ext.length <= 5 ? ext : null;
  }

  String _titleFromUri(Uri uri) {
    final seg = uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => uri.host);
    final noExt = seg.replaceAll(RegExp(r'\.[a-zA-Z0-9]{1,5}$'), '');
    return Uri.decodeComponent(noExt).trim().isEmpty ? uri.host : Uri.decodeComponent(noExt);
  }

  String? _guessQualityFromUrl(String url) {
    final m = RegExp(r'(2160|1440|1080|720|480|360|240|144)p?', caseSensitive: false)
        .firstMatch(url);
    return m != null ? '${m.group(1)}p' : null;
  }

  int _heightFromHint(String? hint) {
    if (hint == null) return 0;
    return int.tryParse(hint.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }
}
