import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_design/liquid_design.dart' show LiquidGlassService;
import 'package:path/path.dart' as p;

import '../models/media_item.dart';
import '../services/importer.dart' show ImportResult;
import '../state/providers.dart';
import 'artwork.dart';
import 'glass.dart';
import 'now_playing.dart';

sealed class _Row {}

class _HeaderRow extends _Row {
  _HeaderRow(this.title, this.count);
  final String title;
  final int count;
}

class _TrackRow extends _Row {
  _TrackRow(this.item, this.queueIndex);
  final MediaItem item;
  final int queueIndex;
}

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(sectionsProvider);
    final sort = ref.watch(sortModeProvider);
    final kindTab = ref.watch(kindFilterProvider);
    final s = ref.watch(stringsProvider);
    final hasCurrent =
        ref.watch(currentItemProvider.select((v) => v.value != null));

    return Rtl(child: Scaffold(
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  const _Header(),
                  Expanded(
                    child: kindTab == KindFilter.settings
                        ? const _SettingsBody()
                        : kindTab == KindFilter.favorites
                        ? const _FavoritesBody()
                        : sort == SortMode.folder
                        ? const _FolderBody(path: '')
                        : sections.when(
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (e, _) =>
                                Center(child: Text('${s.t('حصل خطأ', 'Error')}: $e')),
                            data: (data) => _SectionList(sections: data),
                          ),
                  ),
                ],
              ),
              const _BottomFade(height: 230),
              if (hasCurrent)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.paddingOf(context).bottom + 86,
                  child: const MiniPlayer(),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 10,
                child: const Center(child: _NavBar()),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

/// تدرّج أسود تحت القايمة عشان الصفوف تختفي بنعومة قبل الشريط العايم.
class _BottomFade extends StatelessWidget {
  const _BottomFade({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                context.bg.withValues(alpha: 0),
                context.bg.withValues(alpha: 0.88),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط التابات الزجاجي: مزيكا / فيديو.
class _NavBar extends ConsumerWidget {
  const _NavBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(kindFilterProvider);
    final s = ref.watch(stringsProvider);

    Widget item(IconData icon, String label, KindFilter k) {
      final sel = kind == k;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(kindFilterProvider.notifier).set(k),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: sel
                  ? context.fgA(0.18)
                  : Colors.transparent,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 24, color: sel ? context.fg : context.fg54),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: sel ? context.fg : context.fg54,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 348,
      height: 66,
      child: Glass(
        interactive: true,
        radius: 33,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            item(Icons.music_note_rounded, s.t('المزيكا', 'Music'), KindFilter.audio),
            item(Icons.videocam_rounded, s.t('الفيديو', 'Videos'), KindFilter.video),
            item(Icons.favorite_rounded, s.t('المفضلة', 'Favorites'), KindFilter.favorites),
            item(Icons.settings_rounded, s.t('الإعدادات', 'Settings'), KindFilter.settings),
          ],
        ),
      ),
    );
  }
}

enum _Act {
  sortFolder,
  sortDate,
  sortName,
  kindAll,
  kindAudio,
  kindVideo,
  importFiles,
  importFolder,
  refresh,
}

