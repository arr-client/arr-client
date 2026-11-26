import 'dart:async';
import 'dart:io' as io;

import 'package:file/file.dart' show File;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'artwork_exception.dart';
import 'artwork_file_service.dart';
import 'artwork_repository.dart';

/// How many files one store keeps at most, whatever their size.
const _maximumFiles = 4000;

/// The artwork of one instance on disk: its files and their record, together in
/// one directory.
final class ArtworkStore {
  /// Opens the store in [directory], creating it if need be.
  ArtworkStore(
    io.Directory directory, {
    required int maximumBytes,
    required Duration freshFor,
  }) : _files = _Files(directory.path),
       _repository = ArtworkRepository(
         io.File('${directory.path}/index.json'),
         maximumBytes: maximumBytes,
       ),
       _service = ArtworkFileService(freshFor: freshFor) {
    directory.createSync(recursive: true);
    _manager = CacheManager(
      Config(
        // Names nothing, as the places are given here.
        'artwork',
        maxNrOfCacheObjects: _maximumFiles,
        repo: _repository,
        fileSystem: _files,
        fileService: _service,
      ),
    );
  }

  final _Files _files;
  final ArtworkRepository _repository;
  final ArtworkFileService _service;
  late final CacheManager _manager;
  final _downloads = <Future<void>>{};

  /// The file of the artwork [key], read with [source] if it is not here.
  ///
  /// A file that is here is returned at once, even when it is old, so that it
  /// shows without a server; an old one is also read again for next time.
  Future<File> file(String key, ArtworkSource source) async {
    _service.register(key, source);
    final cached = await _manager.getFileFromCache(key);
    if (cached == null) return (await _download(key)).file;
    if (cached.validTill.isBefore(DateTime.now())) {
      unawaited(_refresh(key));
    }
    return cached.file;
  }

  /// Forgets the artwork [key].
  Future<void> remove(String key) => _manager.removeFile(key);

  /// Ends every use of the directory, which may then be deleted.
  Future<void> retire() async {
    _files.retired = true;
    _service.stop();
    // Their failures belong to whoever asked for them.
    await Future.wait([
      for (final download in _downloads)
        download.then((_) {}, onError: _ignore),
    ]);
    await _repository.retire();
  }

  Future<FileInfo> _download(String key) {
    final download = _manager.downloadFile(key, key: key);
    _downloads.add(download);
    download
        .then((_) {}, onError: _ignore)
        .whenComplete(() => _downloads.remove(download));
    return download;
  }

  Future<void> _refresh(String key) async {
    try {
      await _download(key);
    } on ArtworkException catch (error) {
      // Otherwise the old file is the best there is, so it stays.
      if (error.gone) await remove(key);
    }
  }

  static void _ignore(Object error) {}
}

final class _Files implements FileSystem {
  _Files(this._path);

  final String _path;

  /// A retired store must not recreate its directory.
  var retired = false;

  @override
  Future<File> createFile(String name) async {
    final directory = const LocalFileSystem().directory(_path);
    // The system may have emptied the cache directory.
    if (!retired) await directory.create(recursive: true);
    return directory.childFile(name);
  }
}
