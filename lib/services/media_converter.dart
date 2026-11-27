import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/convert_item.dart';
import '../state/providers.dart';

final converterProvider =
    NotifierProvider<ConverterNotifier, List<ConvertTask>>(
  ConverterNotifier.new,
);

class ConverterNotifier extends Notifier<List<ConvertTask>> {
  final Queue<ConvertTask> _queue = Queue();
  final Map<String, int> _activeSessionIds = {};
  final Set<String> _cancelledIds = {};
  bool _processing = false;

  @override
  List<ConvertTask> build() => const [];

  void enqueueBatch(List<ConvertJobRequest> jobs) {
    if (jobs.isEmpty) return;
    final added = <ConvertTask>[];
    final now = DateTime.now();
    for (var i = 0; i < jobs.length; i++) {
      final j = jobs[i];
      final task = ConvertTask(
        id: '${now.microsecondsSinceEpoch}_${state.length}_$i',
        sourcePath: j.sourcePath,
        title: j.title,
        targetRelFolder: j.targetRelFolder,
        format: j.format,
        audioBitrateKbps: j.audioBitrateKbps,
        videoQuality: j.videoQuality,
        status: ConvertTaskStatus.queued,
        createdAt: now,
      );
      added.add(task);
      _queue.add(task);
    }
    state = [...added, ...state];
    unawaited(_drain());
  }

  Future<void> cancel(String id) async {
    _cancelledIds.add(id);
    final sid = _activeSessionIds[id];
    if (sid != null) {
      try {
        await FFmpegKit.cancel(sid);
      } catch (_) {}
    }
    _update(id, (t) => t.copyWith(status: ConvertTaskStatus.cancelled));
  }

  void remove(String id) {
    _cancelledIds.add(id);
    final sid = _activeSessionIds.remove(id);
    if (sid != null) {
      unawaited(FFmpegKit.cancel(sid));
    }
    state = state.where((t) => t.id != id).toList();
  }

  void clearFinished() {
    state = state
        .where((t) =>
            t.status == ConvertTaskStatus.queued ||
            t.status == ConvertTaskStatus.converting)
        .toList();
  }

  void _update(String id, ConvertTask Function(ConvertTask) fn) {
    state = [
      for (final t in state)
        if (t.id == id) fn(t) else t,
    ];
  }

