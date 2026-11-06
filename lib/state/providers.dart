import 'dart:collection';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import '../services/importer.dart' as importer;
import '../services/importer.dart' show ImportResult;
import '../services/library_scanner.dart';
import '../services/thumbnails.dart';

// ───────────────────────── المكتبة ─────────────────────────

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, List<MediaItem>>(LibraryNotifier.new);

class LibraryNotifier extends AsyncNotifier<List<MediaItem>> {
  @override
  Future<List<MediaItem>> build() => _scan();

  Future<List<MediaItem>> _scan() async =>
      compute(scanDirectory, await libraryRootPath());

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_scan);
  }

  Future<ImportResult> importFiles() async {
    final r = await importer.importFiles(await libraryRootPath());
    await refresh();
    return r;
  }

  Future<ImportResult> importFolder() async {
    final r = await importer.importFolder(await libraryRootPath());
    await refresh();
    return r;
  }
}

/// جذر المكتبة. iOS: Documents بتاع التطبيق (بيظهر في تطبيق «الملفات»).
/// غيره (للتجربة على Windows): فولدر Shaghal جوّه Documents.
Future<String> libraryRootPath() async {
  final docs = await getApplicationDocumentsDirectory();
  if (!Platform.isIOS) {
    final root = p.join(docs.path, 'Shaghal');
    Directory(root).createSync(recursive: true);
    return root;
  }
  // iOS بيعرض فولدر التطبيق في «الملفات» بس لما يبقى فيه ملف، فبنحط README.
  final readme = File(p.join(docs.path, 'README.txt'));
  if (!readme.existsSync()) {
    readme.writeAsStringSync(
      'Put your music and videos here (folders are kept).\n',
    );
  }
  return docs.path;
}

// ───────────────────────── الفرز والفلترة ─────────────────────────

enum SortMode { folder, date, name }

enum KindFilter { all, audio, video }

class SortModeNotifier extends Notifier<SortMode> {
  @override
  SortMode build() => SortMode.folder;
  void set(SortMode m) => state = m;
}

class KindFilterNotifier extends Notifier<KindFilter> {
  @override
  KindFilter build() => KindFilter.all;
  void set(KindFilter k) => state = k;
}

final sortModeProvider =
    NotifierProvider<SortModeNotifier, SortMode>(SortModeNotifier.new);
final kindFilterProvider =
    NotifierProvider<KindFilterNotifier, KindFilter>(KindFilterNotifier.new);

const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// مقارنة طبيعية: "track 2" قبل "track 10".
int naturalCompare(String a, String b) {
  final re = RegExp(r'(\d+|\D+)');
  final pa = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final pb = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final nx = int.tryParse(pa[i]);
    final ny = int.tryParse(pb[i]);
    final c = (nx != null && ny != null)
        ? nx.compareTo(ny)
        : pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

final sectionsProvider = Provider<AsyncValue<List<MediaSection>>>((ref) {
  final lib = ref.watch(libraryProvider);
  final sort = ref.watch(sortModeProvider);
  final kind = ref.watch(kindFilterProvider);

  return lib.whenData((all) {
    final items = all.where((i) {
      switch (kind) {
        case KindFilter.all:
          return true;
        case KindFilter.audio:
          return !i.isVideo;
        case KindFilter.video:
          return i.isVideo;
      }
    }).toList();

    switch (sort) {
      case SortMode.folder:
        final byFolder = SplayTreeMap<String, List<MediaItem>>(
          (a, b) => a.isEmpty
              ? (b.isEmpty ? 0 : -1)
              : (b.isEmpty ? 1 : naturalCompare(a, b)),
        );
        for (final i in items) {
          byFolder.putIfAbsent(i.folder, () => []).add(i);
        }
        return [
          for (final e in byFolder.entries)
            MediaSection(
              e.key.isEmpty ? 'المجلد الرئيسي' : e.key,
              e.value..sort((a, b) => naturalCompare(a.name, b.name)),
            ),
        ];
      case SortMode.date:
        items.sort((a, b) => b.modified.compareTo(a.modified));
        final groups = LinkedHashMap<String, List<MediaItem>>();
        for (final i in items) {
          final key = '${_months[i.modified.month - 1]} ${i.modified.year}';
          groups.putIfAbsent(key, () => []).add(i);
        }
        return [for (final e in groups.entries) MediaSection(e.key, e.value)];
      case SortMode.name:
        items.sort((a, b) => naturalCompare(a.name, b.name));
        return [if (items.isNotEmpty) MediaSection('كل الملفات', items)];
    }
  });
});

// ───────────────────────── المشغّل ─────────────────────────

class PlayerController {
  PlayerController() {
    player = Player();
    video = VideoController(player);
  }

  late final Player player;
  late final VideoController video;
  List<MediaItem> queue = const [];

  Future<void> playQueue(List<MediaItem> items, int index) async {
    queue = items;
    await _activateSession();
    await player.open(
      Playlist([for (final i in items) Media(i.path)], index: index),
    );
  }

  Future<void> _activateSession() async {
    if (!(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) return;
    try {
      await (await AudioSession.instance).setActive(true);
    } catch (_) {}
  }

  Future<void> dispose() => player.dispose();
}

final playerProvider = Provider<PlayerController>((ref) {
  final c = PlayerController();
  ref.onDispose(c.dispose);
  return c;
});

final currentItemProvider = StreamProvider<MediaItem?>((ref) {
  final c = ref.watch(playerProvider);
  return c.player.stream.playlist.map(
    (pl) => (pl.index >= 0 && pl.index < c.queue.length)
        ? c.queue[pl.index]
        : null,
  );
});

final playingProvider = StreamProvider<bool>(
    (ref) => ref.watch(playerProvider).player.stream.playing);
final positionProvider = StreamProvider<Duration>(
    (ref) => ref.watch(playerProvider).player.stream.position);
final durationProvider = StreamProvider<Duration>(
    (ref) => ref.watch(playerProvider).player.stream.duration);

/// مسار الصورة المصغّرة لملف (أو null). بتتولّد مرة واحدة وبتتخزّن.
final thumbProvider = FutureProvider.family<String?, String>(
  (ref, path) => Thumbnails.get(path),
);
