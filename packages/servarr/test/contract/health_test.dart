// The health read: `type` is the level and `wikiUrl` the help link. Disk space
// comes with a later task.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<HealthIssue> _one(
  Service service, [
  Map<String, Object?> changes = const {},
  List<String> without = const [],
]) async {
  final entry = service.list('health').first
    ..addAll(changes)
    ..removeWhere((key, _) => without.contains(key));
  final server = FakeServer.paths({
    'health': [entry],
  });
  return (await value(service.client(server).health())).single;
}

void main() {
  for (final service in services) {
    group('${service.name} health', () {
      test('asks for the health list', () async {
        final server = FakeServer.paths({'health': service.fixture('health')});

        await value(service.client(server).health());

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/health');
        expect(request.query, isEmpty);
        expect(request.body, isNull);
      });

      test('maps every issue in server order', () async {
        final server = FakeServer.paths({'health': service.fixture('health')});

        final issues = await value(service.client(server).health());

        expect(issues.map((issue) => issue.level), [
          HealthLevel.error,
          HealthLevel.warning,
          HealthLevel.notice,
        ]);
        expect(issues.first.source, 'IndexerRssCheck');
        expect(
          issues.first.message,
          'No indexers available with RSS sync enabled',
        );
        expect(
          issues.first.helpUrl,
          Uri.parse(
            'https://wiki.servarr.com/${service.name.toLowerCase()}/system'
            '#no-indexers-available-with-rss-sync-enabled',
          ),
        );
      });

      test('reads a level it does not know as unknown', () async {
        final issue = await _one(service, {'type': 'someFutureLevel'});

        expect(issue.level, HealthLevel.unknown);
      });

      test('accepts an issue without a help link', () async {
        final issue = await _one(service, const {}, ['wikiUrl']);

        expect(issue.helpUrl, isNull);
      });

      test('is empty on a healthy server', () async {
        final server = FakeServer.paths({'health': <Object?>[]});

        expect(await value(service.client(server).health()), isEmpty);
      });

      for (final field in ['source', 'message']) {
        test('cannot understand an issue without $field', () async {
          final entry = service.list('health').first..remove(field);
          final server = FakeServer.paths({
            'health': [entry],
          });

          expect(
            await failure(service.client(server).health()),
            isA<MalformedResponse>(),
          );
        });
      }
    });
  }
}
