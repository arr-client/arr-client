import 'subtitle_language.dart';
import 'subtitle_media.dart';

/// Subtitles a title lacks.
final class SubtitleWant {
  const SubtitleWant({
    required this.media,
    required this.title,
    required this.missing,
  });

  final SubtitleMedia media;

  final String title;

  final List<SubtitleLanguage> missing;
}
