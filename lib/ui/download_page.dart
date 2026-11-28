import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../models/download_item.dart';
import '../services/download_manager.dart';
import '../services/media_extractor.dart';
import '../state/providers.dart';
import 'glass.dart';
import 'now_playing.dart';

class DownloadBody extends ConsumerStatefulWidget {
  const DownloadBody({super.key});

  @override
  ConsumerState<DownloadBody> createState() => _DownloadBodyState();
}

class _DownloadBodyState extends ConsumerState<DownloadBody> {
  final _urlCtrl = TextEditingController();
  final _extractor = MediaExtractor();
  int _mode = 0; // 0 = رابط + قائمة التحميلات، 1 = المتصفح الداخلي
  bool _analyzing = false;
  String? _browserInitialUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = ref.read(incomingShareUrlProvider);
      if (pending != null && pending.isNotEmpty) {
        _handleIncomingUrl(pending);
      }
    });
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _handleIncomingUrl(String url) {
    ref.read(incomingShareUrlProvider.notifier).clear();
    _urlCtrl.text = url;
    _analyzeUrl(url);
  }

  Future<void> _analyzeUrl(String raw) async {
    final clean = raw.trim();
    if (clean.isEmpty || _analyzing) return;
    FocusScope.of(context).unfocus();
    setState(() => _analyzing = true);
    final s = ref.read(stringsProvider);

    try {
      final api = ref.read(customApiUrlProvider);
      final extracted = await _extractor.extract(clean, customApiBase: api);
      if (!mounted) return;

      if (extracted.needsBrowserSniff || extracted.options.isEmpty) {
        setState(() {
          _browserInitialUrl = MediaExtractor.normalizeUrl(clean);
          _mode = 1;
        });
        _showToast(
          s.t(
            'تم فتح الرابط في المتصفح الداخلي — شغّل الفيديو واضغط على زر الوسائط بالأسفل',
            'Opened in internal browser — play the media then tap the detected media button',
          ),
        );
        return;
      }

      await _openQualitySheet(extracted);
    } catch (e) {
      if (!mounted) return;
      _showToast('${s.t('تعذّر تحليل الرابط', 'Failed to analyze URL')}: $e');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _openQualitySheet(
    ExtractedMedia media, {
    String? stepLabel,
    bool showToast = true,
  }) async {
    final s = ref.read(stringsProvider);
    final res = await showModalBottomSheet<
        ({MediaFormatOption option, String folder})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => _QualityAndFolderSheet(
        media: media,
        stepLabel: stepLabel,
      ),
    );
    if (res == null || !mounted) return;

    ref.read(downloadsProvider.notifier).enqueue(
          title: media.title,
          sourceUrl: media.sourceUrl,
          option: res.option,
          targetFolder: res.folder,
          thumbnailUrl: media.thumbnailUrl,
          author: media.author,
        );
    setState(() => _mode = 0);
    if (showToast) {
      _showToast(
        s.t(
          'بدأ التحميل في ${res.folder == kDownloadsFolder ? 'التحميلات' : res.folder}',
          'Started downloading to ${res.folder == kDownloadsFolder ? 'Downloads' : res.folder}',
        ),
      );
    }
  }

  Future<void> _configurePendingQueue({String? startId}) async {
    final s = ref.read(stringsProvider);
    var queuedAny = 0;

    while (mounted) {
      final list = ref.read(pendingSharesProvider);
      final readyList = list
          .where((i) =>
              i.status == PendingShareStatus.ready &&
              i.media != null &&
              !i.media!.needsBrowserSniff &&
              i.media!.options.isNotEmpty)
          .toList();
      if (readyList.isEmpty) break;

      final current = startId != null
          ? (readyList.where((i) => i.id == startId).firstOrNull ?? readyList.first)
          : readyList.first;
      startId = null;

      final media = current.media!;
      final totalLeft = readyList.length;
      final res = await showModalBottomSheet<
          ({MediaFormatOption option, String folder})>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => _QualityAndFolderSheet(
          media: media,
          stepLabel: totalLeft > 1
              ? s.t('متبقي $totalLeft في قائمة الانتظار', '$totalLeft left in queue')
              : null,
        ),
      );
      if (res == null || !mounted) break;

      ref.read(downloadsProvider.notifier).enqueue(
            title: media.title,
            sourceUrl: media.sourceUrl,
            option: res.option,
            targetFolder: res.folder,
            thumbnailUrl: media.thumbnailUrl,
            author: media.author,
          );
      ref.read(pendingSharesProvider.notifier).remove(current.id);
      queuedAny++;
    }

    if (queuedAny > 0 && mounted) {
      setState(() => _mode = 0);
      _showToast(
        s.t(
          'تمت إضافة $queuedAny تحميل إلى القائمة',
          'Added $queuedAny download(s) to queue',
        ),
      );
    }
  }

  void _showToast(String text) {
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
    ref.listen<String?>(incomingShareUrlProvider, (_, next) {
      if (next != null && next.isNotEmpty) {
        _handleIncomingUrl(next);
      }
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Glass(
            radius: 22,
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: _ModePill(
                    icon: Icons.link_rounded,
                    label: s.t('رابط مباشر', 'Link'),
                    active: _mode == 0,
                    onTap: () => setState(() => _mode = 0),
                  ),
                ),
                Expanded(
                  child: _ModePill(
                    icon: Icons.public_rounded,
                    label: s.t('متصفح داخلي', 'Browser'),
                    active: _mode == 1,
                    onTap: () => setState(() => _mode = 1),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _mode,
            children: [
              _LinkAndQueueView(
                urlCtrl: _urlCtrl,
                analyzing: _analyzing,
                onAnalyze: () => _analyzeUrl(_urlCtrl.text),
                onConfigurePending: (id) => _configurePendingQueue(startId: id),
                onOpenBrowser: (url) => setState(() {
                  _browserInitialUrl = url;
                  _mode = 1;
                }),
              ),
              _InternalBrowserView(
                initialUrl: _browserInitialUrl,
                extractor: _extractor,
                onExtracted: _openQualitySheet,
                onToast: _showToast,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
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

class _LinkAndQueueView extends ConsumerWidget {
  const _LinkAndQueueView({
    required this.urlCtrl,
    required this.analyzing,
    required this.onAnalyze,
    required this.onConfigurePending,
    required this.onOpenBrowser,
  });

  final TextEditingController urlCtrl;
  final bool analyzing;
  final VoidCallback onAnalyze;
  final Future<void> Function(String? startId) onConfigurePending;
  final void Function(String url) onOpenBrowser;

  Future<void> _pasteAndAnalyze(BuildContext context) async {
    final data = await Clipboard.getData('text/plain');
    final txt = data?.text?.trim() ?? '';
    if (txt.isEmpty) return;
    urlCtrl.text = txt;
    onAnalyze();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final tasks = ref.watch(downloadsProvider);
    final pendingShares = ref.watch(pendingSharesProvider);
    final readyCount = pendingShares
        .where((i) =>
            i.status == PendingShareStatus.ready &&
            i.media != null &&
            !i.media!.needsBrowserSniff &&
            i.media!.options.isNotEmpty)
        .length;
    final hasCurrent =
        ref.watch(currentItemProvider.select((v) => v.value != null));

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        (hasCurrent ? 200 : 120) + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Glass(
          radius: 26,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: urlCtrl,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => onAnalyze(),
                keyboardType: TextInputType.url,
                style: TextStyle(color: context.fg, fontSize: 15),
                decoration: InputDecoration(
                  hintText: s.t(
                    'الصق رابط فيديو أو صوت من أي منصة...',
                    'Paste video or audio link from any platform...',
                  ),
                  hintStyle: TextStyle(color: context.fg38),
                  filled: true,
                  fillColor: context.fgA(0.06),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.content_paste_rounded, color: context.fg70),
                    tooltip: s.t('لصق', 'Paste'),
                    onPressed: () => _pasteAndAnalyze(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: analyzing ? null : onAnalyze,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: analyzing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        analyzing
                            ? s.t('جاري جلب الجودات...', 'Fetching qualities...')
                            : s.t('جلب الجودات والتحميل', 'Get qualities'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GlassIconButton(
                    icon: Icons.open_in_browser_rounded,
                    size: 46,
                    onPressed: () => onOpenBrowser(
                      urlCtrl.text.trim().isEmpty
                          ? 'https://www.youtube.com'
                          : MediaExtractor.normalizeUrl(urlCtrl.text),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                s.t(
                  'تقدر كمان تعمل «مشاركة» لأي فيديو من يوتيوب أو تيك توك أو إنستجرام أو أي تطبيق إلى «شغل» وهيفتح التحميل تلقائياً.',
                  'You can also Share any video from YouTube, TikTok, Instagram or Safari directly to Shaghal.',
                ),
                style: TextStyle(fontSize: 12, color: context.fg54, height: 1.45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (pendingShares.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    s.t(
                      'روابط مشاركة بانتظار الاختيار (${pendingShares.length})',
                      'Shared Queue (${pendingShares.length})',
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.fg70,
                    ),
                  ),
                ),
              ),
              if (readyCount > 0)
                FilledButton.tonal(
                  onPressed: () => onConfigurePending(null),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    s.t('تجهيز الكل ($readyCount)', 'Configure all ($readyCount)'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              IconButton(
                icon: Icon(Icons.clear_all_rounded, size: 20, color: context.fg54),
                tooltip: s.t('مسح الكل', 'Clear all'),
                onPressed: () => ref.read(pendingSharesProvider.notifier).clearAll(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in pendingShares) ...[
            _PendingShareTile(
              item: item,
              onConfigure: () {
                final m = item.media;
                if (m != null && (m.needsBrowserSniff || m.options.isEmpty)) {
                  ref.read(pendingSharesProvider.notifier).remove(item.id);
                  onOpenBrowser(MediaExtractor.normalizeUrl(item.url));
                  return;
                }
                onConfigurePending(item.id);
              },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            s.t('التحميلات الجارية والمكتملة', 'Downloads Queue'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.fg54,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
            child: Text(
              s.t(
                'مفيش تحميلات دلوقتي.\nالصق رابط فوق أو افتح المتصفح الداخلي لتحميل أي فيديو أو صوت بكل الجودات.',
                'No downloads yet.\nPaste a link above or use the internal browser to download video or audio in any quality.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.fg54, height: 1.6),
            ),
          )
        else
          for (final t in tasks) ...[
            _DownloadTaskTile(task: t),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _PendingShareTile extends ConsumerWidget {
  const _PendingShareTile({
    required this.item,
    required this.onConfigure,
  });

  final PendingShareItem item;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final mgr = ref.read(pendingSharesProvider.notifier);
    final m = item.media;
    final needsBrowser = m != null && (m.needsBrowserSniff || m.options.isEmpty);

    return Glass(
      radius: 22,
      padding: const EdgeInsets.all(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: item.status == PendingShareStatus.ready ? onConfigure : null,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 48,
                height: 48,
                child: m?.thumbnailUrl != null
                    ? Image.network(
                        m!.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: context.fgA(0.10),
                          child: const Icon(Icons.link_rounded, color: Color(0xFF0A84FF)),
                        ),
                      )
                    : Container(
                        color: context.fgA(0.10),
                        child: item.status == PendingShareStatus.analyzing
                            ? const Padding(
                                padding: EdgeInsets.all(13),
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                item.status == PendingShareStatus.failed
                                    ? Icons.error_outline_rounded
                                    : Icons.link_rounded,
                                color: item.status == PendingShareStatus.failed
                                    ? const Color(0xFFFF453A)
                                    : const Color(0xFF0A84FF),
                              ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m?.title ?? item.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    switch (item.status) {
                      PendingShareStatus.analyzing =>
                        s.t('جاري جلب الجودات...', 'Fetching qualities...'),
                      PendingShareStatus.ready => needsBrowser
                          ? s.t('اضغط للفتح في المتصفح الداخلي', 'Tap to open in Browser')
                          : s.t(
                              '${m!.videoOptions.length} فيديو · ${m.audioOptions.length} صوت — اضغط للاختيار',
                              '${m.videoOptions.length} video · ${m.audioOptions.length} audio — tap to pick',
                            ),
                      PendingShareStatus.failed =>
                        s.t('تعذّر التحليل — اضغط إعادة', 'Failed — tap retry'),
                    },
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.status == PendingShareStatus.failed
                          ? const Color(0xFFFF453A)
                          : (item.status == PendingShareStatus.ready
                              ? const Color(0xFF64B5FF)
                              : context.fg54),
                    ),
                  ),
                ],
              ),
            ),
            if (item.status == PendingShareStatus.failed)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: () => mgr.retry(item.id),
              )
            else if (item.status == PendingShareStatus.ready)
              IconButton(
                icon: Icon(
                  needsBrowser ? Icons.open_in_browser_rounded : Icons.tune_rounded,
                  color: const Color(0xFF0A84FF),
                  size: 20,
                ),
                onPressed: onConfigure,
              ),
            IconButton(
              icon: Icon(Icons.close_rounded, size: 19, color: context.fg54),
              onPressed: () => mgr.remove(item.id),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadTaskTile extends ConsumerWidget {
  const _DownloadTaskTile({required this.task});
  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final mgr = ref.read(downloadsProvider.notifier);

    final statusText = switch (task.status) {
      DownloadTaskStatus.queued => s.t('في الانتظار', 'Queued'),
      DownloadTaskStatus.downloading =>
        '${(task.progress * 100).round()}% · ${formatSize(task.receivedBytes)}${task.totalBytes != null && task.totalBytes! > 0 ? ' / ${formatSize(task.totalBytes!)}' : ''}',
      DownloadTaskStatus.processing => task.statusDetail == 'extracting_audio'
          ? s.t('جاري استخراج الصوت...', 'Extracting audio...')
          : s.t('جاري دمج الصوت والفيديو...', 'Muxing audio & video...'),
      DownloadTaskStatus.completed => s.t(
          'مكتمل · ${task.targetFolder == kDownloadsFolder ? 'التحميلات' : task.targetFolder}',
          'Completed · ${task.targetFolder == kDownloadsFolder ? 'Downloads' : task.targetFolder}',
        ),
      DownloadTaskStatus.failed =>
        '${s.t('فشل التحميل', 'Failed')}: ${task.errorMessage ?? ''}',
      DownloadTaskStatus.cancelled => s.t('تم الإلغاء', 'Cancelled'),
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
                child: Icon(
                  task.option.isVideo
                      ? Icons.videocam_rounded
                      : Icons.music_note_rounded,
                  color: const Color(0xFF0A84FF),
                ),
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
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${task.option.label} · ${task.option.codecLabel}',
                      style: TextStyle(fontSize: 12, color: context.fg54),
                    ),
                  ],
                ),
              ),
              if (task.status == DownloadTaskStatus.downloading ||
                  task.status == DownloadTaskStatus.queued ||
                  task.status == DownloadTaskStatus.processing)
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
          if (task.status == DownloadTaskStatus.downloading ||
              task.status == DownloadTaskStatus.processing) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.status == DownloadTaskStatus.processing
                    ? null
                    : task.progress.clamp(0.0, 1.0),
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
                    color: task.status == DownloadTaskStatus.failed
                        ? const Color(0xFFFF453A)
                        : context.fg54,
                  ),
                ),
              ),
              if (task.status == DownloadTaskStatus.completed &&
                  task.outputPath != null)
                TextButton(
                  onPressed: () async {
                    final all = ref.read(libraryProvider).value ?? const [];
                    final idx = all.indexWhere((i) => i.path == task.outputPath);
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

// ───────────────────────── المتصفح الداخلي ─────────────────────────

class _InternalBrowserView extends ConsumerStatefulWidget {
  const _InternalBrowserView({
    required this.initialUrl,
    required this.extractor,
    required this.onExtracted,
    required this.onToast,
  });

  final String? initialUrl;
  final MediaExtractor extractor;
  final Future<void> Function(ExtractedMedia) onExtracted;
  final void Function(String) onToast;

  @override
  ConsumerState<_InternalBrowserView> createState() =>
      _InternalBrowserViewState();
}

class _InternalBrowserViewState extends ConsumerState<_InternalBrowserView> {
  WebViewController? _ctrl;
  final _addrCtrl = TextEditingController(text: 'https://www.youtube.com');
  final List<String> _sniffed = [];
  String _currentUrl = 'https://www.youtube.com';
  String _pageTitle = '';
  int _progress = 0;
  bool _busy = false;
  bool _unsupported = false;

  static const _snifferJs = r'''
(function() {
  if (window.__shaghalSnifferInstalled) return;
  window.__shaghalSnifferInstalled = true;
  const seen = new Set();
  function emit(u) {
    if (!u || typeof u !== 'string') return;
    if (u.startsWith('blob:') || u.startsWith('data:')) return;
    if (!u.startsWith('http')) {
      try { u = new URL(u, location.href).href; } catch(e) { return; }
    }
    const low = u.toLowerCase();
    const isMedia = /\.(mp4|m3u8|webm|m4a|mp3|opus|aac|mov)(\?|$|#)/i.test(low)
      || low.includes('mime=video')
      || low.includes('mime=audio')
      || low.includes('videoplayback');
    if (isMedia && !seen.has(u)) {
      seen.add(u);
      try { ShaghalSniff.postMessage(JSON.stringify({type:'media', url:u, title:document.title})); } catch(e){}
    }
  }
  function scanDom() {
    document.querySelectorAll('video, audio, source').forEach(el => {
      if (el.currentSrc) emit(el.currentSrc);
      if (el.src) emit(el.src);
    });
  }
  const origFetch = window.fetch;
  window.fetch = function() {
    try {
      const a = arguments[0];
      emit(typeof a === 'string' ? a : (a && a.url));
    } catch(e){}
    return origFetch.apply(this, arguments);
  };
  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    try { emit(url); } catch(e){}
    return origOpen.apply(this, arguments);
  };
  scanDom();
  setInterval(scanDom, 1500);
})();
''';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void didUpdateWidget(_InternalBrowserView old) {
    super.didUpdateWidget(old);
    if (widget.initialUrl != null &&
        widget.initialUrl != old.initialUrl &&
        _ctrl != null) {
      _loadUrl(widget.initialUrl!);
    }
  }

  void _initWebView() {
    if (!kIsWeb && !(Platform.isIOS || Platform.isAndroid || Platform.isMacOS || Platform.isWindows)) {
      setState(() => _unsupported = true);
      return;
    }
    try {
      final start = widget.initialUrl ?? 'https://www.youtube.com';
      _currentUrl = start;
      _addrCtrl.text = start;

      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'ShaghalSniff',
          onMessageReceived: (msg) {
            try {
              final data = jsonDecode(msg.message) as Map<String, dynamic>;
              final u = data['url'] as String?;
              final title = data['title'] as String?;
              if (title != null && title.isNotEmpty) _pageTitle = title;
              if (u != null && u.isNotEmpty && !_sniffed.contains(u)) {
                setState(() => _sniffed.add(u));
              }
            } catch (_) {}
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
            onPageStarted: (url) {
              if (!mounted) return;
              setState(() {
                _currentUrl = url;
                _addrCtrl.text = url;
                _sniffed.clear();
              });
            },
            onPageFinished: (url) async {
              if (!mounted) return;
              _currentUrl = url;
              try {
                final t = await _ctrl?.runJavaScriptReturningResult('document.title');
                if (t is String) {
                  _pageTitle = t.replaceAll('"', '');
                }
                await _ctrl?.runJavaScript(_snifferJs);
              } catch (_) {}
              if (mounted) setState(() {});
            },
          ),
        )
        ..loadRequest(Uri.parse(start));
      _ctrl = c;
    } catch (_) {
      setState(() => _unsupported = true);
    }
  }

  @override
  void dispose() {
    _addrCtrl.dispose();
    super.dispose();
  }

  void _loadUrl(String input) {
    final raw = input.trim();
    if (raw.isEmpty || _ctrl == null) return;
    final looksLikeUrl = raw.contains('.') && !raw.contains(' ');
    final url = raw.contains('://')
        ? raw
        : (looksLikeUrl
            ? 'https://$raw'
            : 'https://www.google.com/search?q=${Uri.encodeQueryComponent(raw)}');
    _addrCtrl.text = url;
    _ctrl!.loadRequest(Uri.parse(url));
  }

  Future<void> _collectAndShowQualities() async {
    if (_busy) return;
    setState(() => _busy = true);
    final s = ref.read(stringsProvider);

    try {
      // 1. لو الصفحة الحالية يوتيوب فيديو، نجيب كل الجودات مباشرة عبر youtube_explode_dart
      if (MediaExtractor.extractYouTubeId(_currentUrl) != null) {
        final media = await widget.extractor.extract(_currentUrl);
        if (!mounted) return;
        await widget.onExtracted(media);
        return;
      }

      // 2. مسح إضافي للـ DOM في اللحظة الحالية
      try {
        await _ctrl?.runJavaScript(_snifferJs);
      } catch (_) {}

      String cookieHeader = '';
      try {
        final rawCookies =
            await _ctrl?.runJavaScriptReturningResult('document.cookie');
        if (rawCookies is String && rawCookies.isNotEmpty) {
          cookieHeader = rawCookies.replaceAll('"', '');
        }
      } catch (_) {}

      final headers = <String, String>{
        'Referer': _currentUrl,
        if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
      };

      // 3. لو المتصفح لقط روابط، نحوّلها لجودات (ونفك أي m3u8)
      if (_sniffed.isNotEmpty) {
        final media = await widget.extractor.buildFromSniffedUrls(
          pageUrl: _currentUrl,
          title: _pageTitle,
          urls: _sniffed,
          headers: headers,
        );
        if (!mounted) return;
        if (media.options.isNotEmpty) {
          await widget.onExtracted(media);
          return;
        }
      }

      // 4. محاولة أخيرة عبر HTML / API مخصص
      final fallback = await widget.extractor.extract(
        _currentUrl,
        customApiBase: ref.read(customApiUrlProvider),
        headers: headers,
      );
      if (!mounted) return;
      if (fallback.options.isNotEmpty) {
        await widget.onExtracted(fallback);
      } else {
        widget.onToast(
          s.t(
            'شغّل الفيديو الأول جوه المتصفح عشان يظهر الرابط وبعدين دوس هنا',
            'Press Play on the video first inside the browser, then tap here',
          ),
        );
      }
    } catch (e) {
      if (mounted) widget.onToast('${s.t('حصل خطأ', 'Error')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final hasCurrent =
        ref.watch(currentItemProvider.select((v) => v.value != null));
    final isYtVideo = MediaExtractor.extractYouTubeId(_currentUrl) != null;

    if (_unsupported || _ctrl == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.t(
              'المتصفح الداخلي غير متاح على هذه المنصة. استخدم تبويب الرابط المباشر.',
              'Internal browser is not available on this platform. Use the Link tab.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.fg70),
          ),
        ),
      );
    }

    final bottomOffset =
        (hasCurrent ? 162.0 : 94.0) + MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () async {
                      if (await _ctrl!.canGoBack()) await _ctrl!.goBack();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
                    onPressed: () async {
                      if (await _ctrl!.canGoForward()) await _ctrl!.goForward();
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _addrCtrl,
                      textInputAction: TextInputAction.go,
                      onSubmitted: _loadUrl,
                      style: TextStyle(color: context.fg, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: context.fgA(0.08),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    onPressed: () => _ctrl!.reload(),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final site in const [
                    ('YouTube', 'https://www.youtube.com'),
                    ('TikTok', 'https://www.tiktok.com'),
                    ('Instagram', 'https://www.instagram.com'),
                    ('X', 'https://x.com'),
                    ('Facebook', 'https://m.facebook.com'),
                    ('SoundCloud', 'https://soundcloud.com'),
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ActionChip(
                        label: Text(site.$1, style: const TextStyle(fontSize: 12)),
                        onPressed: () => _loadUrl(site.$2),
                      ),
                    ),
                ],
              ),
            ),
            if (_progress > 0 && _progress < 100)
              LinearProgressIndicator(
                value: _progress / 100,
                minHeight: 2,
                color: const Color(0xFF0A84FF),
              ),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: WebViewWidget(controller: _ctrl!),
              ),
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: bottomOffset,
          child: Center(
            child: GestureDetector(
              onTap: _busy ? null : _collectAndShowQualities,
              child: Glass(
                interactive: true,
                radius: 26,
                tint: (isYtVideo || _sniffed.isNotEmpty)
                    ? const Color(0xFF0A84FF)
                    : null,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_busy)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(
                        Icons.download_rounded,
                        color: (isYtVideo || _sniffed.isNotEmpty)
                            ? Colors.white
                            : context.fg,
                        size: 20,
                      ),
                    const SizedBox(width: 8),
                    Text(
                      isYtVideo
                          ? s.t('تحميل بكل الجودات', 'Download all qualities')
                          : (_sniffed.isNotEmpty
                              ? s.t(
                                  'تحميل (${_sniffed.length} وسائط مكتشفة)',
                                  'Download (${_sniffed.length} detected)',
                                )
                              : s.t('التقاط الوسائط من الصفحة', 'Detect media on page')),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: (isYtVideo || _sniffed.isNotEmpty)
                            ? Colors.white
                            : context.fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── نافذة اختيار الجودة والفولدر ─────────────────────────

class _QualityAndFolderSheet extends ConsumerStatefulWidget {
  const _QualityAndFolderSheet({required this.media, this.stepLabel});
  final ExtractedMedia media;
  final String? stepLabel;

  @override
  ConsumerState<_QualityAndFolderSheet> createState() =>
      _QualityAndFolderSheetState();
}

class _QualityAndFolderSheetState
    extends ConsumerState<_QualityAndFolderSheet> {
  late bool _videoTab;
  MediaFormatOption? _selected;
  String _selectedFolder = kDownloadsFolder;
  final List<String> _extraFolders = [];

  @override
  void initState() {
    super.initState();
    final videos = widget.media.videoOptions;
    final audios = widget.media.audioOptions;
    _videoTab = videos.isNotEmpty;
    _selected = _videoTab ? videos.first : audios.firstOrNull;
  }

  Future<void> _createNewFolder(S s) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('اسم الفولدر الجديد', 'New folder name')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.t('مثلاً: عمرو دياب أو أفلام', 'e.g. Artist or Clips'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(s.t('إنشاء', 'Create')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '').trim();
    if (clean.isEmpty) return;
    final root = await libraryRootPath();
    await Directory(p.join(root, clean)).create(recursive: true);
    setState(() {
      if (!_extraFolders.contains(clean)) _extraFolders.add(clean);
      _selectedFolder = clean;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final videos = widget.media.videoOptions;
    final audios = widget.media.audioOptions;
    final currentList = _videoTab ? videos : audios;
    final isAudioChoice = !(_selected?.isVideo ?? _videoTab);

    final baseFolders = isAudioChoice
        ? ref.watch(audioFoldersProvider)
        : ref.watch(videoFoldersProvider);
    final allFolders = {...baseFolders, ..._extraFolders}.toList()
      ..sort(naturalCompare);

    if (!allFolders.contains(_selectedFolder) &&
        _selectedFolder != kDownloadsFolder) {
      _selectedFolder = kDownloadsFolder;
    }

    return Rtl(
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
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
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.stepLabel != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A84FF).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.stepLabel!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64B5FF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      Text(
                        widget.media.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (videos.isNotEmpty)
                            Expanded(
                              child: _ModePill(
                                icon: Icons.videocam_rounded,
                                label: '${s.t('فيديو', 'Video')} (${videos.length})',
                                active: _videoTab,
                                onTap: () => setState(() {
                                  _videoTab = true;
                                  _selected = videos.first;
                                  _selectedFolder = kDownloadsFolder;
                                }),
                              ),
                            ),
                          if (audios.isNotEmpty)
                            Expanded(
                              child: _ModePill(
                                icon: Icons.music_note_rounded,
                                label: '${s.t('صوت', 'Audio')} (${audios.length})',
                                active: !_videoTab,
                                onTap: () => setState(() {
                                  _videoTab = false;
                                  _selected = audios.first;
                                  _selectedFolder = kDownloadsFolder;
                                }),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      Text(
                        s.t('اختر الجودة', 'Select quality'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: context.fg54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final opt in currentList)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setState(() => _selected = opt),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                color: _selected?.id == opt.id
                                    ? const Color(0xFF0A84FF)
                                        .withValues(alpha: 0.22)
                                    : context.fgA(0.06),
                                border: Border.all(
                                  color: _selected?.id == opt.id
                                      ? const Color(0xFF0A84FF)
                                      : context.fgA(0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    opt.isVideo
                                        ? Icons.hd_rounded
                                        : Icons.graphic_eq_rounded,
                                    color: _selected?.id == opt.id
                                        ? const Color(0xFF0A84FF)
                                        : context.fg70,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          opt.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        Text(
                                          opt.codecLabel,
                                          style: TextStyle(
                                              fontSize: 12, color: context.fg54),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (opt.sizeBytes != null && opt.sizeBytes! > 0)
                                    Text(
                                      formatSize(opt.sizeBytes!),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: context.fg70,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              isAudioChoice
                                  ? s.t(
                                      'إضافة إلى فولدر من فولدرات الصوت؟',
                                      'Save to an Audio folder?',
                                    )
                                  : s.t(
                                      'إضافة إلى فولدر من فولدرات الفيديو؟',
                                      'Save to a Video folder?',
                                    ),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.fg54,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _createNewFolder(s),
                            icon: const Icon(Icons.create_new_folder_rounded,
                                size: 18),
                            label: Text(s.t('فولدر جديد', 'New folder')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            avatar: const Icon(Icons.download_rounded, size: 17),
                            label: Text(
                              s.t(
                                'التحميلات (افتراضي · الشاشة الرئيسية)',
                                'Downloads (Default · Home)',
                              ),
                            ),
                            selected: _selectedFolder == kDownloadsFolder,
                            onSelected: (_) => setState(
                                () => _selectedFolder = kDownloadsFolder),
                          ),
                          for (final f in allFolders)
                            ChoiceChip(
                              avatar: const Icon(Icons.folder_rounded, size: 17),
                              label: Text(f),
                              selected: _selectedFolder == f,
                              onSelected: (_) =>
                                  setState(() => _selectedFolder = f),
                            ),
                        ],
                      ),
                    ],
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
                    child: FilledButton.icon(
                      onPressed: _selected == null
                          ? null
                          : () => Navigator.of(context).pop((
                                option: _selected!,
                                folder: _selectedFolder,
                              )),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0A84FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: Text(
                        s.t('تحميل الآن', 'Download now'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
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
