// Interactive search for a book or an author, and grab (story 8, scenario 4, as
// story 5).
//
// A release the server could not match has `downloadAllowed` false. The server
// then refuses a grab that names no book or author (404), and takes `bookId` or
// `authorId` as what to download it as.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<Release> _release(
  Harness harness,
  MediaTarget target, {
  required bool allowed,
}) async {
  final found = await ok(harness.releases.releases(target));
  harness.server.requests.clear();
  return found.firstWhere((release) => release.downloadAllowed == allowed);
}

void main() {
  for (final (target, parameter, fixture) in [
    (book(9), 'bookId', 'manage_releases_book'),
    (author(), 'authorId', 'manage_releases'),
  ]) {
    final name = target.item.kind.name;

    test('searches for the $name', () async {
      final harness = Harness();

      final found = await ok(harness.releases.releases(target));

      expect(harness.asked, [line(HttpMethod.get, 'release')]);
      expect(harness.server.requests.single.query, {
        parameter: ['${target.item.remoteId}'],
      });
      expect(found, hasLength(records(fixture).length));
      expect(
        found.map((release) => release.searchTarget),
        everyElement({parameter: target.item.remoteId}),
      );
    });

    test('grabs a release found for the $name by naming it', () async {
      final harness = Harness();
      final release = await _release(harness, target, allowed: true);

      await ok(harness.releases.grab(release));

      expect(harness.asked, [line(HttpMethod.post, 'release')]);
      expect(sentBody(harness.server.writes.single), {
        'guid': release.guid,
        'indexerId': release.indexerId,
      });
    });

    test('grabs an unmatched one as what the $name search was for', () async {
      final harness = Harness();
      final release = await _release(harness, target, allowed: false);

      await ok(harness.releases.grab(release));

      expect(sentBody(harness.server.writes.single), {
        'guid': release.guid,
        'indexerId': release.indexerId,
        parameter: target.item.remoteId,
      });
    });
  }

  test('maps a release', () async {
    final raw = records('manage_releases').first;

    final release = (await ok(Harness().releases.releases(author())))
        .singleWhere((release) => release.guid == raw['guid']);

    expect(release.title, raw['title']);
    expect(release.indexer, raw['indexer']);
    expect(release.indexerId, raw['indexerId']);
    expect(release.protocol, DownloadProtocol.torrent);
    expect(release.size, raw['size']);
    expect(release.quality?.name, 'EPUB');
    expect(release.seeders, raw['seeders']);
    expect(release.leechers, raw['leechers']);
    expect(release.rejections, raw['rejections']);
    expect(release.languages, isEmpty);
    expect(release.downloadAllowed, isTrue);
  });

  for (final (name, target) in [
    ('a movie', movie),
    ('a season', MediaTarget(authorRef(1), seasonNumber: 1)),
    ('an author of another instance', const MediaTarget(elsewhere)),
  ]) {
    test('does not search for $name', () async {
      final harness = Harness();

      await expectProgrammingError(() => harness.releases.releases(target));

      expect(harness.server.requests, isEmpty);
    });
  }

  for (final MapEntry(key: cause, value: (answer, expected))
      in writeFailures.entries) {
    test('$cause is reported and a grab is sent once', () async {
      final harness = Harness();
      final release = await _release(harness, book(9), allowed: true);
      harness.server.writeAnswer = answer;

      final failure = await failureOf(harness.releases.grab(release));

      expect(failure.runtimeType, expected);
      expect(harness.server.requests, hasLength(1));
    });
  }
}
