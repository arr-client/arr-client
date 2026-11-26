/// Identifiers shared between services.
final class ExternalIds {
  const ExternalIds({
    this.tmdbId,
    this.tvdbId,
    this.imdbId,
    this.musicBrainzId,
    this.foreignId,
  });

  final int? tmdbId;

  final int? tvdbId;

  final String? imdbId;

  final String? musicBrainzId;

  /// A book or author id from the server's metadata source.
  final String? foreignId;
}
