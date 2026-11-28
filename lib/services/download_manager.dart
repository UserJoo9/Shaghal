import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/download_item.dart';
import '../state/providers.dart';
import 'hls_downloader.dart';
import 'media_extractor.dart';
import 'native_bridge.dart';
import 'thumbnails.dart';

final pendingSharesProvider =
    NotifierProvider<PendingSharesNotifier, List<PendingShareItem>>(
  PendingSharesNotifier.new,
);

class PendingSharesNotifier extends Notifier<List<PendingShareItem>> {
  final _extractor = MediaExtractor();
  final Set<String> _running = {};
  bool _loaded = false;

  @override
  List<PendingShareItem> build() {
    unawaited(_loadSaved());
    return const [];
  }

  Future<File> _saveFile() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File(p.join(d.path, 'pending_shares.json'));
  }

  Future<void> _loadSaved() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _saveFile();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is List) {
        final urls = raw.whereType<String>().toList();
        if (urls.isNotEmpty) addUrls(urls);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final f = await _saveFile();
      await f.writeAsString(jsonEncode([for (final item in state) item.url]));
    } catch (_) {}
  }

  void addUrls(List<String> urls) {
    final existing = {for (final i in state) i.url};
    final added = <PendingShareItem>[];
    final now = DateTime.now();
    for (var i = 0; i < urls.length; i++) {
      final clean = urls[i].trim();
      if (clean.isEmpty || !existing.add(clean)) continue;
      added.add(PendingShareItem(
        id: 'share_${now.microsecondsSinceEpoch}_${state.length + i}',
        url: clean,
        status: PendingShareStatus.analyzing,
        addedAt: now,
      ));
    }
    if (added.isEmpty) return;
    state = [...state, ...added];
    unawaited(_persist());
    for (final item in added) {
      unawaited(_analyze(item.id, item.url));
    }
  }

  void retry(String id) {
    final item = state.where((i) => i.id == id).firstOrNull;
    if (item == null || _running.contains(id)) return;
    _update(id, (x) => PendingShareItem(
      id: x.id,
      url: x.url,
      status: PendingShareStatus.analyzing,
      addedAt: x.addedAt,
    ));
    unawaited(_analyze(id, item.url));
  }

  void remove(String id) {
    state = state.where((i) => i.id != id).toList();
    unawaited(_persist());
  }

  void clearAll() {
    state = const [];
    unawaited(_persist());
  }

  void _update(String id, PendingShareItem Function(PendingShareItem) fn) {
    state = [
      for (final i in state)
        if (i.id == id) fn(i) else i,
    ];
  }

  Future<void> _analyze(String id, String url) async {
    if (_running.contains(id)) return;
    _running.add(id);
    try {
      final api = ref.read(customApiUrlProvider);
      final media = await _extractor.extract(url, customApiBase: api);
      if (!state.any((i) => i.id == id)) return;
      _update(
        id,
        (x) => x.copyWith(
          status: PendingShareStatus.ready,
          media: media,
        ),
      );
    } catch (e) {
      if (!state.any((i) => i.id == id)) return;
      _update(
        id,
        (x) => x.copyWith(
          status: PendingShareStatus.failed,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      _running.remove(id);
    }
  }
}

final downloadsProvider =
    NotifierProvider<DownloadManagerNotifier, List<DownloadTask>>(
  DownloadManagerNotifier.new,
);

class DownloadManagerNotifier extends Notifier<List<DownloadTask>> {
  final Map<String, CancelToken> _tokens = {};
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 5),
    followRedirects: true,
    headers: const {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) '
              'Version/18.0 Mobile/15E148 Safari/604.1',
    },
  ));

  @override
  List<DownloadTask> build() => const [];

  String enqueue({
    required String title,
    required String sourceUrl,
    required MediaFormatOption option,
    required String targetFolder,
    String? thumbnailUrl,
    String? author,
  }) {
    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${state.length}';
    final task = DownloadTask(
      id: id,
      title: title,
      sourceUrl: sourceUrl,
      option: option,
      targetFolder: targetFolder.isEmpty ? 'Downloads' : targetFolder,
      status: DownloadTaskStatus.queued,
      createdAt: DateTime.now(),
      thumbnailUrl: thumbnailUrl,
      author: author,
      totalBytes: option.sizeBytes,
    );
    state = [task, ...state];
    unawaited(_runTask(task));
    return id;
  }

  void cancel(String id) {
    _tokens[id]?.cancel('Cancelled by user');
    _update(id, (t) => t.copyWith(status: DownloadTaskStatus.cancelled));
  }

  void remove(String id) {
    _tokens[id]?.cancel('Removed');
    _tokens.remove(id);
    state = state.where((t) => t.id != id).toList();
  }

  void _update(String id, DownloadTask Function(DownloadTask) fn) {
    state = [
      for (final t in state)
        if (t.id == id) fn(t) else t,
    ];
  }

  Future<void> _runTask(DownloadTask task) async {
    final token = CancelToken();
    _tokens[task.id] = token;
    final tmpDir = await getTemporaryDirectory();
    final workDir = Directory(p.join(tmpDir.path, 'dl_${task.id}'));
    await workDir.create(recursive: true);

    try {
      _update(
        task.id,
        (t) => t.copyWith(status: DownloadTaskStatus.downloading, progress: 0),
      );

      final root = await libraryRootPath();
      final destDir = Directory(p.join(root, task.targetFolder));
      await destDir.create(recursive: true);
      final safeName = _sanitizeFileName(task.title);

      final opt = task.option;
      late String finalPath;

      if (opt.ytVideoStream != null || opt.ytAudioStream != null) {
        finalPath = await _downloadYouTube(task, opt, workDir.path, destDir.path, safeName, token);
      } else if (opt.isHls) {
        finalPath = await _downloadHls(task, opt, workDir.path, destDir.path, safeName, token);
      } else {
        finalPath = await _downloadDirect(task, opt, workDir.path, destDir.path, safeName, token);
      }

      if (token.isCancelled) return;
      await _applyArtworkAndMetadata(task, finalPath, workDir.path);
      if (token.isCancelled) return;
      final finalSize = File(finalPath).existsSync() ? File(finalPath).lengthSync() : null;
      _update(
        task.id,
        (t) => t.copyWith(
          status: DownloadTaskStatus.completed,
          progress: 1,
          receivedBytes: finalSize ?? t.receivedBytes,
          totalBytes: finalSize ?? t.totalBytes,
          outputPath: finalPath,
        ),
      );
      ref.invalidate(thumbProvider(finalPath));
      await ref.read(libraryProvider.notifier).refresh();
    } catch (e) {
      if (token.isCancelled) return;
      _update(
        task.id,
        (t) => t.copyWith(
          status: DownloadTaskStatus.failed,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      _tokens.remove(task.id);
      try {
        if (await workDir.exists()) await workDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<String> _downloadYouTube(
    DownloadTask task,
    MediaFormatOption opt,
    String workDir,
    String destDir,
    String safeName,
    CancelToken token,
  ) async {
    // صوت فقط
    if (opt.ytVideoStream == null && opt.ytAudioStream != null) {
      final out = _uniquePath(destDir, safeName, opt.ext);
      try {
        await _downloadYtStream(
          opt.ytAudioStream!,
          out,
          token,
          (rec, tot) => _update(
            task.id,
            (t) => t.copyWith(
              receivedBytes: rec,
              totalBytes: tot,
              progress: tot > 0 ? (rec / tot).clamp(0.0, 1.0) : 0,
            ),
          ),
        );
        return out;
      } on _YtHttpException catch (e) {
        if (token.isCancelled || e.statusCode != 403 || opt.ytMuxedFallback == null) {
          rethrow;
        }
        // يوتيوب أحياناً بيقفل adaptive audio بـ 403 بعد 1MB؛ نحمّل النسخة المدمجة ونستخرج الصوت
        final muxed = opt.ytMuxedFallback!;
        final tmpMuxed = p.join(workDir, 'fallback_muxed.${muxed.container.name}');
        final expectedTotal = opt.sizeBytes ?? muxed.size.totalBytes;
        await _downloadYtStream(
          muxed,
          tmpMuxed,
          token,
          (rec, tot) => _update(
            task.id,
            (t) => t.copyWith(
              receivedBytes: tot > 0 ? (rec / tot * expectedTotal).round() : 0,
              totalBytes: expectedTotal,
              progress: tot > 0 ? (rec / tot * 0.9).clamp(0.0, 0.9) : 0,
            ),
          ),
        );
        _update(
          task.id,
          (t) => t.copyWith(
            status: DownloadTaskStatus.processing,
            progress: 0.95,
            statusDetail: 'extracting_audio',
          ),
        );
        await _extractAudioToExt(
          tmpMuxed,
          out,
          opt.ext,
          bitrateBps: opt.bitrateBps,
          fromMuxedFallback: true,
        );
        return out;
      }
    }

    final vStream = opt.ytVideoStream!;
    final aStream = opt.ytAudioStream;

    // فيديو مدمج جاهز (Muxed)
    if (aStream == null) {
      final out = _uniquePath(destDir, safeName, opt.ext);
      await _downloadYtStream(
        vStream,
        out,
        token,
        (rec, tot) => _update(
          task.id,
          (t) => t.copyWith(
            receivedBytes: rec,
            totalBytes: tot,
            progress: tot > 0 ? (rec / tot).clamp(0.0, 1.0) : 0,
          ),
        ),
      );
      return out;
    }

    // فيديو + صوت منفصلين: نحمّل الاثنين ثم ندمجهم محلياً
    final vTmp = p.join(workDir, 'video.${vStream.container.name}');
    var aTmp = p.join(workDir, 'audio.${aStream.container.name}');
    final vTotal = vStream.size.totalBytes;
    final aTotal = aStream.size.totalBytes;
    final combinedTotal = vTotal + aTotal;

    await _downloadYtStream(
      vStream,
      vTmp,
      token,
      (rec, _) => _update(
        task.id,
        (t) => t.copyWith(
          receivedBytes: rec,
          totalBytes: combinedTotal,
          progress: combinedTotal > 0 ? (rec / combinedTotal).clamp(0.0, 0.9) : 0,
        ),
      ),
    );

    try {
      await _downloadYtStream(
        aStream,
        aTmp,
        token,
        (rec, _) => _update(
          task.id,
          (t) => t.copyWith(
            receivedBytes: vTotal + rec,
            totalBytes: combinedTotal,
            progress: combinedTotal > 0
                ? ((vTotal + rec) / combinedTotal).clamp(0.0, 0.95)
                : 0.9,
          ),
        ),
      );
    } on _YtHttpException catch (e) {
      if (token.isCancelled || e.statusCode != 403 || opt.ytMuxedFallback == null) {
        rethrow;
      }
      final muxed = opt.ytMuxedFallback!;
      final tmpMuxed = p.join(workDir, 'fallback_audio_src.${muxed.container.name}');
      final mTotal = muxed.size.totalBytes;
      await _downloadYtStream(
        muxed,
        tmpMuxed,
        token,
        (rec, _) => _update(
          task.id,
          (t) => t.copyWith(
            receivedBytes: vTotal + rec,
            totalBytes: vTotal + mTotal,
            progress: (vTotal + mTotal) > 0
                ? ((vTotal + rec) / (vTotal + mTotal)).clamp(0.0, 0.94)
                : 0.9,
          ),
        ),
      );
      aTmp = p.join(workDir, 'audio_extracted.m4a');
      await _extractAudioToExt(tmpMuxed, aTmp, 'm4a');
    }

    _update(
      task.id,
      (t) => t.copyWith(
        status: DownloadTaskStatus.processing,
        progress: 0.96,
        statusDetail: 'muxing',
      ),
    );

    final out = _uniquePath(destDir, safeName, opt.ext);
    await _muxTracks(vTmp, aTmp, out);
    return out;
  }

  /// تحميل مباشر من رابط YouTube بأجزاء 512KB (نتفادى تعليق youtube_explode_dart عند 403).
  Future<void> _downloadYtStream(
    StreamInfo info,
    String outputPath,
    CancelToken token,
    void Function(int received, int total) onProgress,
  ) async {
    final total = info.size.totalBytes;
    if (total <= 0) {
      throw Exception('YouTube stream has empty content length');
    }

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    final url = info.url;
    final clientType = url.queryParameters['c'];
    final ua = clientType == 'IOS'
        ? 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)'
        : 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';

    const chunkSize = 512 * 1024;
    var received = 0;

    try {
      while (received < total) {
        if (token.isCancelled) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: url.toString()),
            reason: 'Cancelled',
          );
        }
        final end = math.min(received + chunkSize, total) - 1;
        final res = await _dio.get<List<int>>(
          url.toString(),
          cancelToken: token,
          options: Options(
            headers: {
              'User-Agent': ua,
              'Range': 'bytes=$received-$end',
            },
            responseType: ResponseType.bytes,
            validateStatus: (_) => true,
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 25),
          ),
        );

        final code = res.statusCode ?? 0;
        if (code != 200 && code != 206) {
          throw _YtHttpException(code);
        }
        final data = res.data;
        if (data == null || data.isEmpty) {
          throw Exception('Empty chunk from YouTube');
        }
        sink.add(data);
        received += data.length;
        onProgress(received, total);
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    await sink.close();
  }

  Future<void> _extractAudioToExt(
    String inputPath,
    String outputPath,
    String ext, {
    int bitrateBps = 0,
    bool fromMuxedFallback = false,
  }) async {
    final low = ext.toLowerCase();
    final kbps = bitrateBps > 0
        ? (bitrateBps / 1000).round().clamp(48, fromMuxedFallback ? 128 : 192)
        : 128;

    if (low == 'm4a') {
      // عند الاستخراج من MP4 المدمج، نسخ مسار AAC مباشرة يحفظ الحجم والجودة الأصلية بسرعة
      if (fromMuxedFallback && kbps >= 96) {
        try {
          await _runFfmpeg(['-y', '-i', inputPath, '-vn', '-c:a', 'copy', '-movflags', '+faststart', outputPath]);
          return;
        } catch (_) {}
      }
      try {
        await NativeBridge.instance.extractAudio(
          inputPath: inputPath,
          outputPath: outputPath,
        );
        return;
      } catch (_) {}
    }

    final codecArgs = switch (low) {
      'opus' => ['-c:a', 'libopus', '-b:a', '${kbps}k'],
      'mp3' => ['-c:a', 'libmp3lame', '-b:a', '${kbps}k'],
      'm4a' => ['-c:a', 'aac', '-b:a', '${kbps}k', '-movflags', '+faststart'],
      _ => ['-c:a', 'aac', '-b:a', '${kbps}k'],
    };
    await _runFfmpeg(['-y', '-i', inputPath, '-vn', ...codecArgs, outputPath]);
  }

  Future<void> _applyArtworkAndMetadata(
    DownloadTask task,
    String filePath,
    String workDir,
  ) async {
    final thumbUrl = task.thumbnailUrl;
    if (thumbUrl == null || thumbUrl.isEmpty) return;

    final bytes = await _fetchThumbnailBytes(thumbUrl);
    if (bytes == null || bytes.isEmpty) return;

    if (!task.option.isVideo) {
      final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
      final isPng = bytes.length >= 4 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47;
      final metaArgs = <String>[
        if (task.title.trim().isNotEmpty) ...['-metadata', 'title=${task.title.trim()}'],
        if (task.author != null && task.author!.trim().isNotEmpty) ...[
          '-metadata',
          'artist=${task.author!.trim()}',
        ],
      ];

      final taggedPath = p.join(workDir, 'tagged.$ext');
      try {
        if (ext == 'opus' || ext == 'ogg') {
          final b64 = _buildFlacPictureBase64(
            bytes,
            mime: isPng ? 'image/png' : 'image/jpeg',
          );
          await _runFfmpeg([
            '-y',
            '-i',
            filePath,
            '-c:a',
            'copy',
            '-metadata:s:a:0',
            'METADATA_BLOCK_PICTURE=$b64',
            ...metaArgs,
            taggedPath,
          ]);
        } else if (ext == 'm4a' || ext == 'mp3' || ext == 'flac') {
          final coverPath = p.join(workDir, isPng ? 'cover.png' : 'cover.jpg');
          await File(coverPath).writeAsBytes(bytes, flush: true);
          await _runFfmpeg([
            '-y',
            '-i',
            filePath,
            '-i',
            coverPath,
            '-map',
            '0:a',
            '-map',
            '1:v',
            '-c',
            'copy',
            '-disposition:v:0',
            'attached_pic',
            ...metaArgs,
            taggedPath,
          ]);
        }
        final taggedFile = File(taggedPath);
        if (await taggedFile.exists() && await taggedFile.length() > 0) {
          await taggedFile.copy(filePath);
        }
      } catch (_) {
        // لو الدمج فشل لصيغة معينة، نكمل ونحفظ الصورة في الكاش
      }
    }

    await Thumbnails.put(filePath, bytes);
  }

  Future<Uint8List?> _fetchThumbnailBytes(String rawUrl) async {
    final candidates = <String>[
      rawUrl,
      if (rawUrl.contains('/maxresdefault.jpg'))
        rawUrl.replaceFirst('/maxresdefault.jpg', '/hqdefault.jpg'),
    ];
    for (final u in candidates) {
      try {
        final res = await _dio.get<List<int>>(
          u,
          options: Options(
            responseType: ResponseType.bytes,
            validateStatus: (_) => true,
            receiveTimeout: const Duration(seconds: 12),
          ),
        );
        if (res.statusCode == 200 && res.data != null && res.data!.isNotEmpty) {
          return Uint8List.fromList(res.data!);
        }
      } catch (_) {}
    }
    return null;
  }

  String _buildFlacPictureBase64(Uint8List imgBytes, {String mime = 'image/jpeg'}) {
    final mimeBytes = ascii.encode(mime);
    final out = BytesBuilder();
    void writeU32(int v) {
      final bd = ByteData(4)..setUint32(0, v);
      out.add(bd.buffer.asUint8List());
    }

    writeU32(3); // Cover (front)
    writeU32(mimeBytes.length);
    out.add(mimeBytes);
    writeU32(0); // description length
    writeU32(0); // width
    writeU32(0); // height
    writeU32(0); // depth
    writeU32(0); // colors
    writeU32(imgBytes.length);
    out.add(imgBytes);
    return base64Encode(out.toBytes());
  }

  Future<void> _muxTracks(
    String videoPath,
    String audioPath,
    String outputPath,
  ) async {
    if (Platform.isIOS && outputPath.toLowerCase().endsWith('.mp4')) {
      try {
        await NativeBridge.instance.muxVideoAndAudio(
          videoPath: videoPath,
          audioPath: audioPath,
          outputPath: outputPath,
        );
        return;
      } catch (_) {
        // لو الكودك AV1/Opus ومش مدعوم في AVAssetExportSession نكمل بـ FFmpeg
      }
    }

    await _runFfmpeg([
      '-y',
      '-i',
      videoPath,
      '-i',
      audioPath,
      '-c',
      'copy',
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      outputPath,
    ]);
  }

  Future<void> _runFfmpeg(List<String> args) async {
    if (Platform.isIOS || Platform.isAndroid || Platform.isMacOS) {
      final done = Completer<void>();
      await FFmpegKit.executeWithArgumentsAsync(
        args,
        (FFmpegSession s) async {
          final rc = await s.getReturnCode();
          if (ReturnCode.isSuccess(rc)) {
            if (!done.isCompleted) done.complete();
          } else {
            final logs = await s.getAllLogsAsString();
            final tail = logs == null || logs.length <= 240
                ? (logs ?? 'FFmpeg failed ($rc)')
                : logs.substring(logs.length - 240);
            if (!done.isCompleted) done.completeError(Exception(tail.trim()));
          }
        },
      );
      return done.future;
    }

    final res = await Process.run('ffmpeg', args);
    if (res.exitCode != 0) {
      throw Exception('ffmpeg failed: ${res.stderr}');
    }
  }

  Future<String> _downloadHls(
    DownloadTask task,
    MediaFormatOption opt,
    String workDir,
    String destDir,
    String safeName,
    CancelToken token,
  ) async {
    final url = opt.url;
    if (url == null) throw Exception('Missing HLS URL');

    if (opt.needsAudioExtract) {
      final tmpBase = p.join(workDir, 'hls_src');
      final srcPath = await HlsDownloader.download(
        dio: _dio,
        playlistUrl: opt.audioPairUrl ?? url,
        outputBasePath: tmpBase,
        headers: opt.headers,
        cancelToken: token,
        onProgress: (prog, rec) => _update(
          task.id,
          (t) => t.copyWith(
            receivedBytes: rec,
            progress: (prog * 0.9).clamp(0.0, 0.9),
          ),
        ),
      );
      _update(
        task.id,
        (t) => t.copyWith(
          status: DownloadTaskStatus.processing,
          progress: 0.95,
          statusDetail: 'extracting_audio',
        ),
      );
      final out = _uniquePath(destDir, safeName, 'm4a');
      await NativeBridge.instance.extractAudio(inputPath: srcPath, outputPath: out);
      return out;
    }

    if (opt.audioPairUrl != null) {
      final vTmp = await HlsDownloader.download(
        dio: _dio,
        playlistUrl: url,
        outputBasePath: p.join(workDir, 'hls_v'),
        headers: opt.headers,
        cancelToken: token,
        onProgress: (prog, rec) => _update(
          task.id,
          (t) => t.copyWith(
            receivedBytes: rec,
            progress: (prog * 0.75).clamp(0.0, 0.75),
          ),
        ),
      );
      final aTmp = await HlsDownloader.download(
        dio: _dio,
        playlistUrl: opt.audioPairUrl!,
        outputBasePath: p.join(workDir, 'hls_a'),
        headers: opt.headers,
        cancelToken: token,
        onProgress: (prog, rec) => _update(
          task.id,
          (t) => t.copyWith(
            progress: (0.75 + prog * 0.2).clamp(0.75, 0.95),
          ),
        ),
      );
      if (vTmp.endsWith('.mp4') && aTmp.endsWith('.mp4')) {
        _update(
          task.id,
          (t) => t.copyWith(
            status: DownloadTaskStatus.processing,
            progress: 0.97,
            statusDetail: 'muxing',
          ),
        );
        final out = _uniquePath(destDir, safeName, 'mp4');
        await NativeBridge.instance.muxVideoAndAudio(
          videoPath: vTmp,
          audioPath: aTmp,
          outputPath: out,
        );
        return out;
      }
      final ext = p.extension(vTmp).replaceFirst('.', '');
      final out = _uniquePath(destDir, safeName, ext.isEmpty ? 'ts' : ext);
      await File(vTmp).copy(out);
      return out;
    }

    final tmpOut = await HlsDownloader.download(
      dio: _dio,
      playlistUrl: url,
      outputBasePath: p.join(workDir, 'hls_single'),
      headers: opt.headers,
      cancelToken: token,
      onProgress: (prog, rec) => _update(
        task.id,
        (t) => t.copyWith(receivedBytes: rec, progress: prog),
      ),
    );
    final ext = p.extension(tmpOut).replaceFirst('.', '');
    final out = _uniquePath(destDir, safeName, ext.isEmpty ? opt.ext : ext);
    await File(tmpOut).copy(out);
    return out;
  }

  Future<String> _downloadDirect(
    DownloadTask task,
    MediaFormatOption opt,
    String workDir,
    String destDir,
    String safeName,
    CancelToken token,
  ) async {
    final url = opt.url;
    if (url == null) throw Exception('Missing download URL');

    if (opt.needsAudioExtract) {
      final tmpVid = p.join(workDir, 'source.mp4');
      await _dio.download(
        url,
        tmpVid,
        cancelToken: token,
        options: Options(headers: opt.headers),
        onReceiveProgress: (rec, tot) => _update(
          task.id,
          (t) => t.copyWith(
            receivedBytes: rec,
            totalBytes: tot > 0 ? tot : opt.sizeBytes,
            progress: tot > 0 ? (rec / tot * 0.9).clamp(0.0, 0.9) : 0,
          ),
        ),
      );
      _update(
        task.id,
        (t) => t.copyWith(
          status: DownloadTaskStatus.processing,
          progress: 0.95,
          statusDetail: 'extracting_audio',
        ),
      );
      final out = _uniquePath(destDir, safeName, 'm4a');
      await NativeBridge.instance.extractAudio(inputPath: tmpVid, outputPath: out);
      return out;
    }

    final out = _uniquePath(destDir, safeName, opt.ext);
    await _dio.download(
      url,
      out,
      cancelToken: token,
      options: Options(headers: opt.headers),
      onReceiveProgress: (rec, tot) => _update(
        task.id,
        (t) => t.copyWith(
          receivedBytes: rec,
          totalBytes: tot > 0 ? tot : opt.sizeBytes,
          progress: tot > 0 ? (rec / tot).clamp(0.0, 1.0) : 0,
        ),
      ),
    );
    return out;
  }

  String _sanitizeFileName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'media_${DateTime.now().millisecondsSinceEpoch}';
    return cleaned.length > 90 ? cleaned.substring(0, 90).trim() : cleaned;
  }

  String _uniquePath(String dir, String base, String ext) {
    final cleanExt = ext.replaceFirst('.', '').toLowerCase();
    var candidate = p.join(dir, '$base.$cleanExt');
    var n = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir, '$base ($n).$cleanExt');
      n++;
    }
    return candidate;
  }
}

class _YtHttpException implements Exception {
  const _YtHttpException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'YouTube HTTP $statusCode';
}
