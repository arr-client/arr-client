/// Managing what Sonarr has: monitoring, editing, deleting, commands and
/// releases. Much of it destroys data.
///
/// A write is sent once. A target the server has no such operation for, one of
/// another instance included, is an [ArgumentError] with nothing sent; it is
/// never widened, say from a season to its series.
library;

import 'package:core/core.dart';

import '../api/sonarr_api.dart';
import '../models/json_fields.dart';
import 'monitor_options.dart';

/// The writes of the library, which the library adapter passes on.
///
/// A series the server is found not to have leaves the cache. What a write
/// changes is otherwise left to the next read.
final class SonarrLibraryWrites {
  /// Writes with [_api], and removes from [_cache] what is gone.
  SonarrLibraryWrites(this._api, this._cache);

  final SonarrApi _api;
  final CacheScope _cache;

  /// A series or one season is written as part of the whole series; an episode
  /// on its own.
  ServiceResult<void> setMonitored(MediaTarget target, bool monitored) {
    final ref = target.item;
    final number = target.seasonNumber;
    if (ref.instanceId == _api.instanceId) {
      switch (ref.kind) {
        case MediaKind.series:
          return _forgettingGone(
            ref,
            _api.updateSeries(
              ref.remoteId,
              number == null
                  ? (series) => series['monitored'] = monitored
                  : (series) => _setSeason(series, number, monitored),
            ),
          );
        case MediaKind.episode when number == null:
          return _forgettingGone(
            ref,
            _api.monitorEpisodes([ref.remoteId], monitored: monitored),
          );
        default:
      }
    }
    throw _unsupported(ref);
  }

  /// Has the server monitor what [optionId], one of [sonarrMonitorOptions],
  /// says.
  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId) {
    final id = _seriesId(ref);
    if (!sonarrMonitorOptions.any((option) => option.id == optionId)) {
      throw ArgumentError.value(optionId, 'optionId', 'not an option');
    }
    return _forgettingGone(ref, _api.seasonPass(id, monitor: optionId));
  }

  /// Fields a series does not have are left out.
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes) {
    final id = _seriesId(ref);
    return _forgettingGone(
      ref,
      _api.editSeries(
        id,
        ItemEdit(
          monitored: changes.monitored,
          qualityProfileId: changes.qualityProfileId,
          tagIds: changes.tagIds,
          seriesType: changes.seriesType,
          seasonFolder: changes.seasonFolder,
        ),
      ),
    );
  }

  /// All of [refs] must be series: nothing is sent otherwise.
  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes) =>
      _api.editAllSeries(refs.map(_seriesId).toList(), changes);

  /// Deletes a series, which then leaves the cache.
  ServiceResult<void> delete(
    ItemRef ref, {
    required bool deleteFiles,
    required bool addImportExclusion,
  }) {
    final id = _seriesId(ref);
    return _delete(
      ref,
      _api.deleteSeries(
        id,
        deleteFiles: deleteFiles,
        addImportListExclusion: addImportExclusion,
      ),
    );
  }

  /// Deletes one episode file.
  ServiceResult<void> deleteFile(MediaFile file) =>
      _api.deleteEpisodeFile(file.id);

  /// Sonarr monitors or unmonitors the episodes of a season that the series is
  /// written with changed.
  void _setSeason(JsonObject series, int number, bool monitored) {
    final season = asObjects(series['seasons']).firstWhere(
      (season) => season['seasonNumber'] == number,
      // Nothing is written for a season the series does not have.
      orElse: () => throw const FormatException('No such season'),
    );
    season['monitored'] = monitored;
  }

  int _seriesId(ItemRef ref) =>
      ref.instanceId == _api.instanceId && ref.kind == MediaKind.series
      ? ref.remoteId
      : throw _unsupported(ref);

  ServiceResult<void> _delete(ItemRef ref, ServiceResult<void> write) async {
    final result = await _forgettingGone(ref, write);
    if (result is Ok) await _cache.remove(ref.kind, ref.remoteId);
    return result;
  }

  /// [write] to [ref], which leaves the cache if it no longer exists.
  ServiceResult<void> _forgettingGone(
    ItemRef ref,
    ServiceResult<void> write,
  ) async {
    final result = await write;
    if (result case Err(error: NotFound())) {
      await _cache.remove(ref.kind, ref.remoteId);
    }
    return result;
  }
}

