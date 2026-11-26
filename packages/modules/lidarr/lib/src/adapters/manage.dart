/// Managing what Lidarr has: monitoring, editing, deleting, commands and
/// releases. Much of it destroys data.
///
/// A write is sent once. A target the server has no such operation for, one of
/// another instance included, is an [ArgumentError] with nothing sent; it is
/// never widened, say from an album to its artist.
library;

import 'package:core/core.dart';

import '../api/lidarr_api.dart';
import '../models/json_fields.dart';
import 'monitor_options.dart';

/// The writes of the library, which the library adapter passes on.
///
/// An artist or album the server is found not to have leaves the cache. What a
/// write changes is otherwise left to the next read.
final class LidarrLibraryWrites {
  /// Writes with [_api], and removes from [_cache] what is gone.
  LidarrLibraryWrites(this._api, this._cache);

  final LidarrApi _api;
  final CacheScope _cache;

  /// An artist is written whole; an album on its own. A track follows its
  /// album.
  ServiceResult<void> setMonitored(MediaTarget target, bool monitored) {
    final ref = target.item;
    if (ref.instanceId == _api.instanceId && target.seasonNumber == null) {
      switch (ref.kind) {
        case MediaKind.artist:
          return _forgettingGone(
            ref,
            _api.shared.edit(
              'artist/${ref.remoteId}',
              ItemEdit(monitored: monitored),
            ),
          );
        // The server accepts an album it does not have, so none is found gone.
        case MediaKind.album:
          return _api.monitorAlbums([ref.remoteId], monitored: monitored);
        default:
      }
    }
    throw _unsupported(ref);
  }

  /// Has the server monitor the albums [optionId], one of
  /// [lidarrMonitorOptions], says.
  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId) {
    final id = _artistId(ref);
    if (!lidarrMonitorOptions.any((option) => option.id == optionId)) {
      throw ArgumentError.value(optionId, 'optionId', 'not an option');
    }
    return _forgettingGone(ref, _api.albumStudio(id, monitor: optionId));
  }

  /// Fields the item does not have are left out. Of an album only whether it is
  /// monitored can be edited: its profiles and tags are the artist's.
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes) {
    final isArtist = _isArtist(ref);
    return _forgettingGone(
      ref,
      _api.shared.edit(
        _path(ref),
        ItemEdit(
          monitored: changes.monitored,
          qualityProfileId: isArtist ? changes.qualityProfileId : null,
          metadataProfileId: isArtist ? changes.metadataProfileId : null,
          tagIds: isArtist ? changes.tagIds : null,
        ),
      ),
    );
  }

  /// All of [refs] must be artists: nothing is sent otherwise.
  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes) =>
      _api.shared.bulkEdit(
        'artist/editor',
        idsField: 'artistIds',
        ids: refs.map(_artistId).toList(),
        changes: changes,
      );

  /// Deletes an artist or an album, which then leaves the cache.
  ServiceResult<void> delete(
    ItemRef ref, {
    required bool deleteFiles,
    required bool addImportExclusion,
  }) {
    // Refuses what cannot be deleted, before anything is sent.
    final path = _path(ref);
    return _delete(
      ref,
      _api.delete(
        path,
        deleteFiles: deleteFiles,
        addImportListExclusion: addImportExclusion,
      ),
    );
  }

  /// Deletes one track file.
  ServiceResult<void> deleteFile(MediaFile file) =>
      _api.deleteTrackFile(file.id);

  bool _isArtist(ItemRef ref) {
    if (ref.instanceId == _api.instanceId) {
      if (ref.kind == MediaKind.artist) return true;
      if (ref.kind == MediaKind.album) return false;
    }
    throw _unsupported(ref);
  }

  /// Where the artist or album [ref] is.
  String _path(ItemRef ref) =>
      '${_isArtist(ref) ? 'artist' : 'album'}/${ref.remoteId}';

  int _artistId(ItemRef ref) =>
      ref.instanceId == _api.instanceId && ref.kind == MediaKind.artist
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

/// Searches and refreshes, and for an artist also rescans.
final class LidarrCommandAdapter implements CommandProvider {
  /// Starts and follows commands with [_api].
  LidarrCommandAdapter(this._api);

  final LidarrApi _api;

  @override
  bool supports(CommandAction action, MediaTarget target) {
    if (target.item.instanceId != _api.instanceId ||
        target.seasonNumber != null) {
      return false;
    }
    return switch (target.item.kind) {
      MediaKind.artist => true,
      MediaKind.album => action != CommandAction.rescan,
      _ => false,
    };
  }

  /// One command searches for any number of albums, or for one artist. No
  /// targets are [Validation], and nothing is sent.
  @override
  ServiceResult<Command> search(List<MediaTarget> targets) {
    if (!targets.every((target) => supports(CommandAction.search, target))) {
      throw ArgumentError.value(targets, 'targets', 'cannot be searched');
    }
    if (targets.every((target) => target.item.kind == MediaKind.album)) {
      // With none, the shared client sends nothing: Validation.
      return _api.shared.startCommand('AlbumSearch', {
        'albumIds': [for (final target in targets) target.item.remoteId],
      });
    }
    if (targets case [final target]) {
      return _api.shared.startCommand('ArtistSearch', {
        'artistId': target.item.remoteId,
      });
    }
    throw ArgumentError.value(targets, 'targets', 'not one search');
  }

  @override
  ServiceResult<Command> refresh(MediaTarget target) {
    _require(CommandAction.refresh, target);
    final id = target.item.remoteId;
    return target.item.kind == MediaKind.artist
        ? _api.shared.startCommand('RefreshArtist', {
            'artistIds': [id],
          })
        : _api.shared.startCommand('RefreshAlbum', {'albumId': id});
  }

  /// Lidarr scans folders, so the artist is read for its own first. An artist
  /// without one is [MalformedResponse], and no command is sent: without a
  /// folder the server would scan every root folder.
  @override
  ServiceResult<Command> rescan(MediaTarget target) {
    _require(CommandAction.rescan, target);
    return _rescan(target.item.remoteId);
  }

  @override
  ServiceResult<Command> commandStatus(int commandId) =>
      _api.shared.commandStatus(commandId);

  ServiceResult<Command> _rescan(int artistId) async {
    final String folder;
    switch (await _api.artist(artistId)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final path = optionalText(value, 'path');
        if (path == null) return const Err(MalformedResponse());
        folder = path;
    }
    return _api.shared.startCommand('RescanFolders', {
      'folders': [folder],
      'artistIds': [artistId],
      // The server would otherwise add every artist it finds.
      'addNewArtists': false,
    });
  }

  void _require(CommandAction action, MediaTarget target) {
    if (!supports(action, target)) throw _unsupported(target.item);
  }
}

/// Interactive search for an album or an artist.
final class LidarrReleaseAdapter implements ReleaseProvider {
  /// Searches and grabs with [_api].
  LidarrReleaseAdapter(this._api);

  final LidarrApi _api;

  /// Without an album or an artist the server would answer with its RSS feeds.
  @override
  ServiceResult<List<Release>> releases(MediaTarget target) {
    final ref = target.item;
    if (ref.instanceId == _api.instanceId && target.seasonNumber == null) {
      switch (ref.kind) {
        case MediaKind.album:
          return _api.shared.releases({'albumId': ref.remoteId});
        case MediaKind.artist:
          return _api.shared.releases({'artistId': ref.remoteId});
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
