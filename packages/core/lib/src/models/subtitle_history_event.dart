import 'subtitle_language.dart';
import 'subtitle_media.dart';

/// An entry of the subtitle history.
final class SubtitleHistoryEvent {
  /// Creates a [SubtitleHistoryEvent].
  const SubtitleHistoryEvent({
    required this.whenText,
    required this.mediaRef,
    required this.title,
    required this.language,
    required this.action,
    this.provider,
    this.score,
  });

  /// The server's relative and server-local time text, shown as is.
  final String whenText;

  /// What the event concerns.
  final SubtitleMedia mediaRef;

  /// What the event is about, as the server names it.
  final String title;

  /// The subtitle's language.
  final SubtitleLanguage language;

  /// The provider used.
  final String? provider;

  /// What happened, as the server reports it.
  final String action;

  /// As the server words it.
  final String? score;
}
