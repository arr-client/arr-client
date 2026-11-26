import 'package:core/core.dart';

/// One file of a manual import, as the user has it.
final class ImportFile {
  const ImportFile(
    this.candidate, {
    this.selected = false,
    this.checking = false,
    this.unchecked = false,
    this.checkFailure,
    this.episodesDropped = false,
    this.earlierRejections = const [],
  });

  /// What would be sent.
  final ManualImportCandidate candidate;

  final bool selected;

  /// Whether the server is evaluating a correction.
  final bool checking;

  /// Whether it was corrected and the server has not evaluated that.
  final bool unchecked;

  /// Why the server could not evaluate the correction.
  final ServiceFailure? checkFailure;

  /// Whether the server's evaluation came back without the episodes chosen.
  final bool episodesDropped;

  /// What the server rejected before a correction that it has not evaluated.
  final List<String> earlierRejections;

  /// Whether the server rejected it, as far as it has said.
  bool get isRejected =>
      candidate.rejections.isNotEmpty || earlierRejections.isNotEmpty;

  String get path => candidate.path;

  /// The last part of the path, of whichever system the server runs on.
  String get name => path.split(RegExp(r'[/\\]')).last;

  ImportFile withSelected(bool value) => ImportFile(
    candidate,
    selected: value,
    checking: checking,
    unchecked: unchecked,
    checkFailure: checkFailure,
    episodesDropped: episodesDropped,
    earlierRejections: earlierRejections,
  );
}

/// [candidate] with what the user chose instead.
///
/// Another movie or series takes no episodes with it, as the server does not
/// check that they belong to it. The server has rejected nothing of the result:
/// what it said before is kept in [ImportFile.earlierRejections].
ManualImportCandidate correctedCandidate(
  ManualImportCandidate candidate, {
  ItemRef? matchedRef,
  List<int>? episodeIds,
  Quality? quality,
  List<Language>? languages,
}) {
  final otherItem = matchedRef != null && matchedRef != candidate.matchedRef;
  return ManualImportCandidate(
    path: candidate.path,
    size: candidate.size,
    rawJson: candidate.rawJson,
    downloadId: candidate.downloadId,
    albumId: candidate.albumId,
    bookId: candidate.bookId,
    trackIds: candidate.trackIds,
    matchedRef: matchedRef ?? candidate.matchedRef,
    episodeIds: episodeIds ?? (otherItem ? const [] : candidate.episodeIds),
    quality: quality ?? candidate.quality,
    languages: languages ?? candidate.languages,
    selected: candidate.selected,
  );
}
