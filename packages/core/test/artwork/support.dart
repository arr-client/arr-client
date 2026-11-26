/// Pictures, servers of them and the cache under test.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../network/support.dart';

/// Grey PNGs one pixel high and one, two or three wide, to tell them apart.
final onePixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNoAAAAggCBd81'
  'ytgAAAABJRU5ErkJggg==',
);
final twoPixels = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAAAAADRSSBWAAAAC0lEQVR4nGNoaAAAAYMBARg'
  '1IhUAAAAASUVORK5CYII=',
);
final threePixels = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAMAAAABCAAAAAA+i0toAAAADElEQVR4nGNoaGgAAAMEAYF'
  'L09IQAAAAAElFTkSuQmCC',
);

/// Lets images be decoded, and servers on loopback be reached, in tests.
void setUpImages() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The binding answers every request with 400 otherwise.
  setUpAll(() => HttpOverrides.global = null);
  setUp(
    () => PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages(),
  );
}

Future<void> picture(HttpResponse response, Uint8List bytes) {
  response.headers.set('content-type', 'image/png');
  response.add(bytes);
  return response.close();
}

/// A server that answers every request with [bytes].
Future<TestServer> pictureServer(Uint8List bytes) =>
    TestServer.start((_, response) => picture(response, bytes));

/// A directory deleted after the test.
Directory temporaryDirectory() {
  final directory = Directory.systemTemp.createTempSync('artwork_test_');
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

/// A cache in [directory], closed after the test.
ArtworkCache cacheIn(
  Directory directory, {
  bool Function()? loadRemote,
  Duration freshFor = const Duration(days: 7),
}) {
  final cache = ArtworkCache(
    directory: () async => directory,
    loadRemote: loadRemote ?? () => true,
    freshFor: freshFor,
  );
  addTearDown(cache.close);
  return cache;
}

MediaImage instanceImage(String path, {Uri? remoteUrl}) => MediaImage(
  type: MediaImageType.poster,
  instancePath: path,
  remoteUrl: remoteUrl,
);

MediaImage remoteImage(Uri url) =>
    MediaImage(type: MediaImageType.poster, remoteUrl: url);

/// Loads [provider] as a widget would, and returns the picture's width.
Future<int> widthOf(ImageProvider<Object>? provider) {
  final width = Completer<int>();
  final stream = provider!.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      width.complete(info.image.width);
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (error, _) {
      width.completeError(error);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return width.future.timeout(const Duration(seconds: 10));
}

final throwsArtworkException = throwsA(isA<ArtworkException>());

/// Every file under [directory], by its path below it.
Map<String, List<int>> filesIn(Directory directory) => {
  for (final file in directory.listSync(recursive: true).whereType<File>())
    file.path.substring(directory.path.length): file.readAsBytesSync(),
};
