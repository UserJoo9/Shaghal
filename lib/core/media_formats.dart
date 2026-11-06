/// الامتدادات اللي المسح (scan) بيعتبرها ميديا.
/// المشغّل نفسه (libmpv/FFmpeg) بيشغّل أي حاجة FFmpeg بتفكّها،
/// فلو في امتداد ناقص ضيفه هنا وخلاص.
class MediaFormats {
  MediaFormats._();

  static const audio = <String>{
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'oga', 'opus', 'wma', 'aiff',
    'aif', 'aifc', 'caf', 'amr', 'ape', 'wv', 'mka', 'mpc', 'dsf', 'dff',
    'alac', 'mp2', 'ac3', 'eac3', 'dts', 'tta', 'm4b', 'm4r', 'spx', 'mid',
    'midi', 'weba',
  };

  static const video = <String>{
    'mp4', 'm4v', 'mov', 'mkv', 'avi', 'webm', 'wmv', 'flv', 'ts', 'mts',
    'm2ts', '3gp', '3g2', 'mpg', 'mpeg', 'ogv', 'vob', 'divx', 'asf', 'rm',
    'rmvb', 'f4v', 'mxf',
  };

  /// null = مش ملف ميديا. true = فيديو. false = صوت.
  static bool? isVideo(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    final ext = path.substring(dot + 1).toLowerCase();
    if (video.contains(ext)) return true;
    if (audio.contains(ext)) return false;
    return null;
  }
}
