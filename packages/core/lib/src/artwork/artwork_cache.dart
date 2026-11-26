/// Loads artwork and keeps it on disk (research R10).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';

import '../models/media_image.dart';
import '../module/result.dart';
import '../module/service_failure.dart';
import '../network/http_method.dart';
import '../network/remote_client.dart';
import '../network/service_http_client.dart';
import '../network/service_request.dart';
import 'artwork_exception.dart';
import 'artwork_file_service.dart';
import 'artwork_image.dart';
import 'artwork_loader.dart';
import 'artwork_store.dart';

/// The artwork of every instance. The app has one, and takes each instance's
/// [ArtworkLoader] from it.
///
/// Each instance has its own directory and its own size limit. Neither file
/// names nor their record hold an address.
final class ArtworkCache {
  /// Keeps artwork under `artwork/` in [directory], which should be one that
  /// the system may empty and does not back up.
  ///
  /// [loadRemote] is asked whenever artwork of a public host is wanted
  /// (`Preferences.loadThirdPartyArtwork`). [maximumBytes] limits what is kept
  /// of one instance, and [freshFor] how long a file is used before it is read
  /// again.
  ArtworkCache({
    required this._directory,
    required this._loadRemote,
    this._maximumBytes = 100 * 1024 * 1024,
    this._freshFor = const Duration(days: 7),
  });

  final Future<Directory> Function() _directory;
  final bool Function() _loadRemote;
  final int _maximumBytes;
  final Duration _freshFor;

  final _remote = RemoteClient();
  final _stores = <String, Future<ArtworkStore>>{};

  // The last clearing: a store is not opened while its directory is deleted.
  Future<void> _clearing = Future.value();

  var _closed = false;

  /// The loader of the instance [instanceId], whose own artwork is read with
  /// [client].
  ArtworkLoader loaderFor(String instanceId, ServiceHttpClient client) =>
      _Loader(this, instanceId, client);

  /// Deletes what is kept of [instanceId], or without one of every instance,
  /// from disk and from Flutter's memory cache. Loads under way fail.
  Future<void> clear({String? instanceId}) {
    final open = _take(instanceId);
    final cleared = _clearing.then((_) async {
      await _retire(open);
      final root = await _root();
      final target = instanceId == null
          ? root
          : Directory('${root.path}/${_digest(instanceId)}');
      if (await target.exists()) await target.delete(recursive: true);
      // Only now, so that nothing is read back from disk into it.
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    });
    // A failure is the caller's, and must not stop later loads.
    _clearing = cleared.then((_) {}, onError: (Object _) {});
    return cleared;
  }

  /// Writes what is pending and drops every connection. Later loads fail.
  Future<void> close() async {
    _closed = true;
    _remote.close();
    await _retire(_take(null));
  }

  List<Future<ArtworkStore>> _take(String? instanceId) => [
    for (final id in instanceId == null ? [..._stores.keys] : [instanceId])
      ?_stores.remove(id),
  ];

  Future<void> _retire(List<Future<ArtworkStore>> stores) async {
    for (final opening in stores) {
      final ArtworkStore store;
      try {
        store = await opening;
      } catch (_) {
        // It never opened, and whoever asked for it has the error.
        continue;
      }
      await store.retire();
    }
  }

  Future<Directory> _root() async =>
      Directory('${(await _directory()).path}/artwork');

  Future<ArtworkStore> _store(String instanceId) {
    if (_closed) {
      return Future.error(const ArtworkException('the cache is closed'));
    }
    return _stores[instanceId] ??= _open(instanceId);
  }

  Future<ArtworkStore> _open(String instanceId) async {
    try {
      await _clearing;
      return ArtworkStore(
        Directory('${(await _root()).path}/${_digest(instanceId)}'),
        maximumBytes: _maximumBytes,
        freshFor: _freshFor,
      );
    } catch (_) {
      // So that the next load tries again.
      unawaited(_stores.remove(instanceId));
      rethrow;
    }
  }
}

final class _Loader implements ArtworkLoader {
  _Loader(this._cache, this._instanceId, this._client);

  final ArtworkCache _cache;
  final String _instanceId;
  final ServiceHttpClient _client;

  @override
  ImageProvider<Object>? image(MediaImage image) {
    final path = image.instancePath;
    if (path != null) {
      if (_instanceRequest(path) case final request?) {
        return _provider('instance\n$path', () => _fromInstance(request));
      }
    }
    final url = image.remoteUrl;
    if (url == null || !_cache._loadRemote() || !isRemoteAddress(url)) {
      return null;
    }
    return _provider('remote\n$url', () => _fromRemote(url));
  }

  ArtworkImage _provider(String name, ArtworkSource source) => ArtworkImage(
    owner: _cache,
    instanceId: _instanceId,
    key: _digest(name),
    store: () => _cache._store(_instanceId),
    source: source,
  );

  Future<Uint8List> _fromInstance(ServiceRequest request) async =>
      switch (await _client.send(request)) {
        Ok(:final value) => _picture(value.bytes),
        Err(:final error) => throw ArtworkException(
          '${error.failure.runtimeType}',
          gone: error.failure is NotFound,
        ),
      };

  Future<Uint8List> _fromRemote(Uri url) async {
    // It may have been switched off since the image was made.
    if (!_cache._loadRemote()) {
      throw const ArtworkException('remote artwork is switched off');
    }
    final int status;
    final Uint8List bytes;
    try {
      final response = await _cache._remote.get(url);
      status = response.statusCode;
      bytes = response.bytes;
    } catch (error) {
      // The type only: the text may quote the address.
      throw ArtworkException('${error.runtimeType}');
    }
    if (status != HttpStatus.ok) {
      throw ArtworkException(
        'status $status',
        gone: status == HttpStatus.notFound || status == HttpStatus.gone,
      );
    }
    return _picture(bytes);
  }
}

Uint8List _picture(Uint8List bytes) =>
    bytes.isEmpty ? throw const ArtworkException('empty answer') : bytes;

String _digest(String text) => sha256.convert(utf8.encode(text)).toString();

/// The request of a `MediaImage.instancePath`, a path under the instance's
/// address with perhaps a query, as a server writes it, so percent-encoded.
/// Null if it is not that.
ServiceRequest? _instanceRequest(String instancePath) {
  final reference = instancePath.split('#').first;
  final mark = reference.indexOf('?');
  final path = (mark < 0 ? reference : reference.substring(0, mark))
      .replaceFirst(RegExp('^/+'), '');
  if (path.isEmpty) return null;
  try {
    final segments = [
      for (final segment in path.split('/')) Uri.decodeComponent(segment),
    ];
    // An encoded slash would become a separator.
    if (segments.any((segment) => segment.contains('/'))) return null;
    final query = <String, List<String>>{};
    for (final pair
        in mark < 0
            ? const <String>[]
            : reference.substring(mark + 1).split('&')) {
      if (pair.isEmpty) continue;
      final equals = pair.indexOf('=');
      final name = equals < 0 ? pair : pair.substring(0, equals);
      final value = equals < 0 ? '' : pair.substring(equals + 1);
      (query[Uri.decodeComponent(name)] ??= []).add(Uri.decodeComponent(value));
    }
    return ServiceRequest(HttpMethod.get, segments.join('/'), query: query);
  } on ArgumentError {
    // A broken escape, or a path that ServiceRequest refuses as it could leave
    // the instance's address.
    return null;
  }
}
