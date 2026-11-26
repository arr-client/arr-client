import 'package:core/core.dart';

import '../api/radarr_api.dart';

/// The changes and deletes of `RadarrLibraryAdapter`.
///
/// Each acts only on movies of this instance: given anything else, even as one
/// of a list, it sends nothing and fails with [Validation].
mixin RadarrLibraryWrites implements LibraryProvider {
  /// Where the writes go.
  RadarrApi get api;

  /// The instance they are for.
  InstanceContext get context;

  @override
  ServiceResult<void> setMonitored(MediaTarget target, bool monitored) async =>
      _isMovieTarget(target, context.instance.id)
      ? await edit(target.item, ItemEdit(monitored: monitored))
      : const Err(Validation([]));

  // A movie has none: [monitorOptions] is empty.
  @override
  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId) async =>
      const Err(Validation([]));

  @override
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes) async =>
      _isMovie(ref, context.instance.id)
      ? await _forgettingGone(
          ref,
          api.shared.edit('movie/${ref.remoteId}', changes),
        )
      : const Err(Validation([]));

  @override
  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes) async =>
      refs.every((ref) => _isMovie(ref, context.instance.id))
      ? await api.shared.bulkEdit(
          'movie/editor',
          idsField: 'movieIds',
          ids: [for (final ref in refs) ref.remoteId],
          changes: changes,
        )
      : const Err(Validation([]));

  @override
  ServiceResult<void> delete(
    ItemRef ref, {
    required bool deleteFiles,
    required bool addImportExclusion,
  }) async {
    if (!_isMovie(ref, context.instance.id)) return const Err(Validation([]));
    final deleted = await _forgettingGone(
      ref,
      api.deleteMovie(
        ref.remoteId,
        deleteFiles: deleteFiles,
        addImportExclusion: addImportExclusion,
      ),
    );
    if (deleted is Ok) {
      await context.cache.remove(MediaKind.movie, ref.remoteId);
    }
    return deleted;
  }

  // The movie stays, so its cache entry does until the next read.
  @override
  ServiceResult<void> deleteFile(MediaFile file) =>
      api.deleteMovieFile(file.id);

  /// [write] to [ref], which leaves the cache if it no longer exists.
  ServiceResult<void> _forgettingGone(
    ItemRef ref,
    ServiceResult<void> write,
  ) async {
    final result = await write;
    if (result case Err(error: NotFound())) {
      await context.cache.remove(MediaKind.movie, ref.remoteId);
    }
    return result;
  }
}

/// Interactive search and grab for a movie.
final class RadarrReleaseAdapter implements ReleaseProvider {
  /// Searches and grabs through [_api] for the instance [_instanceId].
  RadarrReleaseAdapter(this._api, this._instanceId);

  final RadarrApi _api;
  final String _instanceId;

  @override
  ServiceResult<List<Release>> releases(MediaTarget target) async =>
      _isMovieTarget(target, _instanceId)
      ? await _api.shared.releases({'movieId': target.item.remoteId})
      : const Err(Validation([]));

  // The release carries the movie it was searched for.
  @override
  ServiceResult<void> grab(Release release) => _api.shared.grab(release);
}

/// Automatic search, refresh and rescan of movies.
///
/// The server takes a command that names no movie to mean the whole library,
/// so each one names its movies, or is not started and fails with
/// [Validation].
final class RadarrCommandAdapter implements CommandProvider {
  /// Starts commands through [_api] for the instance [_instanceId].
  RadarrCommandAdapter(this._api, this._instanceId);

  final RadarrApi _api;
  final String _instanceId;

  // A movie offers every action.
  @override
  bool supports(CommandAction action, MediaTarget target) =>
      _isMovieTarget(target, _instanceId);

  @override
  ServiceResult<Command> search(List<MediaTarget> targets) async =>
      targets.every((target) => _isMovieTarget(target, _instanceId))
      ? await _api.shared.startCommand('MoviesSearch', {
          'movieIds': [for (final target in targets) target.item.remoteId],
        })
      : const Err(Validation([]));

  @override
  ServiceResult<Command> refresh(MediaTarget target) async =>
      _isMovieTarget(target, _instanceId)
      ? await _api.shared.startCommand('RefreshMovie', {
          'movieIds': [target.item.remoteId],
        })
      : const Err(Validation([]));

  @override
  ServiceResult<Command> rescan(MediaTarget target) async =>
      _isMovieTarget(target, _instanceId)
      ? await _api.shared.startCommand('RescanMovie', {
          'movieId': target.item.remoteId,
        })
      : const Err(Validation([]));

  @override
  ServiceResult<Command> commandStatus(int commandId) =>
      _api.shared.commandStatus(commandId);
}

bool _isMovie(ItemRef ref, String instanceId) =>
    ref.kind == MediaKind.movie && ref.instanceId == instanceId;

// A season is no part of a movie.
bool _isMovieTarget(MediaTarget target, String instanceId) =>
    target.seasonNumber == null && _isMovie(target.item, instanceId);
