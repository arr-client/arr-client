import 'download_protocol.dart';
import 'json_object.dart';
import 'language.dart';
import 'quality.dart';

/// A candidate from an indexer.
final class Release {
  /// Creates a [Release].
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

  /// The indexer's id of the release.
  final String guid;

  /// The server's id of the indexer.
  final int indexerId;

  /// The indexer's name.
  final String indexer;

  /// Release title.
  final String title;

  /// Torrent or Usenet.
  final DownloadProtocol protocol;

  /// Bytes.
  final int size;

  /// Age in hours.
  final double ageHours;

  /// Quality.
  final Quality? quality;

  /// Languages.
  final List<Language> languages;

  /// The server's custom format score.
  final int score;

  /// Torrent seeders.
  final int? seeders;

  /// Torrent leechers.
  final int? leechers;

  /// Why the server would not grab it by itself.
  final List<String> rejections;

  /// Grab sends back what the service requires.
  final JsonObject rawJson;
}