TextStyle _sectionLabel(BuildContext c) => TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: c.fg54,
);

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(sortModeProvider);
    final kind = ref.watch(kindFilterProvider);
    final s = ref.watch(stringsProvider);
    if (kind == KindFilter.settings) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                s.t('الإعدادات', 'Settings'),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final isFav = kind == KindFilter.favorites;
    final count = isFav
        ? (ref.watch(favoriteItemsProvider).value?.length ?? 0)
        : (ref
                .watch(sectionsProvider)
                .value
                ?.fold<int>(0, (n, s) => n + s.items.length) ??
            0);

    final sortLabel = switch (sort) {
      SortMode.folder => s.t('فولدرات', 'Folders'),
      SortMode.date => s.t('التاريخ', 'Date'),
      SortMode.name => s.t('الاسم', 'Name'),
    };
    final kindLabel = switch (kind) {
      KindFilter.all => s.t('الكل', 'All'),
      KindFilter.audio => s.t('صوت', 'Audio'),
      KindFilter.video => s.t('فيديو', 'Video'),
      KindFilter.favorites => s.t('المفضلة', 'Favorites'),
      KindFilter.settings => s.t('الإعدادات', 'Settings'),
    };

    void onSelected(_Act a) {
      final lib = ref.read(libraryProvider.notifier);
      switch (a) {
        case _Act.sortFolder:
          ref.read(sortModeProvider.notifier).set(SortMode.folder);
        case _Act.sortDate:
          ref.read(sortModeProvider.notifier).set(SortMode.date);
        case _Act.sortName:
          ref.read(sortModeProvider.notifier).set(SortMode.name);
        case _Act.kindAll:
          ref.read(kindFilterProvider.notifier).set(KindFilter.all);
        case _Act.kindAudio:
          ref.read(kindFilterProvider.notifier).set(KindFilter.audio);
        case _Act.kindVideo:
          ref.read(kindFilterProvider.notifier).set(KindFilter.video);
        case _Act.importFiles:
          _import(context, s, lib.importFiles);
        case _Act.importFolder:
          _import(context, s, lib.importFolder);
        case _Act.refresh:
          lib.refresh();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFav ? s.t('المفضلة', 'Favorites') : s.t('المكتبة', 'Library'),
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isFav
                      ? '${s.t('المفضلة', 'Favorites')} · ${s.t('$count ملف', '$count files')}'
                      : '$sortLabel · $kindLabel · ${s.t('$count ملف', '$count files')}',
                  style: TextStyle(fontSize: 13, color: context.fg54),
                ),
              ],
            ),
          ),
          GlassIconButton(
            icon: Icons.more_horiz_rounded,
            size: 46,
            onPressed: () => _showMenu(context, s, sort, kind, onSelected),
          ),
        ],
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(text, style: _sectionLabel(context)),
      );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem(
    this.label, {
    required this.icon,
    this.checked = false,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color:
              checked ? context.fgA(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 46,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(icon, size: 21, color: context.fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (checked)
                      Icon(Icons.check_rounded, size: 20, color: context.fg),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
        child: Container(height: 0.5, color: context.fgA(0.22)),
      );
}

/// قايمة Liquid Glass: لوح زجاج واحد، عناصر بأيقونات، والمختار بيتظلّل بكبسولة.
Future<void> _showMenu(
  BuildContext context,
  S s,
  SortMode sort,
  KindFilter kind,
  void Function(_Act) onSelected,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 170),
    // fade بس: الـ transforms على الـ platform view النيتيف بتبوّظ الزجاج وقت الحركة
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (ctx, _, __) {
      void pick(_Act a) {
        Navigator.of(ctx).pop();
        onSelected(a);
      }

      return Rtl(
        child: SafeArea(
          child: Align(
            alignment: AlignmentDirectional.topEnd,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 66, 16, 0),
              child: SizedBox(
                width: 264,
                child: Glass(
                  radius: 32,
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MenuLabel(s.t('الفرز', 'Sort')),
                        _MenuItem(s.t('بالفولدرات', 'By folder'),
                            icon: Icons.folder_rounded,
                            checked: sort == SortMode.folder,
                            onTap: () => pick(_Act.sortFolder)),
                        _MenuItem(s.t('بالتاريخ', 'By date'),
                            icon: Icons.calendar_today_rounded,
                            checked: sort == SortMode.date,
                            onTap: () => pick(_Act.sortDate)),
                        _MenuItem(s.t('بالاسم', 'By name'),
                            icon: Icons.sort_by_alpha_rounded,
                            checked: sort == SortMode.name,
                            onTap: () => pick(_Act.sortName)),
                        const _MenuDivider(),
                        _MenuItem(s.t('استيراد ملفات', 'Import files'),
                            icon: Icons.audio_file_rounded,
                            onTap: () => pick(_Act.importFiles)),
                        _MenuItem(s.t('استيراد فولدر', 'Import folder'),
                            icon: Icons.create_new_folder_rounded,
                            onTap: () => pick(_Act.importFolder)),
                        _MenuItem(s.t('تحديث', 'Refresh'),
                            icon: Icons.refresh_rounded,
                            onTap: () => pick(_Act.refresh)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

void _toast(ScaffoldMessengerState m, String text) {
  m.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.transparent,
    elevation: 0,
    content: Glass(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Text(text, style: TextStyle(color: m.context.fg)),
    ),
  ));
}

/// بيوقّف حركة الخلفية وقت السكرول.
Widget _scrollWatch(WidgetRef ref, Widget child) {
  return NotificationListener<ScrollNotification>(
    onNotification: (n) {
      if (n is ScrollStartNotification) {
        ref.read(scrollingProvider.notifier).set(true);
      } else if (n is ScrollEndNotification) {
        ref.read(scrollingProvider.notifier).set(false);
      }
      return false;
    },
    child: child,
  );
}

Future<void> _import(
  BuildContext context,
  S s,
  Future<ImportResult> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await action();
    if (r.copied == 0 && r.skipped == 0) return; // اتلغى
    _toast(
      messenger,
      s.t('تم استيراد ${r.copied} ملف', 'Imported ${r.copied} files') +
          (r.skipped > 0
              ? s.t(' · اتخطّى ${r.skipped}', ' · skipped ${r.skipped}')
              : ''),
    );
  } catch (e) {
    _toast(messenger, '${s.t('فشل الاستيراد', 'Import failed')}: $e');
  }
}

class _FolderEntry {
  const _FolderEntry(this.name, this.path, this.count);
  final String name;
  final String path;
  final int count;
}

Widget _emptyMessage(BuildContext context, S s) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          s.t(
            'مفيش ملفات هنا.\nدوس على ⋯ فوق ← استيراد ملفات أو فولدر عشان تضيف ميديا.',
            'No files here.\nTap ⋯ above → Import files or folder to add media.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.7, color: context.fg70),
        ),
      ),
    );

/// محتوى فولدر: الفولدرات الفرعية الأول، وبعدها الأغاني اللي جواه مباشرة.
class _FolderBody extends ConsumerWidget {
  const _FolderBody({required this.path});
  final String path; // فاضي = الجذر

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final kind = ref.watch(kindFilterProvider);
    final s = ref.watch(stringsProvider);

    return lib.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('${s.t('حصل خطأ', 'Error')}: $e')),
      data: (all) {
        final target = path.isEmpty ? const <String>[] : p.split(path);
        final folders = <String, _FolderEntry>{};
        final tracks = <MediaItem>[];

        for (final i in all) {
          if (kind == KindFilter.audio && i.isVideo) continue;
          if (kind == KindFilter.video && !i.isVideo) continue;
          final parts = i.folder.isEmpty ? const <String>[] : p.split(i.folder);
          if (parts.length < target.length) continue;
          var inside = true;
          for (var k = 0; k < target.length; k++) {
            if (parts[k] != target[k]) {
              inside = false;
              break;
            }
          }
          if (!inside) continue;
          if (parts.length == target.length) {
            tracks.add(i);
          } else {
            final fp = p.joinAll(parts.sublist(0, target.length + 1));
            final old = folders[fp];
            folders[fp] =
                _FolderEntry(parts[target.length], fp, (old?.count ?? 0) + 1);
          }
        }

        final folderList = folders.values.toList()
          ..sort((a, b) => naturalCompare(a.name, b.name));
        tracks.sort((a, b) => naturalCompare(a.name, b.name));

        if (folderList.isEmpty && tracks.isEmpty) return _emptyMessage(context, s);

        return _scrollWatch(ref, ListView.builder(
          padding: EdgeInsets.fromLTRB(
            0,
            4,
            0,
            200 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: folderList.length + tracks.length,
          itemBuilder: (context, index) {
            if (index < folderList.length) {
              final f = folderList[index];
              return _FolderTile(
                entry: f,
                subtitle: s.t('${f.count} ملف', '${f.count} files'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FolderPage(path: f.path, title: f.name),
                  ),
                ),
              );
            }
            final t = index - folderList.length;
            final item = tracks[t];
            return _TrackTile(
              key: ValueKey(item.path),
              item: item,
              onTap: () async {
                await ref.read(playerProvider).playQueue(tracks, t);
                if (item.isVideo && context.mounted) openFullPlayer(context);
              },
            );
          },
        ));
      },
    );
  }
}

