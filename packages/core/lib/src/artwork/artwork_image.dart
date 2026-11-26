import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'artwork_file_service.dart';
import 'artwork_store.dart';

/// One piece of an instance's artwork, read through its store.
///
/// Equal only to an image of the same cache, instance and artwork, so that
/// Flutter's memory cache cannot give one instance the picture of another.
final class ArtworkImage extends ImageProvider<ArtworkImage> {
  /// Creates an [ArtworkImage] of the artwork [key] of [instanceId].
  const ArtworkImage({
    required this._owner,
    required this.instanceId,
    required this.key,
    required this._store,
    required this._source,
  });

  final Object _owner;

  /// Whose artwork this is.
  final String instanceId;

  /// Which artwork this is: a digest, so that it can be printed.
  final String key;

  final Future<ArtworkStore> Function() _store;
  final ArtworkSource _source;

  @override
  Future<ArtworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ArtworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: key._load(decode),
    scale: 1,
    debugLabel: 'artwork',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final store = await _store();
      final file = await store.file(key, _source);
      final bytes = await file.readAsBytes();
      try {
        return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      } catch (_) {
        // Not a picture: it must not be kept as if it were.
        await store.remove(key);
        rethrow;
      }
    } catch (_) {
      // So that it is tried again the next time it is shown.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(this));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ArtworkImage &&
      identical(other._owner, _owner) &&
      other.instanceId == instanceId &&
      other.key == key;

  @override
  int get hashCode => Object.hash(_owner, instanceId, key);

  @override
  String toString() => 'ArtworkImage($instanceId, $key)';
}
