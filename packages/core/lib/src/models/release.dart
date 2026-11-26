import 'download_protocol.dart';
import 'json_object.dart';
import 'language.dart';
import 'quality.dart';

/// A candidate from an indexer.
final class Release {
  const Release({
    required this.guid,
    required this.indexerId,
    required this.indexer,
    required this.title,
    required this.protocol,
    required this.size,
    required this.ageHours,
    required this.rawJson,
    this.quality,
    this.seeders,
    this.leechers,
    this.languages = const [],
    this.score = 0,
    this.rejections = const [],
  });

  final String guid;

  final int indexerId;

  final String indexer;

  final String title;

  final DownloadProtocol protocol;

  /// Bytes.
  final int size;

  final double ageHours;

  final Quality? quality;

  final List<Language> languages;

  final int score;

  final int? seeders;

  final int? leechers;

  final List<String> rejections;

  /// Grab sends back what the service requires.
  final JsonObject rawJson;
}
