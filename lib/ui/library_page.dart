import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/media_item.dart';
import '../services/importer.dart' show ImportResult;
import '../state/providers.dart';
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
    final hasCurrent =
        ref.watch(currentItemProvider.select((v) => v.value != null));

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  const _Header(),
                  Expanded(
                    child: sort == SortMode.folder
                        ? const _FolderBody(path: '')
                        : sections.when(
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (e, _) =>
                                Center(child: Text('حصل خطأ: $e')),
                            data: (data) => _SectionList(sections: data),
                          ),
                  ),
                ],
              ),
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

const _sectionLabel = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: Colors.white54,
);

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          Text(label),
        ],
      );
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(sortModeProvider);
    final kind = ref.watch(kindFilterProvider);
    final count = ref
            .watch(sectionsProvider)
            .value
            ?.fold<int>(0, (n, s) => n + s.items.length) ??
        0;

    final sortLabel = switch (sort) {
      SortMode.folder => 'فولدرات',
      SortMode.date => 'التاريخ',
      SortMode.name => 'الاسم',
    };
    final kindLabel = switch (kind) {
      KindFilter.all => 'الكل',
      KindFilter.audio => 'صوت',
      KindFilter.video => 'فيديو',
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
          _import(context, lib.importFiles);
        case _Act.importFolder:
          _import(context, lib.importFolder);
        case _Act.refresh:
          lib.refresh();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Glass(
        radius: 30,
        padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'المكتبة',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$sortLabel · $kindLabel · $count ملف',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_Act>(
                  icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
                  padding: EdgeInsets.zero,
                  color: const Color(0xF2141414),
                  elevation: 12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  onSelected: onSelected,
                  itemBuilder: (_) => [
                    const PopupMenuItem<_Act>(
                      enabled: false,
                      height: 32,
                      child: Text('الفرز', style: _sectionLabel),
                    ),
                    CheckedPopupMenuItem<_Act>(
                      value: _Act.sortFolder,
                      checked: sort == SortMode.folder,
                      child: const Text('بالفولدرات'),
                    ),
                    CheckedPopupMenuItem<_Act>(
                      value: _Act.sortDate,
                      checked: sort == SortMode.date,
                      child: const Text('بالتاريخ'),
                    ),
                    CheckedPopupMenuItem<_Act>(
                      value: _Act.sortName,
                      checked: sort == SortMode.name,
                      child: const Text('بالاسم'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<_Act>(
                      enabled: false,
                      height: 32,
                      child: Text('النوع', style: _sectionLabel),
                    ),
                    CheckedPopupMenuItem<_Act>(
                      value: _Act.kindAll,
                      checked: kind == KindFilter.all,
                      child: const Text('الكل'),
                    ),
                    CheckedPopupMenuItem<_Act>(
                      value: _Act.kindAudio,
                      checked: kind == KindFilter.audio,
                      child: const Text('صوت'),
                    ),
                    CheckedPopupMenuItem<_Act>(
                      value: _Act.kindVideo,
                      checked: kind == KindFilter.video,
                      child: const Text('فيديو'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<_Act>(
                      value: _Act.importFiles,
                      child: _MenuRow(Icons.audio_file_rounded, 'استيراد ملفات'),
                    ),
                    const PopupMenuItem<_Act>(
                      value: _Act.importFolder,
                      child: _MenuRow(
                        Icons.create_new_folder_rounded,
                        'استيراد فولدر',
                      ),
                    ),
                    const PopupMenuItem<_Act>(
                      value: _Act.refresh,
                      child: _MenuRow(Icons.refresh_rounded, 'تحديث'),
                    ),
                  ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _import(
  BuildContext context,
  Future<ImportResult> Function() action,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await action();
    if (r.copied == 0 && r.skipped == 0) return; // اتلغى
    messenger.showSnackBar(SnackBar(
      content: Text(
        'تم استيراد ${r.copied} ملف'
        '${r.skipped > 0 ? ' · اتخطّى ${r.skipped}' : ''}',
      ),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('فشل الاستيراد: $e')));
  }
}

class _FolderEntry {
  const _FolderEntry(this.name, this.path, this.count);
  final String name;
  final String path;
  final int count;
}

const _emptyMessage = Center(
  child: Padding(
    padding: EdgeInsets.all(32),
    child: Text(
      'مفيش ملفات هنا.\nدوس على ⋯ فوق ← استيراد ملفات أو فولدر عشان تضيف ميديا.',
      textAlign: TextAlign.center,
      style: TextStyle(height: 1.7, color: Colors.white70),
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

    return lib.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('حصل خطأ: $e')),
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

        if (folderList.isEmpty && tracks.isEmpty) return _emptyMessage;

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            12,
            4,
            12,
            120 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: folderList.length + tracks.length,
          itemBuilder: (context, index) {
            if (index < folderList.length) {
              final f = folderList[index];
              return _FolderTile(
                entry: f,
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
        );
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

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Glass(
                      radius: 30,
                      padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: Colors.white,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: _FolderBody(path: path)),
                ],
              ),
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
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.entry, required this.onTap});
  final _FolderEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                  child: const Icon(Icons.folder_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.count} ملف',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left_rounded, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionList extends ConsumerWidget {
  const _SectionList({required this.sections});
  final List<MediaSection> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sections.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'مفيش ملفات لسه.\nانقل ملفاتك من تطبيق «الملفات» ← على iPhone ← Shaghal '
            'وبعدها اضغط تحديث. الفولدرات هتتحفظ زي ما هي.',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.7, color: Colors.white70),
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

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        12,
        4,
        12,
        120 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row) {
          _HeaderRow() => Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
              child: Text(
                '${row.title}  ·  ${row.count}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
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
    );
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
    final d = item.modified;
    final date =
        '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.white.withValues(alpha: active ? 0.20 : 0.07),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    active
                        ? Icons.graphic_eq_rounded
                        : (item.isVideo
                            ? Icons.movie_rounded
                            : Icons.music_note_rounded),
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.ext} · ${formatSize(item.size)} · $date',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
