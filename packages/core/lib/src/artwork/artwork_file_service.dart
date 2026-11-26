import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'artwork_exception.dart';

/// Reads one piece of artwork, or throws an [ArtworkException].
typedef ArtworkSource = Future<Uint8List> Function();

/// Fetches for flutter_cache_manager through the core's own clients, in place
/// of its [HttpFileService], which would follow a redirect with the headers of
/// the first request (research R10).
///
/// The cache manager knows artwork only by an opaque key, which it also gets as
/// the "url", so that no address is written to disk. What a key stands for is
/// registered here, in memory.
final class ArtworkFileService extends FileService {
  /// [freshFor] is how long a file is used before it is read again.
  ArtworkFileService({required this._freshFor}) {
    concurrentFetches = 6;
  }

  final Duration _freshFor;
  final _sources = <String, ArtworkSource>{};
  final _waiting = <Completer<Uint8List>>{};
  var _stopped = false;

  /// Says how to read the artwork of [key].
  void register(String key, ArtworkSource source) => _sources[key] = source;

  /// Fails every fetch, under way and later.
  void stop() {
    _stopped = true;
    for (final fetch in _waiting) {
      if (!fetch.isCompleted) fetch.completeError(_cleared);
    }
  }

  static const _cleared = ArtworkException('the cache was cleared');

  /// [headers] are not sent: no entity tag is kept, so the cache manager has
  /// none to give.
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final source = _sources[url];
    if (_stopped) throw _cleared;
    if (source == null) throw const ArtworkException('unknown artwork');
    final fetch = Completer<Uint8List>();
    _waiting.add(fetch);
    unawaited(
      source().then(
        (bytes) {
          if (!fetch.isCompleted) fetch.complete(bytes);
        },
        onError: (Object error, StackTrace stack) {
          if (!fetch.isCompleted) fetch.completeError(error, stack);
        },
      ),
    );
    try {
      return _Response(await fetch.future, DateTime.now().add(_freshFor));
    } finally {
      _waiting.remove(fetch);
    }
  }
}

final class _Response implements FileServiceResponse {
  _Response(this._bytes, this.validTill);

  final Uint8List _bytes;

  @override
  final DateTime validTill;

  @override
  Stream<List<int>> get content => Stream.value(_bytes);

  @override
  int get contentLength => _bytes.length;

  @override
  int get statusCode => 200;

  @override
  String? get eTag => null;

  // The decoder tells the format from the content.
  @override
  String get fileExtension => '.img';
}
