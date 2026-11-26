// `HealthProvider`: health (its mapping is in health_test.dart) and disk space.
// Prowlarr reports health only (`providesDiskSpace: false`).

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servarr/servarr.dart';

import 'overview_support.dart';
import 'support.dart';

FakeServer _server(Service service, [List<Object?>? disks]) =>
    FakeServer.paths({
      'diskspace': disks ?? service.fixture('overview_diskspace'),
      'health': service.fixture('health'),
    });

ServarrHealth _health(Service service, FakeServer server) =>
    ServarrHealth(service.overviewClient(server));

void main() {
  for (final service in services) {
    group('${service.name} disk space', () {
      test('asks for the disk space', () async {
        final server = _server(service);

        await value(_health(service, server).diskSpace());

        final request = server.requests.single;
        expect(request.method, HttpMethod.get);
        expect(request.path, 'api/v3/diskspace');
        expect(request.query, isEmpty);
        expect(request.body, isNull);
      });

      test('maps the recorded disk', () async {
        final disks = await value(
          _health(service, _server(service)).diskSpace(),
        );

        expect(disks.map((disk) => (disk.path, disk.free, disk.total)), [
          (
            service.list('overview_diskspace').single['path'],
            80000000000,
            250000000000,
          ),
        ]);
      });

      test('maps every disk in server order, a full one included', () async {
        final disks = await value(
          _health(
            service,
            _server(service, [
              {'path': '/b', 'label': '', 'freeSpace': 0, 'totalSpace': 10},
              {'path': '/a', 'label': 'x', 'freeSpace': 5, 'totalSpace': 20},
            ]),
          ).diskSpace(),
        );

        expect(disks.map((disk) => (disk.path, disk.free, disk.total)), [
          ('/b', 0, 10),
          ('/a', 5, 20),
        ]);
      });

      for (final field in ['path', 'freeSpace', 'totalSpace']) {
        test('cannot understand a disk without $field', () async {
          final disk = service.list('overview_diskspace').single..remove(field);

          expect(
            await failure(
              _health(service, _server(service, [disk])).diskSpace(),
            ),
            isA<MalformedResponse>(),
          );
        });
      }

      test('passes a failure on, asking once', () async {
        final server = FakeServer.always(const Reply(403, ''));

        expect(
          await failure(_health(service, server).diskSpace()),
          isA<Forbidden>(),
        );
        expect(server.requests, hasLength(1));
      });

      test('is not asked for where there is none', () async {
        final server = _server(service);
        final health = ServarrHealth(
          service.overviewClient(server),
          providesDiskSpace: false,
        );

        expect(health.providesDiskSpace, isFalse);
        expect(await value(health.diskSpace()), isEmpty);
        expect(server.requests, isEmpty);
      });
    });

    group('${service.name} health provider', () {
      test('is a provider of both', () {
        final health = _health(service, _server(service));

        expect(health, isA<HealthProvider>());
        expect(health.providesDiskSpace, isTrue);
      });

      test('reports the problems with their message and help link', () async {
        final server = _server(service);

        final issues = await value(_health(service, server).health());

        final recorded = service.list('health');
        expect(server.requests.single.path, 'api/v3/health');
        expect(issues.map((issue) => issue.message), [
          for (final entry in recorded) entry['message'],
        ]);
        expect(issues.map((issue) => issue.helpUrl), [
          for (final entry in recorded) Uri.parse(entry['wikiUrl']! as String),
        ]);
      });

      test('passes a failure on', () async {
        final server = FakeServer.always(const NoReply(Unreachable()));

        expect(
          await failure(_health(service, server).health()),
          isA<Unreachable>(),
        );
      });
    });
  }
}