class FolderPage extends ConsumerWidget {
  const FolderPage({super.key, required this.path, required this.title});
  final String path;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasCurrent =
        ref.watch(currentItemProvider.select((v) => v.value != null));

    return Rtl(child: Scaffold(
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 20, 8),
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        GlassIconButton(
                          icon: Icons.chevron_left_rounded,
                          size: 46,
                          iconSize: 30,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: _FolderBody(path: path)),
                ],
              ),
              const _BottomFade(height: 150),
              if (hasCurrent)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.paddingOf(context).bottom + 8,
                  child: const MiniPlayer(),
                ),
            ],
          ),
        ),
      ),
    ));
  }
}

/// صف مسطّح بأسلوب iOS: من غير كروت، فاصل رفيع، وتظليل خفيف للصف الشغّال.
class _FlatRow extends StatelessWidget {
  const _FlatRow({required this.child, required this.onTap, this.active = false});
  final Widget child;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Material(
            color: active
                ? context.fgA(0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: child,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 88, end: 20),
          child: Container(height: 0.5, color: context.fgA(0.08)),
        ),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.entry,
    required this.subtitle,
    required this.onTap,
  });
  final _FolderEntry entry;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _FlatRow(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3A6BFF), Color(0xFF1B2A6B)],
              ),
            ),
            child: const Icon(Icons.folder_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: context.fg54),
                ),
              ],
            ),
          ),
          Icon(
            Directionality.of(context) == TextDirection.rtl
                ? Icons.chevron_left_rounded
                : Icons.chevron_right_rounded,
            color: context.fg38,
          ),
        ],
      ),
    );
  }
}

