// Server options and the credits of a movie against recorded answers.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_support.dart';

// What sanitizing took the shape from: Radarr 7.0 gives a credit's picture as
// a proxy address that no listed read serves, with the public one beside it.
const _proxied =
    '/MediaCoverProxy/5d4f05b25774fadd80cf14d0282204d769bd7e86/headshot.jpg';
const _public = 'https://image.tmdb.org/t/p/original/headshot.jpg';

void main() {
  group('options', () {
    test('reads profiles, root folders and tags', () async {
      final harness = Harness();

      await succeed(harness.library.options());

      expect(
        harness.server.requests.map((r) => r.path),
        unorderedEquals([
          'api/v3/qualityprofile',
          'api/v3/rootfolder',
          'api/v3/tag',
        ]),
      );
      expect(harness.server.requests.map((r) => r.method).toSet(), {
        HttpMethod.get,
      });
    });

    test('maps quality profiles', () async {
      final options = await succeed(Harness().library.options());

      final profiles = options.where(
        (o) => o.kind == ServerOptionKind.qualityProfile,
      );
      expect(
        profiles.map((o) => (o.id, o.label, o.freeSpace)),
        unorderedEquals([
          for (final wire in records(fixture('qualityprofile')))
            (wire['id'], wire['name'], null),
        ]),
      );
    });

    test('labels a root folder by its path, with its free space', () async {
      final wire = records(fixture('rootfolder')).single;

      final options = await succeed(Harness().library.options());

      final folder = options.singleWhere(
        (o) => o.kind == ServerOptionKind.rootFolder,
      );
      expect(folder.id, wire['id']);
      expect(folder.label, wire['path']);
      expect(folder.freeSpace, wire['freeSpace']);
    });

    test('maps tags', () async {
      final options = await succeed(Harness().library.options());

      final tags = options.where((o) => o.kind == ServerOptionKind.tag);
      expect(
        tags.map((o) => (o.id, o.label, o.freeSpace)),
        unorderedEquals([
          for (final wire in records(fixture('tag')))
            (wire['id'], wire['label'], null),
        ]),
      );
      // Radarr has no metadata profiles.
      expect(
        options.where((o) => o.kind == ServerOptionKind.metadataProfile),
        isEmpty,
      );
    });

    for (final path in ['qualityprofile', 'rootfolder', 'tag']) {
      test('fails when $path does', () async {
        const failure = ServerError(statusCode: 500);
        final harness = Harness();
        harness.server.answers['api/v3/$path'] = failedAnswer(
          failure,
          status: 500,
        );

        expect(await failureOf(harness.library.options()), same(failure));
      });

      test('cannot understand $path of another shape', () async {
        final harness = Harness();
        harness.server.answers['api/v3/$path'] = textAnswer('{}');

        expect(
          await failureOf(harness.library.options()),
          isA<MalformedResponse>(),
        );
      });
    }
  });

  group('credits', () {
    final wire = records(fixture('credit'));

    Future<Map<String, Credit>> credits(Harness harness) async => {
      for (final credit in await succeed(harness.library.credits(movieRef(3))))
        credit.person: credit,
    };

    test('asks for the credits of the movie', () async {
      final harness = Harness();

      await succeed(harness.library.credits(movieRef(3)));

      final request = harness.server.requests.single;
      expect(request.path, 'api/v3/credit');
      expect(request.query, {
        'movieId': ['3'],
      });
    });

    test('maps cast and crew', () async {
      final result = await credits(Harness());

      expect(result, hasLength(wire.length));
      for (final entry in wire) {
        final credit = result[entry['personName']]!;
        if (entry['type'] == 'cast') {
          expect(credit.type, CreditType.cast);
          expect(credit.character, entry['character']);
          // Radarr gives a cast member no job, and the module makes up none.
          expect(credit.role, isNull);
        } else {
          expect(credit.type, CreditType.crew);
          expect(credit.role, entry['job']);
          expect(credit.character, isNull);
        }
      }
    });

    for (final (what, changes, type, role) in [
      (
        'a crew member with a department only',
        {'job': null},
        CreditType.crew,
        'Directing',
      ),
      (
        'a crew member with neither job nor department',
        {'job': null, 'department': null},
        CreditType.crew,
        null,
      ),
      (
        'a type it does not know',
        {'type': 'someFutureType'},
        CreditType.unknown,
        'Director',
      ),
    ]) {
      test('reads $what', () async {
        final harness = Harness();
        harness.server.answers['api/v3/credit'] = jsonAnswer([
          {
            ...wire.firstWhere((entry) => entry['type'] == 'crew'),
            'job': 'Director',
            'department': 'Directing',
            ...changes,
          },
        ]);

        final credit = (await credits(harness)).values.single;

        expect(credit.type, type);
        expect(credit.role, role);
        expect(credit.character, isNull);
      });
    }

    test('takes a headshot from its public address', () async {
      final harness = Harness();
      harness.server.answers['api/v3/credit'] = jsonAnswer([
        {
          ...wire.first,
          'images': [
            {'coverType': 'headshot', 'url': _proxied, 'remoteUrl': _public},
          ],
        },
      ]);

      final image = (await credits(harness)).values.single.image!;

      expect(image.type, MediaImageType.headshot);
      expect(image.instancePath, isNull);
      expect(image.remoteUrl, Uri.parse(_public));
    });

    test('has no picture where the server gives none', () async {
      final without = wire.singleWhere(
        (entry) => (entry['images']! as List<Object?>).isEmpty,
      );

      final result = await credits(Harness());

      expect(result[without['personName']]!.image, isNull);
    });

    test('is empty where the server provides none', () async {
      expect(await succeed(Harness().library.credits(movieRef(1))), isEmpty);
    });

    test('passes on a failure', () async {
      const failure = Unreachable();
      final harness = Harness()..server.down = failedAnswer(failure);

      expect(
        await failureOf(harness.library.credits(movieRef(3))),
        same(failure),
      );
    });

    test('cannot understand a body of another shape', () async {
      final harness = Harness()..server.down = textAnswer('{}');

      expect(
        await failureOf(harness.library.credits(movieRef(3))),
        isA<MalformedResponse>(),
      );
    });
  });
}
