import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/download_item.dart';
import '../state/providers.dart';
import 'hls_downloader.dart';
import 'native_bridge.dart';

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
      _update(
        task.id,
        (t) => t.copyWith(
          status: DownloadTaskStatus.completed,
          progress: 1,
          outputPath: finalPath,
        ),
      );
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
    final yt = YoutubeExplode();
    try {
      // صوت فقط أو فيديو مدمج جاهز
      if (opt.ytVideoStream == null && opt.ytAudioStream != null) {
        final out = _uniquePath(destDir, safeName, opt.ext);
        await _pipeYtStream(
          yt,
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
      }

      final vStream = opt.ytVideoStream!;
      final aStream = opt.ytAudioStream;

      // فيديو مدمج جاهز (Muxed)
      if (aStream == null) {
        final out = _uniquePath(destDir, safeName, opt.ext);
        await _pipeYtStream(
          yt,
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
      final aTmp = p.join(workDir, 'audio.${aStream.container.name}');
      final vTotal = vStream.size.totalBytes;
      final aTotal = aStream.size.totalBytes;
      final combinedTotal = vTotal + aTotal;

      await _pipeYtStream(
        yt,
        vStream,
        vTmp,
        token,
        (rec, _) => _update(
          task.id,
          (t) => t.copyWith(
            receivedBytes: rec,
            totalBytes: combinedTotal,
            progress: combinedTotal > 0 ? (rec / combinedTotal).clamp(0.0, 0.92) : 0,
          ),
        ),
      );

      await _pipeYtStream(
        yt,
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

      _update(
        task.id,
        (t) => t.copyWith(
          status: DownloadTaskStatus.processing,
          progress: 0.96,
          statusDetail: 'muxing',
        ),
      );

      final out = _uniquePath(destDir, safeName, opt.ext);
      await NativeBridge.instance.muxVideoAndAudio(
        videoPath: vTmp,
        audioPath: aTmp,
        outputPath: out,
      );
      return out;
    } finally {
      yt.close();
    }
  }

  Future<void> _pipeYtStream(
    YoutubeExplode yt,
    StreamInfo info,
    String outputPath,
    CancelToken token,
    void Function(int received, int total) onProgress,
  ) async {
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    final total = info.size.totalBytes;
    var received = 0;

    try {
      await for (final chunk in yt.videos.streams.get(info)) {
        if (token.isCancelled) {
          throw Exception('Cancelled');
        }
        sink.add(chunk);
        received += chunk.length;
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