class _SectionList extends ConsumerWidget {
  const _SectionList({required this.sections});
  final List<MediaSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    if (sections.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            s.t(
              'مفيش ملفات لسه.\nانقل ملفاتك من تطبيق «الملفات» ← على iPhone ← Shaghal '
                  'وبعدها اضغط تحديث. الفولدرات هتتحفظ زي ما هي.',
              'No files yet.\nMove your files from the Files app → On My iPhone → Shaghal, '
                  'then tap Refresh. Folders are kept as they are.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.7, color: context.fg70),
          ),
        ),
      );
    }

    final rows = <_Row>[];
    final queue = <MediaItem>[];
    for (final s in sections) {
      rows.add(_HeaderRow(s.title, s.items.length));
      for (final i in s.items) {
        rows.add(_TrackRow(i, queue.length));
        queue.add(i);
      }
    }

    return _scrollWatch(ref, ListView.builder(
      padding: EdgeInsets.fromLTRB(
        0,
        4,
        0,
        200 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row) {
          _HeaderRow() => Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '${row.title}  ·  ${row.count}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.fg70,
                ),
              ),
            ),
          _TrackRow() => _TrackTile(
              key: ValueKey(row.item.path),
              item: row.item,
              onTap: () async {
                final c = ref.read(playerProvider);
                await c.playQueue(queue, row.queueIndex);
                if (row.item.isVideo && context.mounted) {
                  openFullPlayer(context);
                }
              },
            ),
        };
      },
    ));
  }
}

