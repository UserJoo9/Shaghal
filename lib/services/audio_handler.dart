import 'dart:async';

import 'package:audio_service/audio_service.dart' hide MediaItem;
import 'package:audio_service/audio_service.dart' as svc show MediaItem;
import 'package:audio_session/audio_session.dart';
import 'package:path/path.dart' as p;

import '../services/thumbnails.dart';
import '../state/providers.dart' show PlayerController;

/// يربط مشغّل media_kit بـ Control Center وشاشة القفل وأزرار السماعات.
class ShaghalAudioHandler extends BaseAudioHandler with SeekHandler {
  ShaghalAudioHandler(this._c) {
    final pl = _c.player;
    pl.stream.playlist.listen((_) {
      _updateItem();
      _broadcast();
    });
    pl.stream.playing.listen((_) => _broadcast());
    pl.stream.rate.listen((_) => _broadcast());
    pl.stream.buffering.listen((_) => _broadcast());
    pl.stream.duration.listen((_) => _updateItem());
    pl.stream.position.listen((_) {
      // iOS بيكمّل العدّاد لوحده، فبنحدّثه كل ثانية بس (وده كمان بيلقط الـ seek).
      if (_sinceBroadcast.elapsedMilliseconds >= 1000) _broadcast();
    });
    _listenSession();
  }

  final PlayerController _c;
  final Stopwatch _sinceBroadcast = Stopwatch()..start();

  Future<void> _listenSession() async {
    final session = await AudioSession.instance;
    session.interruptionEventStream.listen((e) {
      if (e.begin) _c.player.pause(); // مكالمة أو تطبيق تاني خد الصوت
    });
    session.becomingNoisyEventStream.listen((_) => _c.player.pause()); // فصل السماعة
  }

  void _updateItem() {
    final i = _c.player.state.playlist.index;
    if (i < 0 || i >= _c.queue.length) return;
    final t = _c.queue[i];
    final d = _c.player.state.duration;
    final item = svc.MediaItem(
      id: t.path,
      title: t.name,
      artist: t.folder.isEmpty ? null : p.basename(t.folder), // الفولدر = الفنان
      duration: d == Duration.zero ? null : d,
      artUri: _art[t.path],
    );
    mediaItem.add(item);
    if (!_art.containsKey(t.path)) _loadArt(t.path, item);
  }

  final Map<String, Uri?> _art = {};

  /// غلاف الأغنية في Control Center بيتحمّل بعد ما الأغنية تبدأ.
  Future<void> _loadArt(String path, svc.MediaItem item) async {
    final file = await Thumbnails.get(path);
    _art[path] = file == null ? null : Uri.file(file);
    if (file != null && mediaItem.value?.id == path) {
      mediaItem.add(item.copyWith(artUri: _art[path]));
    }
  }

  void _broadcast() {
    if (_c.queue.isEmpty) return;
    _sinceBroadcast
      ..reset()
      ..start();
    final s = _c.player.state;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (s.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: s.buffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      playing: s.playing,
      updatePosition: s.position,
      bufferedPosition: s.buffer,
      speed: s.rate,
      queueIndex: s.playlist.index,
    ));
  }

  @override
  Future<void> play() async {
    try {
      await (await AudioSession.instance).setActive(true);
    } catch (_) {}
    await _c.player.play();
  }

  @override
  Future<void> pause() => _c.player.pause();

  @override
  Future<void> seek(Duration position) => _c.player.seek(position);

  @override
  Future<void> skipToNext() => _c.player.next();

  @override
  Future<void> skipToPrevious() => _c.player.previous();

  @override
  Future<void> stop() async {
    await _c.player.stop();
    await super.stop();
  }
}
