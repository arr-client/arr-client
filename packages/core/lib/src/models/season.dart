/// A season of a series.
final class Season {
  const Season({
    required this.number,
    required this.monitored,
    this.episodeCount = 0,
    this.episodeFileCount = 0,
    this.totalEpisodeCount = 0,
  });

  final int number;

  final bool monitored;

  /// Aired and monitored episodes.
  final int episodeCount;

  final int episodeFileCount;

  final int totalEpisodeCount;
}
