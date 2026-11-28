import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/media_formats.dart';
import '../models/convert_item.dart';
import '../models/media_item.dart';
import '../services/media_converter.dart';
import '../state/providers.dart';
import 'glass.dart';
import 'now_playing.dart';

class ConverterBody extends ConsumerStatefulWidget {
  const ConverterBody({super.key});

  @override
  ConsumerState<ConverterBody> createState() => _ConverterBodyState();
}

class _ConverterBodyState extends ConsumerState<ConverterBody> {
  ConvertKind _kind = ConvertKind.audio;
  bool _folderMode = true; // true = فولدر كامل، false = ملف ملف
  ConvertFormat _format = ConvertFormat.audioFormats.first;
  int _bitrateKbps = 192;
  VideoQualityPreset _videoQuality = VideoQualityPreset.original;

  // اختيار فولدر كامل (من المكتبة أو من الجهاز)
  String? _selectedLibFolder;
  String? _externalFolderPath;
  List<String> _externalFolderFiles = const [];

  // اختيار ملفات فردانية
  final List<({String path, String name})> _selectedFiles = [];
  final _newFolderCtrl = TextEditingController();
  bool _newFolderEdited = false;

  @override
  void initState() {
    super.initState();
    _suggestNewFolderName();
  }

  @override
  void dispose() {
    _newFolderCtrl.dispose();
    super.dispose();
  }

  Future<void> _suggestNewFolderName() async {
    if (_newFolderEdited) return;
    final base = _kind == ConvertKind.audio
        ? 'Converted ${_format.label.split(' ').first}'
        : 'Converted ${_format.label.split(' ').first}';
    try {
      final root = await libraryRootPath();
      var candidate = base;
      var n = 2;
      while (Directory(p.join(root, candidate)).existsSync()) {
        candidate = '$base ($n)';
        n++;
      }
      if (mounted && !_newFolderEdited) {
        _newFolderCtrl.text = candidate;
      }
    } catch (_) {
      if (mounted && !_newFolderEdited) _newFolderCtrl.text = base;
    }
  }

  void _setKind(ConvertKind k) {
    if (_kind == k) return;
    setState(() {
      _kind = k;
      _format = k == ConvertKind.audio
          ? ConvertFormat.audioFormats.first
          : ConvertFormat.videoFormats.first;
      _selectedLibFolder = null;
      _externalFolderPath = null;
      _externalFolderFiles = const [];
      _selectedFiles.clear();
      _newFolderEdited = false;
    });
    _suggestNewFolderName();
  }