/// Searches, and for a series also refreshes and rescans.
final class SonarrCommandAdapter implements CommandProvider {
  /// Starts and follows commands with [_api].
  SonarrCommandAdapter(this._api);

  final SonarrApi _api;

  @override
  bool supports(CommandAction action, MediaTarget target) {
    if (target.item.instanceId != _api.instanceId) return false;
    return switch (target.item.kind) {
      MediaKind.series =>
        target.seasonNumber == null || action == CommandAction.search,
      MediaKind.episode =>
        target.seasonNumber == null && action == CommandAction.search,
      _ => false,
    };
  }

  /// One command searches for any number of episodes, or for one season, or
  /// for one series. No targets are [Validation], and nothing is sent.
  @override
  ServiceResult<Command> search(List<MediaTarget> targets) {
    if (!targets.every((target) => supports(CommandAction.search, target))) {
      throw ArgumentError.value(targets, 'targets', 'cannot be searched');
    }
    if (targets.every((target) => target.item.kind == MediaKind.episode)) {
      // With none, the shared client sends nothing: Validation.
      return _api.shared.startCommand('EpisodeSearch', {
        'episodeIds': [for (final target in targets) target.item.remoteId],
      });
    }
    if (targets case [final target]) {
      final id = target.item.remoteId;
      return switch (target.seasonNumber) {
        final number? => _api.shared.startCommand('SeasonSearch', {
          'seriesId': id,
          'seasonNumber': number,
        }),
        null => _api.shared.startCommand('SeriesSearch', {'seriesId': id}),
      };
    }
    throw ArgumentError.value(targets, 'targets', 'not one search');
  }

  @override
  ServiceResult<Command> refresh(MediaTarget target) {
    _require(CommandAction.refresh, target);
    return _api.shared.startCommand('RefreshSeries', {
      'seriesIds': [target.item.remoteId],
    });
  }

  @override
  ServiceResult<Command> rescan(MediaTarget target) {
    _require(CommandAction.rescan, target);
    return _api.shared.startCommand('RescanSeries', {
      'seriesId': target.item.remoteId,
    });
  }

  @override
  ServiceResult<Command> commandStatus(int commandId) =>
      _api.shared.commandStatus(commandId);

  void _require(CommandAction action, MediaTarget target) {
    if (!supports(action, target)) throw _unsupported(target.item);
  }
}

/// Interactive search for an episode or a season.
final class SonarrReleaseAdapter implements ReleaseProvider {
  /// Searches and grabs with [_api].
  SonarrReleaseAdapter(this._api);

  final SonarrApi _api;

  /// Without an episode, or a series and a season, the server would answer with
  /// its RSS feeds, and there is no search for a whole series.
  @override
  ServiceResult<List<Release>> releases(MediaTarget target) {
    final ref = target.item;
    if (ref.instanceId == _api.instanceId) {
      switch ((ref.kind, target.seasonNumber)) {
        case (MediaKind.episode, null):
          return _api.shared.releases({'episodeId': ref.remoteId});
        case (MediaKind.series, final number?):
          return _api.shared.releases({
            'seriesId': ref.remoteId,
            'seasonNumber': number,
          });
        default:
      }
    }
    throw _unsupported(ref);
  }

  @override
  ServiceResult<void> grab(Release release) => _api.shared.grab(release);
}

ArgumentError _unsupported(ItemRef ref) =>
    ArgumentError.value(ref.kind, 'kind', 'not a target of this operation');
