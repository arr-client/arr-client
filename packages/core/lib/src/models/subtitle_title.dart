import 'subtitle_file.dart';
import 'subtitle_media.dart';

/// The subtitle state of a title.
final class SubtitleTitle {
  const SubtitleTitle({
    required this.media,
    required this.title,
    this.year,
    this.missingCount = 0,
    this.files = const [],
  });

  final SubtitleMedia media;

  final String title;

  final int? year;

  final int missingCount;

  final List<SubtitleFile> files;
}