  Future<void> _drain() async {
    if (_processing) return;
    _processing = true;
    var convertedAny = false;
    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeFirst();
        if (_cancelledIds.remove(task.id)) continue;
        final ok = await _runOne(task);
        if (ok) convertedAny = true;
      }
    } finally {
      _processing = false;
      if (convertedAny) {
        await ref.read(libraryProvider.notifier).refresh();
      }
    }
  }

  Future<bool> _runOne(ConvertTask task) async {
    try {
      _update(
        task.id,
        (t) => t.copyWith(status: ConvertTaskStatus.converting, progress: 0),
      );

      final root = await libraryRootPath();
      final destDir = Directory(p.join(root, task.targetRelFolder));
      await destDir.create(recursive: true);

      final baseName = p.basenameWithoutExtension(task.sourcePath);
      final outPath = _uniquePath(destDir.path, baseName, task.format.ext);

      final args = buildFfmpegArgs(
        inputPath: task.sourcePath,
        outputPath: outPath,
        format: task.format,
        audioBitrateKbps: task.audioBitrateKbps,
        videoQuality: task.videoQuality,
      );

      if (Platform.isIOS || Platform.isAndroid || Platform.isMacOS) {
        await _runWithFFmpegKit(task, args, outPath);
      } else {
        await _runWithDesktopFfmpeg(task, args, outPath);
      }

      if (_cancelledIds.contains(task.id)) {
        if (await File(outPath).exists()) await File(outPath).delete();
        return false;
      }

      _update(
        task.id,
        (t) => t.copyWith(
          status: ConvertTaskStatus.completed,
          progress: 1,
          outputPath: outPath,
        ),
      );
      return true;
    } catch (e) {
      if (_cancelledIds.contains(task.id)) return false;
      _update(
        task.id,
        (t) => t.copyWith(
          status: ConvertTaskStatus.failed,
          errorMessage: e.toString(),
        ),
      );
      return false;
    } finally {
      _activeSessionIds.remove(task.id);
    }
  }

  Future<void> _runWithFFmpegKit(
    ConvertTask task,
    List<String> args,
    String outPath,
  ) async {
    final durationMs = await _probeDurationMs(task.sourcePath);
    final done = Completer<void>();

    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (FFmpegSession s) async {
        final rc = await s.getReturnCode();
        if (ReturnCode.isSuccess(rc)) {
          if (!done.isCompleted) done.complete();
        } else if (ReturnCode.isCancel(rc)) {
          if (!done.isCompleted) done.completeError(Exception('Cancelled'));
        } else {
          final logs = await s.getAllLogsAsString();
          final tail = logs == null || logs.length <= 280
              ? (logs ?? 'Conversion failed ($rc)')
              : logs.substring(logs.length - 280);
          if (!done.isCompleted) done.completeError(Exception(tail.trim()));
        }
      },
      null,
      (stats) {
        if (durationMs > 0) {
          final prog = (stats.getTime() / durationMs).clamp(0.0, 0.99);
          _update(task.id, (t) => t.copyWith(progress: prog));
        }
      },
    );

    final sid = session.getSessionId();
    if (sid != null) {
      _activeSessionIds[task.id] = sid;
      if (_cancelledIds.contains(task.id)) {
        await FFmpegKit.cancel(sid);
      }
    }

    try {
      await done.future;
    } catch (_) {
      if (await File(outPath).exists()) await File(outPath).delete();
      rethrow;
    }
  }

  Future<int> _probeDurationMs(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = await session.getMediaInformation();
      final durStr = info?.getDuration();
      final secs = double.tryParse(durStr ?? '');
      if (secs != null && secs > 0) return (secs * 1000).round();
    } catch (_) {}
    return 0;
  }

  Future<void> _runWithDesktopFfmpeg(
    ConvertTask task,
    List<String> args,
    String outPath,
  ) async {
    final res = await Process.run('ffmpeg', args);
    if (res.exitCode != 0) {
      if (await File(outPath).exists()) await File(outPath).delete();
      throw Exception('ffmpeg failed: ${res.stderr}');
    }
  }

  static List<String> buildFfmpegArgs({
    required String inputPath,
    required String outputPath,
    required ConvertFormat format,
    required int audioBitrateKbps,
    required VideoQualityPreset videoQuality,
  }) {
    final br = '${audioBitrateKbps}k';

    if (!format.isVideo) {
      final codecArgs = switch (format.id) {
        'mp3' => ['-c:a', 'libmp3lame', '-b:a', br],
        'm4a' => ['-c:a', 'aac', '-b:a', br, '-movflags', '+faststart'],
        'aac' => ['-c:a', 'aac', '-b:a', br, '-f', 'adts'],
        'opus' => ['-c:a', 'libopus', '-b:a', br],
        'ogg' => ['-c:a', 'libvorbis', '-b:a', br],
        'flac' => ['-c:a', 'flac'],
        'wav' => ['-c:a', 'pcm_s16le'],
        'alac' => ['-c:a', 'alac', '-movflags', '+faststart'],
        'aiff' => ['-c:a', 'pcm_s16be'],
        'wma' => ['-c:a', 'wmav2', '-b:a', br],
        'ac3' => ['-c:a', 'ac3', '-b:a', br],
        _ => ['-b:a', br],
      };
      return ['-y', '-i', inputPath, '-vn', ...codecArgs, outputPath];
    }

    final maxH = switch (videoQuality) {
      VideoQualityPreset.original => null,
      VideoQualityPreset.p1080 => 1080,
      VideoQualityPreset.p720 => 720,
      VideoQualityPreset.p480 => 480,
      VideoQualityPreset.p360 => 360,
    };

    // أبعاد زوجية دائماً ومن غير تكبير للأصل
    final scaleFilter = maxH == null
        ? 'scale=trunc(iw/2)*2:trunc(ih/2)*2'
        : "scale='trunc(iw*min(1,$maxH/ih)/2)*2':'trunc(ih*min(1,$maxH/ih)/2)*2'";

    final codecArgs = switch (format.id) {
      'mp4' || 'm4v' || 'mov' => [
          '-vf',
          scaleFilter,
          '-c:v',
          'libx264',
          '-preset',
          'veryfast',
          '-crf',
          '21',
          '-pix_fmt',
          'yuv420p',
          '-c:a',
          'aac',
          '-b:a',
          '192k',
          '-movflags',
          '+faststart',
        ],
      'mkv' => [
          '-vf',
          scaleFilter,
          '-c:v',
          'libx264',
          '-preset',
          'veryfast',
          '-crf',
          '21',
          '-pix_fmt',
          'yuv420p',
          '-c:a',
          'aac',
          '-b:a',
          '192k',
        ],
      'ts' => [
          '-vf',
          scaleFilter,
          '-c:v',
          'libx264',
          '-preset',
          'veryfast',
          '-crf',
          '22',
          '-pix_fmt',
          'yuv420p',
          '-c:a',
          'aac',
          '-b:a',
          '160k',
          '-f',
          'mpegts',
        ],
      'webm' => [
          '-vf',
          scaleFilter,
          '-c:v',
          'libvpx',
          '-b:v',
          maxH != null && maxH <= 480 ? '900k' : '2200k',
          '-deadline',
          'realtime',
          '-cpu-used',
          '5',
          '-c:a',
          'libopus',
          '-b:a',
          '128k',
        ],
      'avi' => [
          '-vf',
          scaleFilter,
          '-c:v',
          'mpeg4',
          '-q:v',
          '4',
          '-c:a',
          'libmp3lame',
          '-b:a',
          '192k',
        ],
      'flv' => [
          '-vf',
          scaleFilter,
          '-c:v',
          'flv',
          '-q:v',
          '5',
          '-c:a',
          'aac',
          '-ar',
          '44100',
          '-b:a',
          '128k',
        ],
      '3gp' => [
          '-vf',
          'scale=352:288',
          '-c:v',
          'mpeg4',
          '-b:v',
          '400k',
          '-c:a',
          'aac',
          '-ar',
          '44100',
          '-ac',
          '1',
          '-b:a',
          '64k',
        ],
      _ => [
          '-vf',
          scaleFilter,
          '-c:v',
          'libx264',
          '-preset',
          'veryfast',
          '-c:a',
          'aac',
        ],
    };

    return ['-y', '-i', inputPath, ...codecArgs, outputPath];
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
