import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_design/liquid_design.dart'
    show LiquidGlassService, LiquidGlassStyle;
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


// ───────────────────────── اللغة ─────────────────────────

enum AppLang { ar, en }

class LangNotifier extends Notifier<AppLang> {
  @override
  AppLang build() {
    _load();
    return AppLang.ar;
  }

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File(p.join(d.path, 'lang.txt'));
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists() && (await f.readAsString()).trim() == 'en') {
        state = AppLang.en;
      }
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = state == AppLang.ar ? AppLang.en : AppLang.ar;
    try {
      await (await _file()).writeAsString(state == AppLang.en ? 'en' : 'ar');
    } catch (_) {}
  }
}

final langProvider =
    NotifierProvider<LangNotifier, AppLang>(LangNotifier.new);

/// ترجمة بسيطة: s.t('عربي', 'English').
class S {
  const S(this.lang);
  final AppLang lang;
  bool get ar => lang == AppLang.ar;
  String t(String arabic, String english) => ar ? arabic : english;
}

final stringsProvider = Provider<S>((ref) => S(ref.watch(langProvider)));


// ───────────────────────── نمط الزجاج ─────────────────────────

/// true = زجاج شفاف (clear)، false = عادي (regular، ضبابي أكتر). بيتطبّق على كل الزجاج.
class GlassClearNotifier extends Notifier<bool> {
  @override
  bool build() {
    Future.microtask(() {
      _apply(state);
      _load();
    });
    return true;
  }

  void _apply(bool clear) {
    LiquidGlassService.instance
        .setStyle(clear ? LiquidGlassStyle.clear : LiquidGlassStyle.regular);
  }

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File(p.join(d.path, 'glass.txt'));
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final clear = (await f.readAsString()).trim() != 'regular';
        if (clear != state) {
          state = clear;
          _apply(clear);
        }
      }
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    _apply(state);
    try {
      await (await _file()).writeAsString(state ? 'clear' : 'regular');
    } catch (_) {}
  }
}

final glassClearProvider =
    NotifierProvider<GlassClearNotifier, bool>(GlassClearNotifier.new);


// ───────────────────────── المظهر وشفافية الزجاج ─────────────────────────

/// ملف إعدادات صغير (نص واحد) في مجلد التطبيق.
Future<File> _prefFile(String name) async {
  final d = await getApplicationSupportDirectory();
  await d.create(recursive: true);
  return File(p.join(d.path, name));
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    try {
      final f = await _prefFile('theme.txt');
      if (await f.exists()) {
        state = switch ((await f.readAsString()).trim()) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        };
      }
    } catch (_) {}
  }

  Future<void> set(ThemeMode m) async {
    state = m;
    try {
      await (await _prefFile('theme.txt')).writeAsString(m.name);
    } catch (_) {}
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// شفافية مادة الزجاج (0.3 – 1.0). 1.0 = الزجاج كامل الظهور.
class GlassOpacityNotifier extends Notifier<double> {
  @override
  double build() {
    Future.microtask(_load);
    return 1.0;
  }

  Future<void> _load() async {
    try {
      final f = await _prefFile('glassopacity.txt');
      if (await f.exists()) {
        final v = double.tryParse((await f.readAsString()).trim());
        if (v != null) {
          state = v.clamp(0.3, 1.0);
          LiquidGlassService.instance.setOpacity(state);
        }
      }
    } catch (_) {}
  }

  void preview(double v) {
    state = v.clamp(0.3, 1.0);
    LiquidGlassService.instance.setOpacity(state);
  }

  Future<void> save() async {
    try {
      await (await _prefFile('glassopacity.txt'))
          .writeAsString(state.toStringAsFixed(2));
    } catch (_) {}
  }
}

final glassOpacityProvider =
    NotifierProvider<GlassOpacityNotifier, double>(GlassOpacityNotifier.new);

// ───────────────────────── الفرز والفلترة ─────────────────────────

enum SortMode { folder, date, name }

enum KindFilter { all, audio, video, favorites, settings }

class SortModeNotifier extends Notifier<SortMode> {
  @override
  SortMode build() => SortMode.folder;
  void set(SortMode m) => state = m;
}

class KindFilterNotifier extends Notifier<KindFilter> {
  @override
  KindFilter build() => KindFilter.audio; // التابات: مزيكا / فيديو / مفضلة
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

const _monthsEn = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
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
  final s = ref.watch(stringsProvider);

  return lib.whenData((all) {
    final items = all.where((i) {
      switch (kind) {
        case KindFilter.all:
        case KindFilter.favorites:
        case KindFilter.settings:
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
              e.key.isEmpty ? s.t('المجلد الرئيسي', 'Main folder') : e.key,
              e.value..sort((a, b) => naturalCompare(a.name, b.name)),
            ),
        ];
      case SortMode.date:
        items.sort((a, b) => b.modified.compareTo(a.modified));
        final groups = LinkedHashMap<String, List<MediaItem>>();
        for (final i in items) {
          final m = (s.ar ? _months : _monthsEn)[i.modified.month - 1];
          final key = '$m ${i.modified.year}';
          groups.putIfAbsent(key, () => []).add(i);
        }
        return [for (final e in groups.entries) MediaSection(e.key, e.value)];
      case SortMode.name:
        items.sort((a, b) => naturalCompare(a.name, b.name));
        return [if (items.isNotEmpty) MediaSection(s.t('كل الملفات', 'All files'), items)];
    }
  });
});


