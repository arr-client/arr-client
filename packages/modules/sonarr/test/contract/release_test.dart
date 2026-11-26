// Interactive search and grab (story 5, scenarios 3 and 4). The shared client's
// tests cover how a release is read; these cover what Sonarr is asked.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonarr/sonarr_module.dart';

import 'manage_support.dart';
import 'support.dart';

/// Whether the server says [release] can be grabbed as it is.
bool _allowed(Release release) => release.rawJson['downloadAllowed'] == true;

/// Each kind of recorded release.
final _kinds = <String, bool Function(Release)>{
  'an accepted release': (release) =>
      _allowed(release) && release.rejections.isEmpty,
  'a rejected release': (release) =>
      _allowed(release) && release.rejections.isNotEmpty,
  'an unmatched release': (release) => !_allowed(release),
};

/// The first release of [kind] that a search of [target] finds.
Future<Release> _found(
  ReleaseProvider provider,
  MediaTarget target,
  String kind,
) async => (await ok(provider.releases(target))).firstWhere(_kinds[kind]!);

void main() {
  test('the module offers releases', () {
    expect(
      SonarrModule().capabilitiesFor(
        const ProbeResult(
          product: 'Sonarr',
          version: '4.0.20.3014',
          newerThanTested: false,
        ),
        null,
      ),
      contains(CapabilityKind.release),
    );
    final harness = ManageHarness();
    expect(harness.releases, isA<ReleaseProvider>());
    expect(harness.sonarr.requests, isEmpty);
  });

  for (final (name, target, query, fixture) in [
    (
      'an episode',
      episode(),
      {
        'episodeId': ['31'],
      },
      'manage_releases',
    ),
    (
      'a season',
      season(1),
      {
        'seriesId': ['1'],
        'seasonNumber': ['1'],
      },
      'manage_releases_season',
    ),
    (
      'the specials',
      season(0),
      {
        'seriesId': ['1'],
        'seasonNumber': ['0'],
      },
      'manage_releases_season',
    ),
  ]) {
    test('searches for $name and grabs nothing', () async {
      final harness = ManageHarness();

      final releases = await ok(harness.releases.releases(target));

      final request = harness.sonarr.requests.single;
      expect(request.method, HttpMethod.get);
      expect(request.path, 'api/v3/release');
      expect(request.query, query);
      expect(request.body, isNull);
      // The server asks its indexers while the request is open.
      expect(request.timeout, const Duration(minutes: 2));
      expect(
        releases.map((release) => release.guid),
        records(fixture).map((record) => record['guid']),
      );
      expect(
        releases.map((release) => release.rejections),
        records(fixture).map((record) => record['rejections']),
      );
    });
  }

  // Without both ids of a season, or one of an episode, Sonarr answers with
  // its RSS feeds.
  for (final (name, target) in [
    ('a whole series', series()),
    ('a movie', movie),
    ('an episode of a season', MediaTarget(episodeRef(31), seasonNumber: 1)),
    (
      'a season of another instance',
      const MediaTarget(elsewhere, seasonNumber: 1),
    ),
  ]) {
    test('does not search for $name', () async {
      final harness = ManageHarness();

      await expectProgrammingError(() => harness.releases.releases(target));

      expect(harness.sonarr.requests, isEmpty);
    });
  }

  for (final MapEntry(key: cause, value: (answer, expected))
      in transportFailures.entries) {
    test('a search reports $cause', () async {
      final harness = ManageHarness()..sonarr.always = answer;

      final failure = await failureOf(harness.releases.releases(episode()));

      expect(failure.runtimeType, expected);
    });
  }

  // As Sonarr's web UI grabs. A release the server could not match to the
  // series has `downloadAllowed` false, and is only found again if the grab
  // says what was searched for; without that the server answers 404. Any other
  // release, rejected ones too, is grabbed by its indexer and guid alone.
  for (final (search, target, searched) in [
    ('an episode', episode(), {'episodeId': 31}),
    ('a season', season(1), {'seriesId': 1, 'seasonNumber': 1}),
    ('the specials', season(0), {'seriesId': 1, 'seasonNumber': 0}),
  ]) {
    for (final kind in _kinds.keys) {
      final unmatched = kind == 'an unmatched release';
      final names = unmatched
          ? 'naming what was searched'
          : 'by indexer and guid';

      test('grabs $kind of a search for $search $names', () async {
        final harness = ManageHarness();
        final provider = harness.releases;
        final release = await _found(provider, target, kind);
        harness.sonarr.requests.clear();

        await ok(provider.grab(release));

        final request = harness.sonarr.requests.single;
        expect(request.method, HttpMethod.post);
        expect(request.path, 'api/v3/release');
        expect(request.query, isEmpty);
        expect(sentBody(request), {
          'guid': release.guid,
          'indexerId': release.indexerId,
          if (unmatched) ...searched,
        });
      });
    }
  }

  test('grabs with what its own search was for, not a later one', () async {
    final harness = ManageHarness();
    final provider = harness.releases;
    final release = await _found(provider, episode(), 'an unmatched release');
    await ok(provider.releases(season(2)));
    await ok(provider.releases(episode(37)));
    harness.sonarr.requests.clear();

    await ok(provider.grab(release));

    expect(sentBody(harness.sonarr.requests.single), {
      'guid': release.guid,
      'indexerId': release.indexerId,
      'episodeId': 31,
    });
  });

  for (final MapEntry(key: cause, value: (answer, expected)) in {
    ...writeFailures,
    // The server holds a search's releases for a limited time.
    'a release it no longer holds': (
      FakeSonarr.body(
        '{"message":"Couldn\'t find requested release in cache, try '
        'searching again"}',
        status: 404,
      ),
      NotFound,
    ),
  }.entries) {
    for (final kind in ['an accepted release', 'an unmatched release']) {
      test('a grab of $kind reports $cause and is sent once', () async {
        final harness = ManageHarness();
        final provider = harness.releases;
        final release = await _found(provider, episode(), kind);
        harness.sonarr
          ..requests.clear()
          ..writeAnswer = answer;

        final failure = await failureOf(provider.grab(release));

        expect(failure.runtimeType, expected);
        expect(harness.asked, [line(HttpMethod.post, 'release')]);
      });
    }
  }
}
