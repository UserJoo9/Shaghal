import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../core/media_formats.dart';

class ImportResult {
  const ImportResult(this.copied, this.skipped);
  final int copied;
  final int skipped;
}

Future<bool> _copy(File src, String dest) async {
  try {
    await Directory(p.dirname(dest)).create(recursive: true);
    await src.copy(dest);
    return true;
  } on FileSystemException {
    return false;
  }
}

/// يختار المستخدم ملفات (صوت/فيديو) وتتنسخ لمكتبة التطبيق.
Future<ImportResult> importFiles(String destRoot) async {
  final res = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.any,
  );
  if (res == null) return const ImportResult(0, 0);

  var copied = 0;
  var skipped = 0;
  for (final f in res.files) {
    final src = f.path;
    if (src == null || MediaFormats.isVideo(src) == null) {
      skipped++;
      continue;
    }
    if (await _copy(File(src), p.join(destRoot, p.basename(src)))) {
      copied++;
    } else {
      skipped++;
    }
  }
  return ImportResult(copied, skipped);
}

/// يختار المستخدم فولدر كامل، وتتنسخ ملفات الميديا اللي فيه بنفس هيكل الفولدرات.
Future<ImportResult> importFolder(String destRoot) async {
  final dir = await FilePicker.platform.getDirectoryPath();
  if (dir == null) return const ImportResult(0, 0);

  final base = p.join(destRoot, p.basename(dir));
  var copied = 0;
  var skipped = 0;
  await for (final e in Directory(dir).list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    if (MediaFormats.isVideo(e.path) == null) continue;
    final dest = p.join(base, p.relative(e.path, from: dir));
    if (await _copy(e, dest)) {
      copied++;
    } else {
      skipped++;
    }
  }
  return ImportResult(copied, skipped);
}