class _TrackTile extends ConsumerWidget {
  const _TrackTile({super.key, required this.item, required this.onTap});
  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      currentItemProvider.select((v) => v.value?.path == item.path),
    );

    final fav = ref.watch(
      favoritesProvider.select((f) => f.contains(favKey(item))),
    );

    return _FlatRow(
      active: active,
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Artwork(
                  path: item.path,
                  size: 56,
                  radius: 13,
                  isVideo: item.isVideo,
                ),
                if (active)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      color: Colors.black54,
                    ),
                    child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: active ? const Color(0xFF64B5FF) : context.fg,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.ext.toUpperCase()} · ${formatSize(item.size)}',
                  style: TextStyle(fontSize: 13, color: context.fg54),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(favoritesProvider.notifier).toggle(item),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 22,
                color: fav ? const Color(0xFFFF2D55) : context.fg38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _KindHeader {
  const _KindHeader(this.title, this.icon, this.count);
  final String title;
  final IconData icon;
  final int count;
}

/// تاب المفضلة: صوت ثم فيديو، وجوّه كل نوع الملفات متقسّمة بالفولدر (الفنان) ومترتبة بالاسم.
class _FavoritesBody extends ConsumerWidget {
  const _FavoritesBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favoriteItemsProvider);
    final s = ref.watch(stringsProvider);

    return fav.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('${s.t('حصل خطأ', 'Error')}: $e')),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                s.t(
                  'لسه مفيش مفضّلات.\nدوس على القلب ♥ جنب أي أغنية أو فيديو، أو من شاشة التشغيل، وهتلاقيه هنا.',
                  'No favorites yet.\nTap the heart ♥ next to any track or video, or in the player, and it will show up here.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.7, color: context.fg70),
              ),
            ),
          );
        }

        final rows = <Object>[];
        final queue = <MediaItem>[];

        void addKind(String title, IconData icon, List<MediaItem> list) {
          if (list.isEmpty) return;
          rows.add(_KindHeader(title, icon, list.length));
          final groups = <String, List<MediaItem>>{};
          for (final i in list) {
            groups.putIfAbsent(i.folder, () => []).add(i);
          }
          final keys = groups.keys.toList()
            ..sort((a, b) => a.isEmpty
                ? (b.isEmpty ? 0 : -1)
                : (b.isEmpty ? 1 : naturalCompare(a, b)));
          for (final k in keys) {
            final g = groups[k]!
              ..sort((a, b) => naturalCompare(a.name, b.name));
            rows.add(_HeaderRow(
                k.isEmpty ? s.t('المجلد الرئيسي', 'Main folder') : k, g.length));
            for (final i in g) {
              rows.add(_TrackRow(i, queue.length));
              queue.add(i);
            }
          }
        }

        addKind(s.t('المزيكا', 'Music'), Icons.music_note_rounded,
            items.where((i) => !i.isVideo).toList());
        addKind(s.t('الفيديو', 'Videos'), Icons.videocam_rounded,
            items.where((i) => i.isVideo).toList());

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            0,
            4,
            0,
            200 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row is _KindHeader) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 2),
                child: Row(
                  children: [
                    Icon(row.icon, size: 20, color: const Color(0xFF64B5FF)),
                    const SizedBox(width: 8),
                    Text(
                      '${row.title}  ·  ${row.count}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }
            if (row is _HeaderRow) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  '${row.title}  ·  ${row.count}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.fg70,
                  ),
                ),
              );
            }
            final t = row as _TrackRow;
            return _TrackTile(
              key: ValueKey(t.item.path),
              item: t.item,
              onTap: () async {
                await ref.read(playerProvider).playQueue(queue, t.queueIndex);
                if (t.item.isVideo && context.mounted) openFullPlayer(context);
              },
            );
          },
        );
      },
    );
  }
}