  Future<void> _pickExternalFolder(S s) async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final files = <String>[];
    await for (final e
        in Directory(dir).list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final isVid = MediaFormats.isVideo(e.path);
      if (isVid == null) continue;
      if (_kind == ConvertKind.audio && isVid) continue;
      if (_kind == ConvertKind.video && !isVid) continue;
      files.add(e.path);
    }
    if (!mounted) return;
    if (files.isEmpty) {
      _toast(s.t(
        'مفيش ملفات ${_kind == ConvertKind.audio ? 'صوت' : 'فيديو'} في الفولدر ده',
        'No ${_kind == ConvertKind.audio ? 'audio' : 'video'} files in that folder',
      ));
      return;
    }
    setState(() {
      _selectedLibFolder = null;
      _externalFolderPath = dir;
      _externalFolderFiles = files;
    });
  }

  Future<void> _pickLibraryFiles(List<MediaItem> all, S s) async {
    final candidates = all
        .where((i) => _kind == ConvertKind.audio ? !i.isVideo : i.isVideo)
        .toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));
    if (candidates.isEmpty) {
      _toast(s.t('مفيش ملفات متاحة في المكتبة', 'No matching files in library'));
      return;
    }

    final chosen = await showModalBottomSheet<List<MediaItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _MultiFilePickerSheet(
        items: candidates,
        initialPaths: {for (final f in _selectedFiles) f.path},
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      for (final item in chosen) {
        if (!_selectedFiles.any((f) => f.path == item.path)) {
          _selectedFiles.add((path: item.path, name: item.name));
        }
      }
    });
  }

  Future<void> _pickExternalFiles(S s) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (res == null || !mounted) return;
    var added = 0;
    setState(() {
      for (final f in res.files) {
        final path = f.path;
        if (path == null) continue;
        final isVid = MediaFormats.isVideo(path);
        if (isVid == null) continue;
        if (_kind == ConvertKind.audio && isVid) continue;
        if (_kind == ConvertKind.video && !isVid) continue;
        if (!_selectedFiles.any((x) => x.path == path)) {
          _selectedFiles.add((
            path: path,
            name: p.basenameWithoutExtension(path),
          ));
          added++;
        }
      }
    });
    if (added == 0) {
      _toast(s.t(
        'اختار ملفات ${_kind == ConvertKind.audio ? 'صوت' : 'فيديو'} صالحة',
        'Select valid ${_kind == ConvertKind.audio ? 'audio' : 'video'} files',
      ));
    }
  }

  Future<void> _startConversion(List<MediaItem> all, S s) async {
    final jobs = <ConvertJobRequest>[];

    if (_folderMode) {
      if (_selectedLibFolder != null) {
        final baseOut = '${_selectedLibFolder!} converted';
        final matching = all.where((i) {
          final kindMatch =
              _kind == ConvertKind.audio ? !i.isVideo : i.isVideo;
          if (!kindMatch) return false;
          return i.folder == _selectedLibFolder ||
              i.folder.startsWith('${_selectedLibFolder!}/') ||
              i.folder.startsWith('${_selectedLibFolder!}\\');
        }).toList()
          ..sort((a, b) => naturalCompare(a.name, b.name));

        for (final item in matching) {
          final relSub = p.relative(item.folder, from: _selectedLibFolder!);
          final targetFolder =
              relSub == '.' ? baseOut : p.join(baseOut, relSub);
          jobs.add(ConvertJobRequest(
            sourcePath: item.path,
            title: item.name,
            targetRelFolder: targetFolder,
            format: _format,
            audioBitrateKbps: _bitrateKbps,
            videoQuality: _videoQuality,
          ));
        }
      } else if (_externalFolderPath != null &&
          _externalFolderFiles.isNotEmpty) {
        final baseOut = '${p.basename(_externalFolderPath!)} converted';
        for (final filePath in _externalFolderFiles) {
          final relDir =
              p.relative(p.dirname(filePath), from: _externalFolderPath!);
          final targetFolder =
              relDir == '.' ? baseOut : p.join(baseOut, relDir);
          jobs.add(ConvertJobRequest(
            sourcePath: filePath,
            title: p.basenameWithoutExtension(filePath),
            targetRelFolder: targetFolder,
            format: _format,
            audioBitrateKbps: _bitrateKbps,
            videoQuality: _videoQuality,
          ));
        }
      }
    } else {
      if (_selectedFiles.isEmpty) {
        _toast(s.t('اختار ملف واحد على الأقل', 'Select at least one file'));
        return;
      }
      var newFolder = _newFolderCtrl.text
          .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
          .trim();
      if (newFolder.isEmpty) {
        newFolder = 'Converted ${_format.label.split(' ').first}';
      }
      for (final f in _selectedFiles) {
        jobs.add(ConvertJobRequest(
          sourcePath: f.path,
          title: f.name,
          targetRelFolder: newFolder,
          format: _format,
          audioBitrateKbps: _bitrateKbps,
          videoQuality: _videoQuality,
        ));
      }
    }

    if (jobs.isEmpty) {
      _toast(s.t('مفيش ملفات محددة للتحويل', 'No files selected to convert'));
      return;
    }

    ref.read(converterProvider.notifier).enqueueBatch(jobs);
    _toast(s.t(
      'بدأ تحويل ${jobs.length} ملف إلى ${_format.label}',
      'Started converting ${jobs.length} files to ${_format.label}',
    ));

    setState(() {
      if (!_folderMode) {
        _selectedFiles.clear();
        _newFolderEdited = false;
      }
    });
    _suggestNewFolderName();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: Glass(
        radius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Text(text, style: TextStyle(color: context.fg)),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final all = ref.watch(libraryProvider).value ?? const <MediaItem>[];
    final tasks = ref.watch(converterProvider);
    final hasCurrent =
        ref.watch(currentItemProvider.select((v) => v.value != null));

    // الفولدرات المتاحة حسب النوع (صوت أو فيديو)
    final folderCounts = <String, int>{};
    for (final i in all) {
      final match = _kind == ConvertKind.audio ? !i.isVideo : i.isVideo;
      if (!match || i.folder.isEmpty) continue;
      folderCounts[i.folder] = (folderCounts[i.folder] ?? 0) + 1;
    }
    final libFolders = folderCounts.keys.toList()..sort(naturalCompare);

    final formatList = _kind == ConvertKind.audio
        ? ConvertFormat.audioFormats
        : [...ConvertFormat.videoFormats, ...ConvertFormat.audioFormats];

    final outFolderPreview = _folderMode
        ? (_selectedLibFolder != null
            ? '${_selectedLibFolder!} converted'
            : (_externalFolderPath != null
                ? '${p.basename(_externalFolderPath!)} converted'
                : null))
        : (_newFolderCtrl.text.trim().isEmpty
            ? 'Converted'
            : _newFolderCtrl.text.trim());

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        (hasCurrent ? 200 : 120) + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        // 1. صوت أم فيديو
        Glass(
          radius: 22,
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: _SegPill(
                  icon: Icons.music_note_rounded,
                  label: s.t('تحويل صوت', 'Audio'),
                  active: _kind == ConvertKind.audio,
                  onTap: () => _setKind(ConvertKind.audio),
                ),
              ),
              Expanded(
                child: _SegPill(
                  icon: Icons.videocam_rounded,
                  label: s.t('تحويل فيديو', 'Video'),
                  active: _kind == ConvertKind.video,
                  onTap: () => _setKind(ConvertKind.video),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. اختيار فولدر كامل أو ملفات فردية
        Glass(
          radius: 26,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.t('طريقة التنظيم والتحديد', 'Selection & Organization'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.fg54,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: context.fgA(0.06),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _SegPill(
                        icon: Icons.folder_copy_rounded,
                        label: s.t('فولدر كامل', 'Whole folder'),
                        active: _folderMode,
                        onTap: () => setState(() => _folderMode = true),
                      ),
                    ),
                    Expanded(
                      child: _SegPill(
                        icon: Icons.checklist_rounded,
                        label: s.t('ملف ملف', 'Select files'),
                        active: !_folderMode,
                        onTap: () => setState(() => _folderMode = false),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_folderMode) ...[
                Text(
                  s.t(
                    'اختر فولدراً لتحويل كل محتوياته دفعة واحدة (يُحفظ في فولدر بنفس الاسم + converted):',
                    'Pick a folder to convert all its files at once (saved in "<name> converted"):',
                  ),
                  style: TextStyle(fontSize: 12, color: context.fg54),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in libFolders)
                      ChoiceChip(
                        avatar: const Icon(Icons.folder_rounded, size: 17),
                        label: Text(
                          '${f == kDownloadsFolder ? s.t('التحميلات', 'Downloads') : f} (${folderCounts[f]})',
                        ),
                        selected: _selectedLibFolder == f,
                        onSelected: (_) => setState(() {
                          _selectedLibFolder = f;
                          _externalFolderPath = null;
                          _externalFolderFiles = const [];
                        }),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.drive_folder_upload_rounded,
                          size: 17),
                      label: Text(s.t('فولدر من الجهاز...', 'Device folder...')),
                      onPressed: () => _pickExternalFolder(s),
                    ),
                  ],
                ),
                if (_externalFolderPath != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${p.basename(_externalFolderPath!)} · ${s.t('${_externalFolderFiles.length} ملف', '${_externalFolderFiles.length} files')}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0A84FF),
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  s.t(
                    'اختر الملفات الفردية (ستُحفظ معاً في فولدر جديد):',
                    'Pick individual files (saved together into a new folder):',
                  ),
                  style: TextStyle(fontSize: 12, color: context.fg54),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickLibraryFiles(all, s),
                        icon: const Icon(Icons.library_music_rounded, size: 18),
                        label: Text(s.t('من المكتبة', 'From library')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickExternalFiles(s),
                        icon: const Icon(Icons.attach_file_rounded, size: 18),
                        label: Text(s.t('من الملفات', 'From Files')),
                      ),
                    ),
                  ],
                ),
                if (_selectedFiles.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final f in _selectedFiles)
                        InputChip(
                          label: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onDeleted: () => setState(() {
                            _selectedFiles.removeWhere((x) => x.path == f.path);
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _newFolderCtrl,
                  onChanged: (_) => _newFolderEdited = true,
                  style: TextStyle(color: context.fg, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: s.t('اسم الفولدر الجديد', 'New output folder name'),
                    prefixIcon: const Icon(Icons.create_new_folder_rounded),
                    filled: true,
                    fillColor: context.fgA(0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
              if (outFolderPreview != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A84FF).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_special_rounded,
                          size: 18, color: Color(0xFF64B5FF)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.t('مسار الحفظ:', 'Output folder:')} $outFolderPreview',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. الصيغة المطلوبة والجودة
        Glass(
          radius: 26,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.t('الصيغة المستهدفة', 'Target Format'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.fg54,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final fmt in formatList)
                    ChoiceChip(
                      label: Text(fmt.label),
                      selected: _format.id == fmt.id,
                      onSelected: (_) {
                        setState(() => _format = fmt);
                        _suggestNewFolderName();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!_format.isVideo && !_format.isLossless) ...[
                Text(
                  s.t('جودة الصوت (Bitrate)', 'Audio Bitrate'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.fg54,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final br in const [320, 256, 192, 128, 96, 64])
                      ChoiceChip(
                        label: Text('$br kbps'),
                        selected: _bitrateKbps == br,
                        onSelected: (_) => setState(() => _bitrateKbps = br),
                      ),
                  ],
                ),
              ] else if (_format.isVideo) ...[
                Text(
                  s.t('دقة الفيديو', 'Video Resolution'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.fg54,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final q in VideoQualityPreset.values)
                      ChoiceChip(
                        label: Text(switch (q) {
                          VideoQualityPreset.original =>
                            s.t('الأصلية', 'Original'),
                          VideoQualityPreset.p1080 => '1080p',
                          VideoQualityPreset.p720 => '720p',
                          VideoQualityPreset.p480 => '480p',
                          VideoQualityPreset.p360 => '360p',
                        }),
                        selected: _videoQuality == q,
                        onSelected: (_) => setState(() => _videoQuality = q),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _startConversion(all, s),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0A84FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.transform_rounded),
                label: Text(
                  s.t('بدء التحويل', 'Start Conversion'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 4. قائمة التحويلات
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              s.t('عمليات التحويل', 'Conversion Queue'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.fg54,
              ),
            ),
            if (tasks.any((t) =>
                t.status == ConvertTaskStatus.completed ||
                t.status == ConvertTaskStatus.failed ||
                t.status == ConvertTaskStatus.cancelled))
              TextButton(
                onPressed: () =>
                    ref.read(converterProvider.notifier).clearFinished(),
                child: Text(s.t('مسح المكتمل', 'Clear finished')),
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              s.t(
                'حدد فولدراً أو ملفات فوق واضغط «بدء التحويل».',
                'Select a folder or files above and tap Start Conversion.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.fg54),
            ),
          )
        else
          for (final t in tasks) ...[
            _ConvertTaskTile(task: t),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SegPill extends StatelessWidget {
  const _SegPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: active ? context.fgA(0.16) : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: active ? context.fg : context.fg54),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? context.fg : context.fg54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConvertTaskTile extends ConsumerWidget {
  const _ConvertTaskTile({required this.task});
  final ConvertTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final mgr = ref.read(converterProvider.notifier);
    final srcExt =
        p.extension(task.sourcePath).replaceFirst('.', '').toUpperCase();

    final statusText = switch (task.status) {
      ConvertTaskStatus.queued => s.t('في الانتظار', 'Queued'),
      ConvertTaskStatus.converting => '${(task.progress * 100).round()}%',
      ConvertTaskStatus.completed =>
        '${s.t('مكتمل في', 'Saved in')} ${task.targetRelFolder}',
      ConvertTaskStatus.failed =>
        '${s.t('فشل التحويل', 'Failed')}: ${task.errorMessage ?? ''}',
      ConvertTaskStatus.cancelled => s.t('تم الإلغاء', 'Cancelled'),
    };

    return Glass(
      radius: 22,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: context.fgA(0.10),
                ),
                child: const Icon(Icons.transform_rounded,
                    color: Color(0xFF0A84FF)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$srcExt → ${task.format.label} · 📁 ${task.targetRelFolder}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.fg54),
                    ),
                  ],
                ),
              ),
              if (task.status == ConvertTaskStatus.converting ||
                  task.status == ConvertTaskStatus.queued)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => mgr.cancel(task.id),
                )
              else
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: context.fg54),
                  onPressed: () => mgr.remove(task.id),
                ),
            ],
          ),
          if (task.status == ConvertTaskStatus.converting) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress > 0 ? task.progress.clamp(0.0, 1.0) : null,
                minHeight: 5,
                backgroundColor: context.fgA(0.12),
                color: const Color(0xFF0A84FF),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  statusText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: task.status == ConvertTaskStatus.failed
                        ? const Color(0xFFFF453A)
                        : context.fg54,
                  ),
                ),
              ),
              if (task.status == ConvertTaskStatus.completed &&
                  task.outputPath != null)
                TextButton(
                  onPressed: () async {
                    final all = ref.read(libraryProvider).value ?? const [];
                    final idx =
                        all.indexWhere((i) => i.path == task.outputPath);
                    if (idx >= 0) {
                      await ref.read(playerProvider).playQueue(all, idx);
                      if (all[idx].isVideo && context.mounted) {
                        openFullPlayer(context);
                      }
                    }
                  },
                  child: Text(s.t('تشغيل', 'Play')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MultiFilePickerSheet extends ConsumerStatefulWidget {
  const _MultiFilePickerSheet({
    required this.items,
    required this.initialPaths,
  });
  final List<MediaItem> items;
  final Set<String> initialPaths;

  @override
  ConsumerState<_MultiFilePickerSheet> createState() =>
      _MultiFilePickerSheetState();
}

class _MultiFilePickerSheetState extends ConsumerState<_MultiFilePickerSheet> {
  late final Set<String> _picked = {...widget.initialPaths};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final filtered = _query.trim().isEmpty
        ? widget.items
        : widget.items
            .where((i) =>
                i.name.toLowerCase().contains(_query.trim().toLowerCase()))
            .toList();

    return Rtl(
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => GlassSheet(
          radius: 30,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.fg38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.t(
                            'تحديد الملفات (${_picked.length})',
                            'Select files (${_picked.length})',
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_picked.length == filtered.length) {
                              _picked.clear();
                            } else {
                              _picked.addAll(filtered.map((e) => e.path));
                            }
                          });
                        },
                        child: Text(_picked.length == filtered.length
                            ? s.t('إلغاء الكل', 'Clear')
                            : s.t('تحديد الكل', 'Select all')),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: s.t('بحث...', 'Search...'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: context.fgA(0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final checked = _picked.contains(item.path);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (_) => setState(() {
                          if (!checked) {
                            _picked.add(item.path);
                          } else {
                            _picked.remove(item.path);
                          }
                        }),
                        title: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.ext} · ${item.folder.isEmpty ? s.t('الرئيسي', 'Main') : item.folder}',
                          style: TextStyle(fontSize: 12, color: context.fg54),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    14 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final selected = widget.items
                            .where((i) => _picked.contains(i.path))
                            .toList();
                        Navigator.of(context).pop(selected);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        s.t('تم (${_picked.length})', 'Done (${_picked.length})'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
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
