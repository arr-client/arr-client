/// Identifiers shared between services.
final class ExternalIds {
  /// Creates an [ExternalIds].
  const ExternalIds({
    this.tmdbId,
    this.tvdbId,
    this.imdbId,
    this.musicBrainzId,
    this.foreignId,
  });

  /// TMDB id.
  final int? tmdbId;

  /// TVDB id.
  final int? tvdbId;

  /// IMDb id.
  final String? imdbId;

  /// MusicBrainz id.
  final String? musicBrainzId;

  /// A book or author id from the server's metadata source.
  final String? foreignId;
}
