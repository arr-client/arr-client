/// What is kept on disk and in memory, and how it is cleared.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/src/artwork/artwork_repository.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../network/support.dart';
import 'support.dart';

void main() {
  setUpImages();

  InstanceHttpClient client(TestServer server) =>
      clientFor(settingsFor(server.url()));

  /// Drops Flutter's own copies, so that the next load goes to the disk.
  void forgetMemory() => PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages();

  test('is kept, and shown without the server after a restart', () async {
    final directory = temporaryDirectory();
    final server = await pictureServer(twoPixels);
    final first = cacheIn(directory);
    await widthOf(
      first.loaderFor('a', client(server)).image(instanceImage('poster')),
    );
    await first.close();
    forgetMemory();

    final width = await widthOf(
      cacheIn(directory)
          .loaderFor('a', clientFor(settingsFor(Uri.parse('http://[::1]:1'))))
          .image(instanceImage('poster')),
    );

    expect(width, 2);
    expect(server.requests, hasLength(1));
  });

  test('neither file names nor files hold an address or a secret', () async {
    final directory = temporaryDirectory();
    final server = await pictureServer(onePixel);
    final cache = cacheIn(directory);
    final loader = cache.loaderFor('instance-id', client(server));

    await widthOf(loader.image(instanceImage('secretpath?apikey=$apiKey')));
    await widthOf(
      loader.image(remoteImage(server.url('/remotepath?token=hidden-token'))),
    );
    await cache.close();

    final files = filesIn(directory);
    expect(files.keys.where((name) => name.endsWith('.img')), hasLength(2));
    final everything = [
      for (final MapEntry(:key, :value) in files.entries)
        '$key ${latin1.decode(value)}',
    ].join(' ');
    for (final text in [
      ...secretValues,
      'secretpath',
      'remotepath',
      'hidden-token',
      '127.0.0.1',
      'instance-id',
    ]) {
      expect(everything, isNot(contains(text)));
    }
  });

  test('instances do not share pictures', () async {
    final one = await pictureServer(onePixel);
    final two = await pictureServer(twoPixels);
    final cache = cacheIn(temporaryDirectory());
    final first = cache.loaderFor('a', client(one));
    final second = cache.loaderFor('b', client(two));
    final image = instanceImage('MediaCover/1/poster.jpg');

    expect(first.image(image), isNot(second.image(image)));
    expect(first.image(image), first.image(image));
    expect(await widthOf(first.image(image)), 1);
    expect(await widthOf(second.image(image)), 2);
    forgetMemory();
    expect(await widthOf(first.image(image)), 1);
    expect(await widthOf(second.image(image)), 2);
    expect(one.requests, hasLength(1));
    expect(two.requests, hasLength(1));
  });

  test('clearing one instance leaves the others', () async {
    final directory = temporaryDirectory();
    final server = await pictureServer(onePixel);
    final cache = cacheIn(directory);
    final first = cache.loaderFor('a', client(server));
    final second = cache.loaderFor('b', client(server));
    await widthOf(first.image(instanceImage('first')));
    await widthOf(second.image(instanceImage('second')));

    await cache.clear(instanceId: 'a');

    expect(
      filesIn(directory).keys.where((name) => name.endsWith('.img')),
      hasLength(1),
    );
    expect(Directory('${directory.path}/artwork').listSync(), hasLength(1));
    await widthOf(first.image(instanceImage('first')));
    await widthOf(second.image(instanceImage('second')));
    expect(server.requests.map((r) => r.target), [
      '/first',
      '/second',
      '/first',
    ]);
  });

  test('clearing everything includes instances not used since start', () async {
    final directory = temporaryDirectory();
    final server = await pictureServer(onePixel);
    final first = cacheIn(directory);
    await widthOf(
      first.loaderFor('a', client(server)).image(instanceImage('poster')),
    );
    await first.close();

    await cacheIn(directory).clear();

    expect(directory.listSync(), isEmpty);
  });

  test('clearing fails a load under way and leaves nothing', () async {
    final directory = temporaryDirectory();
    final asked = Completer<void>();
    final answer = Completer<void>();
    final server = await TestServer.start((_, response) async {
      asked.complete();
      await answer.future;
      await picture(response, onePixel);
    });
    final cache = cacheIn(directory);
    final loading = widthOf(
      cache.loaderFor('a', client(server)).image(instanceImage('poster')),
    );
    final failed = expectLater(loading, throwsArtworkException);
    await asked.future;

    await cache.clear();
    await failed;
    answer.complete();
    await pause();

    expect(directory.listSync(), isEmpty);
  });

  test('what is not a picture is not kept', () async {
    var body = utf8.encode('not a picture');
    final server = await TestServer.start(
      (_, response) => picture(response, body),
    );
    final loader = cacheIn(temporaryDirectory()).loaderFor('a', client(server));

    await expectLater(
      widthOf(loader.image(instanceImage('poster'))),
      throwsA(anything),
    );
    await pause();
    body = onePixel;

    expect(await widthOf(loader.image(instanceImage('poster'))), 1);
    expect(server.requests, hasLength(2));
  });

  test('a failure is tried again the next time', () async {
    var status = 500;
    final server = await TestServer.start(
      (_, response) => status == 200
          ? picture(response, onePixel)
          : reply(response, status: status),
    );
    final loader = cacheIn(temporaryDirectory()).loaderFor('a', client(server));

    await expectLater(
      widthOf(loader.image(instanceImage('poster'))),
      throwsArtworkException,
    );
    await pause();
    status = 200;

    expect(await widthOf(loader.image(instanceImage('poster'))), 1);
  });

  test('an old picture is shown and read again', () async {
    var body = onePixel;
    final server = await TestServer.start(
      (_, response) => picture(response, body),
    );
    final loader = cacheIn(
      temporaryDirectory(),
      freshFor: Duration.zero,
    ).loaderFor('a', client(server));
    Future<int> load() async {
      forgetMemory();
      final width = await widthOf(loader.image(instanceImage('poster')));
      await pause();
      return width;
    }

    expect(await load(), 1);
    body = twoPixels;

    expect(await load(), 1);
    expect(await load(), 2);
  });

  test('an old picture that is gone is forgotten, else kept', () async {
    var status = 200;
    final server = await TestServer.start(
      (_, response) => status == 200
          ? picture(response, onePixel)
          : reply(response, status: status),
    );
    final loader = cacheIn(
      temporaryDirectory(),
      freshFor: Duration.zero,
    ).loaderFor('a', client(server));
    Future<int> load() async {
      forgetMemory();
      try {
        return await widthOf(loader.image(instanceImage('poster')));
      } finally {
        await pause();
      }
    }

    await load();
    status = 500;
    expect(await load(), 1);
    expect(await load(), 1);
    status = 404;
    expect(await load(), 1);

    await expectLater(load(), throwsArtworkException);
  });

  test('the least recently used files beyond a limit are removed', () async {
    final repository = ArtworkRepository(
      File('${temporaryDirectory().path}/index.json'),
      maximumBytes: 100,
    );
    await repository.open();
    addTearDown(repository.close);
    for (final (name, length) in [('old', 50), ('middle', 50), ('new', 50)]) {
      await repository.insert(
        CacheObject(
          name,
          relativePath: name,
          validTill: DateTime.now(),
          length: length,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    Future<List<String>> over(int capacity) async => [
      for (final object in await repository.getObjectsOverCapacity(capacity))
        object.key,
    ];

    expect(await over(10), ['old']);
    expect(await over(1), ['middle', 'old']);
  });

  test('using a file again does not rewrite the record at once', () async {
    final index = File('${temporaryDirectory().path}/index.json');
    final repository = ArtworkRepository(index, maximumBytes: 100);
    await repository.open();
    addTearDown(repository.close);
    await repository.insert(
      CacheObject('a', relativePath: 'a', validTill: DateTime.now()),
    );
    final written = index.readAsStringSync();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    await repository.updateOrInsert((await repository.get('a'))!);
    expect(index.readAsStringSync(), written);

    await repository.updateOrInsert(
      (await repository.get('a'))!.copyWith(relativePath: 'b'),
    );
    expect(index.readAsStringSync(), isNot(written));
  });

  test('loads fail once closed', () async {
    final server = await RawServer.start();
    final cache = cacheIn(temporaryDirectory());
    final loader = cache.loaderFor('a', clientFor(settingsFor(server.url())));

    await cache.close();

    await expectLater(
      widthOf(loader.image(instanceImage('poster'))),
      throwsArtworkException,
    );
    expect(server.connections, 0);
  });
}