// ───────────────────────── المفضلة ─────────────────────────

/// مفتاح ثابت للملف (الفولدر النسبي + اسم الملف) عشان المفضلة تفضل صح
/// حتى لو مسار الـ Documents على الجهاز اتغيّر بعد تحديث التطبيق.
String favKey(MediaItem i) =>
    p.posix.join(i.folder.replaceAll('\\', '/'), p.basename(i.path));

class FavoritesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _load();
    return <String>{};
  }

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    await d.create(recursive: true);
    return File(p.join(d.path, 'favorites.json'));
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        state = {...state, ...list.cast<String>()};
      }
    } catch (_) {}
  }

  Future<void> toggle(MediaItem item) async {
    final k = favKey(item);
    final next = {...state};
    if (!next.remove(k)) next.add(k);
    state = next;
    try {
      await (await _file()).writeAsString(jsonEncode(next.toList()));
    } catch (_) {}
  }
}

final favoritesProvider =
    NotifierProvider<FavoritesNotifier, Set<String>>(FavoritesNotifier.new);

/// كل الملفات المفضّلة (اللي لسه موجودة في المكتبة).
final favoriteItemsProvider = Provider<AsyncValue<List<MediaItem>>>((ref) {
  final lib = ref.watch(libraryProvider);
  final favs = ref.watch(favoritesProvider);
  return lib.whenData(
    (all) => all.where((i) => favs.contains(favKey(i))).toList(),
  );
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

// الـ streams بتاعة media_kit مش بتعيد آخر قيمة، فبنبدأ كل provider بالحالة الحالية
// (وإلا الوقت والمدة بيفضلوا 00:00 لو الصفحة اتفتحت بعد ما القيمة اتبعتت).
final currentItemProvider = StreamProvider<MediaItem?>((ref) async* {
  final c = ref.watch(playerProvider);
  MediaItem? at(int i) => (i >= 0 && i < c.queue.length) ? c.queue[i] : null;
  yield at(c.player.state.playlist.index);
  yield* c.player.stream.playlist.map((pl) => at(pl.index));
});

final playingProvider = StreamProvider<bool>((ref) async* {
  final pl = ref.watch(playerProvider).player;
  yield pl.state.playing;
  yield* pl.stream.playing;
});

final positionProvider = StreamProvider<Duration>((ref) async* {
  final pl = ref.watch(playerProvider).player;
  yield pl.state.position;
  yield* pl.stream.position;
});

final durationProvider = StreamProvider<Duration>((ref) async* {
  final pl = ref.watch(playerProvider).player;
  yield pl.state.duration;
  yield* pl.stream.duration;
});

/// true وقت ما المستخدم بيسكرول (الخلفية بتوقف حركتها عشان السكرول يفضل ناعم).
class ScrollingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) {
    if (state != v) state = v;
  }
}

final scrollingProvider =
    NotifierProvider<ScrollingNotifier, bool>(ScrollingNotifier.new);

/// مسار الصورة المصغّرة لملف (أو null). بتتولّد مرة واحدة وبتتخزّن.
final thumbProvider = FutureProvider.family<String?, String>(
  (ref, path) => Thumbnails.get(path),
);
