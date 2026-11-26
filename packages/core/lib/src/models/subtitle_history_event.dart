import 'subtitle_language.dart';
import 'subtitle_media.dart';

/// An entry of the subtitle history.
final class SubtitleHistoryEvent {
  const SubtitleHistoryEvent({
    required this.whenText,
    required this.mediaRef,
    required this.language,
    required this.action,
    this.provider,
    this.score,
  });

  /// The server's relative and server-local time text, shown as is.
  final String whenText;

  final SubtitleMedia mediaRef;

  final SubtitleLanguage language;

  final String? provider;

  final String action;

  /// As the server words it.
  final String? score;
}