// ───────────────────────── الإعدادات ─────────────────────────

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(height: 0.5, color: context.fgA(0.10)),
        ));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(title, style: _sectionLabel(context)),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.fgA(0.07),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: context.fgA(0.10), width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(icon, size: 22, color: context.fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_rounded,
                      size: 22, color: Color(0xFF0A84FF)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(langProvider);
    final mode = ref.watch(themeModeProvider);
    final clear = ref.watch(glassClearProvider);
    final opacity = ref.watch(glassOpacityProvider);

    void setLang(AppLang l) {
      if (ref.read(langProvider) != l) ref.read(langProvider.notifier).toggle();
    }

    void setClear(bool c) {
      if (ref.read(glassClearProvider) != c) {
        ref.read(glassClearProvider.notifier).toggle();
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        200 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _SettingsGroup(
          title: s.t('اللغة', 'Language'),
          children: [
            _ChoiceRow(
              icon: Icons.translate_rounded,
              label: 'العربية',
              selected: lang == AppLang.ar,
              onTap: () => setLang(AppLang.ar),
            ),
            _ChoiceRow(
              icon: Icons.language_rounded,
              label: 'English',
              selected: lang == AppLang.en,
              onTap: () => setLang(AppLang.en),
            ),
          ],
        ),
        _SettingsGroup(
          title: s.t('المظهر', 'Appearance'),
          children: [
            _ChoiceRow(
              icon: Icons.dark_mode_rounded,
              label: s.t('داكن', 'Dark'),
              selected: mode == ThemeMode.dark,
              onTap: () =>
                  ref.read(themeModeProvider.notifier).set(ThemeMode.dark),
            ),
            _ChoiceRow(
              icon: Icons.light_mode_rounded,
              label: s.t('فاتح', 'Light'),
              selected: mode == ThemeMode.light,
              onTap: () =>
                  ref.read(themeModeProvider.notifier).set(ThemeMode.light),
            ),
            _ChoiceRow(
              icon: Icons.brightness_auto_rounded,
              label: s.t('زي النظام', 'System'),
              selected: mode == ThemeMode.system,
              onTap: () =>
                  ref.read(themeModeProvider.notifier).set(ThemeMode.system),
            ),
          ],
        ),
        _SettingsGroup(
          title: s.t('الزجاج (Liquid Glass)', 'Liquid Glass'),
          children: [
            _ChoiceRow(
              icon: Icons.blur_on_rounded,
              label: s.t('شفاف', 'Clear'),
              selected: clear,
              onTap: () => setClear(true),
            ),
            _ChoiceRow(
              icon: Icons.blur_circular_rounded,
              label: s.t('عادي (ضبابي)', 'Regular (frosted)'),
              selected: !clear,
              onTap: () => setClear(false),
            ),
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.opacity_rounded, size: 22, color: context.fg),
                    Expanded(
                      child: Slider(
                        value: opacity,
                        min: 0.3,
                        max: 1.0,
                        onChanged: (v) =>
                            ref.read(glassOpacityProvider.notifier).preview(v),
                        onChangeEnd: (_) =>
                            ref.read(glassOpacityProvider.notifier).save(),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(opacity * 100).round()}%',
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 13, color: context.fg54),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            s.t(
              'شفافية الزجاج النيتيف بتتأثر كمان بإعداد iPhone: الشاشة والسطوع ← Liquid Glass.',
              'Native glass also follows your iPhone setting: Display & Brightness → Liquid Glass.',
            ),
            style: TextStyle(fontSize: 12, height: 1.6, color: context.fg38),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: Text(
            'Glass: ${LiquidGlassService.isNativePlatform ? "native ✓" : "fallback ✗"}'
            ' · iOS ${LiquidGlassService.osMajorVersion}',
            style: TextStyle(fontSize: 11, color: context.fg38),
          ),
        ),
      ],
    );
  }
}
