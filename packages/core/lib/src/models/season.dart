/// A season of a series.
final class Season {
  /// Creates a [Season].
  const Season({
    required this.number,
    required this.monitored,
    this.episodeCount = 0,
    this.episodeFileCount = 0,
    this.totalEpisodeCount = 0,
  });

  /// Season number; 0 holds specials.
  final int number;

  /// Whether the season is monitored.
  final bool monitored;

  /// Aired and monitored episodes.
  final int episodeCount;

  /// Episodes with a file.
  final int episodeFileCount;

  /// All episodes, aired or not.
  final int totalEpisodeCount;
}
