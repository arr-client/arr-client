/// Managing what Readarr has: monitoring, editing, deleting, commands and
/// releases. Much of it destroys data.
///
/// A write is sent once. A target the server has no such operation for, one of
/// another instance included, is an [ArgumentError] with nothing sent; it is
/// never widened, say from a book to its author.
library;

import 'package:core/core.dart';

import '../api/readarr_api.dart';
import '../models/json_fields.dart';
import 'monitor_options.dart';

/// The writes of the library, which the library adapter passes on.
///
/// An author or book the server is found not to have leaves the cache. What a
/// write changes is otherwise left to the next read.
final class ReadarrLibraryWrites {
  /// Writes with [_api], and removes from [_cache] what is gone.
  ReadarrLibraryWrites(this._api, this._cache);

  final ReadarrApi _api;
  final CacheScope _cache;

  /// An author is written whole; a book on its own.
  ServiceResult<void> setMonitored(MediaTarget target, bool monitored) {
    final ref = target.item;
    if (ref.instanceId == _api.instanceId && target.seasonNumber == null) {
      switch (ref.kind) {
        case MediaKind.author:
          return _forgettingGone(
            ref,
            _api.shared.edit(
              'author/${ref.remoteId}',
              ItemEdit(monitored: monitored),
            ),
          );
        // The server accepts a book it does not have, so none is found gone.
        case MediaKind.book:
          return _api.monitorBooks([ref.remoteId], monitored: monitored);
        default:
      }
    }
    throw _unsupported(ref);
  }

  /// Has the server monitor the books [optionId], one of
  /// [readarrMonitorOptions], says.
  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId) {
    final id = _authorId(ref);
    if (!readarrMonitorOptions.any((option) => option.id == optionId)) {
      throw ArgumentError.value(optionId, 'optionId', 'not an option');
    }
    return _forgettingGone(ref, _api.bookshelf(id, monitor: optionId));
  }

  /// Fields the item does not have are left out. Of a book only whether it is
  /// monitored can be edited: its profiles and tags are the author's.
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes) {
    if (_isAuthor(ref)) {
      return _forgettingGone(
        ref,
        _api.shared.edit(
          _path(ref),
          ItemEdit(
            monitored: changes.monitored,
            qualityProfileId: changes.qualityProfileId,
            metadataProfileId: changes.metadataProfileId,
            tagIds: changes.tagIds,
          ),
        ),
      );
    }
    final monitored = changes.monitored;
    if (monitored == null) return Future.value(const Ok(null));
    return _forgettingGone(ref, _editBook(ref.remoteId, monitored));
  }

  /// All of [refs] must be authors: nothing is sent otherwise.
  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes) =>
      _api.shared.bulkEdit(
        'author/editor',
        idsField: 'authorIds',
        ids: refs.map(_authorId).toList(),
        changes: changes,
      );

  /// Deletes an author or a book, which then leaves the cache.
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

  /// Deletes one book file.
  ServiceResult<void> deleteFile(MediaFile file) =>
      _api.deleteBookFile(file.id);

  /// The server writes a book's editions with it and fails without them, and
  /// the book it answers with has none. So they are read and sent back as they
  /// are.
  ServiceResult<void> _editBook(int id, bool monitored) async {
    switch (await _api.editions(id)) {
      // NotFound would say that the book is gone.
      case Err(error: NotFound()):
        return const Err(ServerError(statusCode: 404));
      case Err(:final error):
        return Err(error);
      case Ok(value: final editions):
        return _api.shared.update('book/$id', (record) {
          record['editions'] = editions;
          record['monitored'] = monitored;
        });
    }
  }

  bool _isAuthor(ItemRef ref) {
    if (ref.instanceId == _api.instanceId) {
      if (ref.kind == MediaKind.author) return true;
      if (ref.kind == MediaKind.book) return false;
    }
    throw _unsupported(ref);
  }

  /// Where the author or book [ref] is.
  String _path(ItemRef ref) =>
      '${_isAuthor(ref) ? 'author' : 'book'}/${ref.remoteId}';

  int _authorId(ItemRef ref) =>
      ref.instanceId == _api.instanceId && ref.kind == MediaKind.author
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

/// Searches and refreshes, and for an author also rescans.
final class ReadarrCommandAdapter implements CommandProvider {
  /// Starts and follows commands with [_api].
  ReadarrCommandAdapter(this._api);

  final ReadarrApi _api;

  @override
  bool supports(CommandAction action, MediaTarget target) {
    if (target.item.instanceId != _api.instanceId ||
        target.seasonNumber != null) {
      return false;
    }
    return switch (target.item.kind) {
      MediaKind.author => true,
      MediaKind.book => action != CommandAction.rescan,
      _ => false,
    };
  }

  /// One command searches for any number of books, or for one author. No
  /// targets are [Validation], and nothing is sent.
  @override
  ServiceResult<Command> search(List<MediaTarget> targets) {
    if (!targets.every((target) => supports(CommandAction.search, target))) {
      throw ArgumentError.value(targets, 'targets', 'cannot be searched');
    }
    if (targets.every((target) => target.item.kind == MediaKind.book)) {
      // With none, the shared client sends nothing: Validation.
      return _api.shared.startCommand('BookSearch', {
        'bookIds': [for (final target in targets) target.item.remoteId],
      });
    }
    if (targets case [final target]) {
      return _api.shared.startCommand('AuthorSearch', {
        'authorId': target.item.remoteId,
      });
    }
    throw ArgumentError.value(targets, 'targets', 'not one search');
  }

  @override
  ServiceResult<Command> refresh(MediaTarget target) {
    _require(CommandAction.refresh, target);
    final id = target.item.remoteId;
    return target.item.kind == MediaKind.author
        ? _api.shared.startCommand('RefreshAuthor', {'authorId': id})
        : _api.shared.startCommand('RefreshBook', {'bookId': id});
  }

  /// Readarr scans folders, so the author is read for its own first. An author
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

  ServiceResult<Command> _rescan(int authorId) async {
    final String folder;
    switch (await _api.author(authorId)) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final path = optionalText(value, 'path');
        if (path == null) return const Err(MalformedResponse());
        folder = path;
    }
    return _api.shared.startCommand('RescanFolders', {
      'folders': [folder],
      'authorIds': [authorId],
      // The server would otherwise add every author it finds.
      'addNewAuthors': false,
    });
  }

  void _require(CommandAction action, MediaTarget target) {
    if (!supports(action, target)) throw _unsupported(target.item);
  }
}

/// Interactive search for a book or an author.
final class ReadarrReleaseAdapter implements ReleaseProvider {
  /// Searches and grabs with [_api].
  ReadarrReleaseAdapter(this._api);

  final ReadarrApi _api;

  /// Without a book or an author the server would answer with its RSS feeds.
  @override
  ServiceResult<List<Release>> releases(MediaTarget target) {
    final ref = target.item;
    if (ref.instanceId == _api.instanceId && target.seasonNumber == null) {
      switch (ref.kind) {
        case MediaKind.book:
          return _api.shared.releases({'bookId': ref.remoteId});
        case MediaKind.author:
          return _api.shared.releases({'authorId': ref.remoteId});
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
