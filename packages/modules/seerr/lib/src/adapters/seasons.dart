/// The seasons of a series, to choose from when it is requested. No capability
/// offers them: only the module's request screen needs them.
library;

import 'package:core/core.dart';

import '../api/seerr_api.dart';
import 'records.dart';
import 'server.dart';

/// One season, as far as one variant of it goes.
final class SeasonChoice {
  /// Creates a [SeasonChoice].
  const SeasonChoice({
    required this.number,
    required this.availability,
    required this.requested,
    this.episodeCount,
  });

  /// Season number; 0 holds specials.
  final int number;

  /// How many episodes it has, where the server says.
  final int? episodeCount;

  /// Whether it is on the server.
  final Availability availability;

  /// Whether a request that is not over names it.
  final bool requested;

  /// Whether the server takes a request for it.
  bool get isOpen =>
      !requested &&
      (availability == Availability.unknown ||
          availability == Availability.deleted);
}

/// The seasons of a series.
final class SeasonChoices {
  /// Creates [SeasonChoices].
  const SeasonChoices({required this.seasons, required this.mayChoose});

  /// In the server's order.
  final List<SeasonChoice> seasons;

  /// Whether some of the open seasons may be requested without the others.
  final bool mayChoose;
}

/// Reads the seasons of one instance's series.
final class SeerrSeasonAdapter {
  /// Creates a [SeerrSeasonAdapter].
  SeerrSeasonAdapter(InstanceContext context)
    : _api = SeerrApi(context),
      _server = SeerrServer.of(context.instance.lastProbe);

  final SeerrApi _api;
  final SeerrServer _server;

  /// The seasons of the series [tmdbId], for the standard or the 4K variant.
  /// Specials are left out unless the server takes requests for them.
  ServiceResult<SeasonChoices> seasons(int tmdbId, {required bool is4k}) async {
    final Map<String, Object?> settings;
    switch (await _api.readObject('settings/public')) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        settings = value;
    }
    return readRecord(
      _api,
      'tv/$tmdbId',
      (series) => _choices(
        series,
        is4k: is4k,
        // As in the web interface: Overseerr has neither setting.
        specials: settings['enableSpecialEpisodes'] == true,
        mayChoose: settings['partialRequestsEnabled'] != false,
      ),
    );
  }

  SeasonChoices _choices(
    JsonObject series, {
    required bool is4k,
    required bool specials,
    required bool mayChoose,
  }) {
    final media = switch (series['mediaInfo']) {
      null => null,
      final info => asObject(info),
    };
    final requested = <int>{
      for (final request in _objects(media?['requests']))
        // Declined (3) and completed (5) requests are over.
        if ((request['is4k'] == true) == is4k &&
            request['status'] != 3 &&
            request['status'] != 5)
          for (final season in _objects(request['seasons']))
            requireInt(season, 'seasonNumber'),
    };
    final states = {
      for (final season in _objects(media?['seasons']))
        requireInt(season, 'seasonNumber'): _server.availability(
          season[is4k ? 'status4k' : 'status'],
        ),
    };
    return SeasonChoices(
      mayChoose: mayChoose,
      seasons: [
        for (final season in asObjects(series['seasons']))
          if (requireInt(season, 'seasonNumber') case final number
              when number > 0 || specials)
            SeasonChoice(
              number: number,
              episodeCount: switch (season['episodeCount']) {
                final int count => count,
                _ => null,
              },
              availability: states[number] ?? Availability.unknown,
              requested: requested.contains(number),
            ),
      ],
    );
  }

  static List<JsonObject> _objects(Object? value) =>
      value == null ? const [] : asObjects(value);
}
