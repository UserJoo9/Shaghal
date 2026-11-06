import 'package:path/path.dart' as p;

class MediaItem {
  const MediaItem({
    required this.path,
    required this.folder,
    required this.modified,
    required this.size,
    required this.isVideo,
  });

  final String path;

  /// مسار الفولدر نسبةً لـ Documents. فاضي = الفولدر الرئيسي.
  final String folder;
  final DateTime modified;
  final int size;
  final bool isVideo;

  String get name => p.basenameWithoutExtension(path);
  String get ext => p.extension(path).replaceFirst('.', '').toUpperCase();
}

class MediaSection {
  const MediaSection(this.title, this.items);
  final String title;
  final List<MediaItem> items;
}
