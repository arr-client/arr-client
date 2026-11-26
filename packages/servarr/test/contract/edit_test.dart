// Editing without data loss (research R13; story 5, scenarios 5 and 8): the
// record is read, the changed fields are set in it and the whole of it is
// written back. Whatever the user did not change goes back as the server sent
// it, a field the app does not know included.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servarr/servarr.dart';

import 'manage_support.dart';
import 'support.dart';

String _path(Service service) =>
    service == radarr ? 'movie/${_id(service)}' : 'series/${_id(service)}';

int _id(Service service) => service.object('manage_item')['id']! as int;

/// The recorded item with what no version of the app can know about.
JsonObject _record(Service service) => service.object('manage_item')
  ..['someFutureFlag'] = true
  ..['someFutureObject'] = {
    'list': [
      1,
      null,
      2.5,
      {'deep': 'kept'},
    ],
    'empty': <Object?>[],
  }
  // Left out is not the same to every server as null.
  ..['someFutureNull'] = null
  ..['someFutureText'] = 'Ünïcode "quoted" \\ text';

/// A server that has [record] and accepts a write of it, as recorded: with 202
/// and the record.
FakeServer _server(Service service, JsonObject record) => routes({
  'GET ${_path(service)}': Reply.json(record),
  'PUT ${_path(service)}': Reply.json(record, status: 202),
});

/// What [changes] makes the client write over [record].
Future<JsonObject> _written(
  Service service,
  ItemEdit changes, [
  JsonObject? record,
]) async {
  final server = _server(service, record ?? _record(service));
  await value(service.client(server).edit(_path(service), changes));
  return sentBody(server.requests.last)! as JsonObject;
}

/// Asserts that [written] is [record] with [changed] and nothing else.
void _expectOnly(
  JsonObject written,
  JsonObject record,
  Map<String, Object?> changed,
) {
  expect(written.keys.toSet(), {...record.keys, ...changed.keys});
  for (final key in written.keys) {
    expect(
      written[key],
      changed.containsKey(key) ? changed[key] : record[key],
      reason: key,
    );
  }
}

/// Each field of an edit, and what it writes.
final _fields = <String, (ItemEdit, Map<String, Object?>)>{
  'monitoring': (const ItemEdit(monitored: false), {'monitored': false}),
  'the quality profile': (
    const ItemEdit(qualityProfileId: 6),
    {'qualityProfileId': 6},
  ),
  'tags': (
    const ItemEdit(tagIds: {2}),
    {
      'tags': [2],
    },
  ),
  // The set is the whole new one.
  'no tags': (const ItemEdit(tagIds: {}), {'tags': <int>[]}),
};

const _seriesFields = <String, (ItemEdit, Map<String, Object?>)>{
  'the series type daily': (
    ItemEdit(seriesType: SeriesType.daily),
    {'seriesType': 'daily'},
  ),
  'the series type anime': (
    ItemEdit(seriesType: SeriesType.anime),
    {'seriesType': 'anime'},
  ),
  'season folders': (ItemEdit(seasonFolder: false), {'seasonFolder': false}),
};

const _movieFields = <String, (ItemEdit, Map<String, Object?>)>{
  'minimum availability tba': (
    ItemEdit(minimumAvailability: MinimumAvailability.tba),
    {'minimumAvailability': 'tba'},
  ),
  'minimum availability announced': (
    ItemEdit(minimumAvailability: MinimumAvailability.announced),
    {'minimumAvailability': 'announced'},
  ),
  'minimum availability in cinemas': (
    ItemEdit(minimumAvailability: MinimumAvailability.inCinemas),
    {'minimumAvailability': 'inCinemas'},
  ),
};

void main() {
  for (final service in services) {
    group('${service.name} edit', () {
      test('reads the record and then writes it to the same path', () async {
        final server = _server(service, _record(service));

        await value(
          service
              .client(server)
              .edit(_path(service), const ItemEdit(monitored: false)),
        );

        expect(server.requests, hasLength(2));
        final [read, write] = server.requests;
        expect(read.method, HttpMethod.get);
        expect(read.path, 'api/v3/${_path(service)}');
        expect(read.query, isEmpty);
        expect(write.method, HttpMethod.put);
        expect(write.path, 'api/v3/${_path(service)}');
        // `moveFiles` among others is never asked for.
        expect(write.query, isEmpty);
      });

      final own = service == radarr ? _movieFields : _seriesFields;
      for (final MapEntry(key: name, value: (changes, changed)) in {
        ..._fields,
        ...own,
      }.entries) {
        test('of $name keeps every other field', () async {
          _expectOnly(
            await _written(service, changes),
            _record(service),
            changed,
          );
        });
      }

      test('of several fields at once keeps the rest', () async {
        _expectOnly(
          await _written(
            service,
            const ItemEdit(monitored: false, qualityProfileId: 6, tagIds: {}),
          ),
          _record(service),
          {'monitored': false, 'qualityProfileId': 6, 'tags': <int>[]},
        );
      });

      // Lidarr and Readarr have it; the field is the same across the family.
      test('of the metadata profile keeps every other field', () async {
        final record = _record(service)..['metadataProfileId'] = 1;

        _expectOnly(
          await _written(service, const ItemEdit(metadataProfileId: 2), record),
          record,
          {'metadataProfileId': 2},
        );
      });

      test('applies to the record as the server has it now', () async {
        // Changed elsewhere since the app displayed it.
        var record = _record(service);
        final server = FakeServer(
          (request) => Reply.json(
            record,
            status: request.method == HttpMethod.get ? 200 : 202,
          ),
        );
        final client = service.client(server);
        await value(
          client.edit(_path(service), const ItemEdit(monitored: false)),
        );
        record = _record(service)
          ..['monitored'] = false
          ..['tags'] = [1, 2]
          ..['path'] = '/redacted/moved';

        await value(
          client.edit(_path(service), const ItemEdit(qualityProfileId: 6)),
        );

        expect(server.requests.map((request) => request.method), [
          HttpMethod.get,
          HttpMethod.put,
          HttpMethod.get,
          HttpMethod.put,
        ]);
        _expectOnly(sentBody(server.requests.last)! as JsonObject, record, {
          'qualityProfileId': 6,
        });
      });

      test('writes no value it does not know', () async {
        _expectOnly(
          await _written(
            service,
            const ItemEdit(
              monitored: false,
              seriesType: SeriesType.unknown,
              minimumAvailability: MinimumAvailability.unknown,
            ),
          ),
          _record(service),
          {'monitored': false},
        );
      });

      for (final (name, changes) in [
        ('no change', const ItemEdit()),
        (
          'only values it does not know',
          const ItemEdit(
            seriesType: SeriesType.unknown,
            minimumAvailability: MinimumAvailability.unknown,
          ),
        ),
      ]) {
        test('sends nothing for $name', () async {
          final server = _server(service, _record(service));

          await value(service.client(server).edit(_path(service), changes));

          expect(server.requests, isEmpty);
        });
      }
    });
  }

  group('Sonarr change of one season', () {
    /// As a module would turn monitoring of season [number] off.
    void Function(JsonObject) unmonitor(int number) => (record) {
      final seasons = (record['seasons']! as List<Object?>).cast<JsonObject>();
      seasons.firstWhere(
        (season) => season['seasonNumber'] == number,
      )['monitored'] = false;
    };

    test('keeps the series and the other seasons', () async {
      final server = _server(sonarr, _record(sonarr));

      await value(sonarr.client(server).update(_path(sonarr), unmonitor(2)));

      final expected = _record(sonarr);
      unmonitor(2)(expected);
      expect(expected, isNot(_record(sonarr)));
      expect(server.requests, hasLength(2));
      expect(server.requests.last.method, HttpMethod.put);
      expect(sentBody(server.requests.last), expected);
    });

    test('writes nothing if the record cannot be understood', () async {
      final server = _server(sonarr, _record(sonarr));

      expect(
        await failure(
          sonarr
              .client(server)
              .update(
                _path(sonarr),
                (record) => throw const FormatException('No seasons'),
              ),
        ),
        isA<MalformedResponse>(),
      );
      expect(server.requests.single.method, HttpMethod.get);
    });
  });

  ServiceResult<void> edit(ServarrClient client) =>
      client.edit('movie/${_id(radarr)}', const ItemEdit(qualityProfileId: 6));

  group('an edit whose read fails', () {
    final failures = <String, (Answer, Type)>{
      ...transportFailures,
      // As recorded for an item that does not exist.
      'an item that is gone': (const Reply(404, ''), NotFound),
      'JSON that breaks off': (const Reply(200, '{"id":'), MalformedResponse),
      'JSON of another shape': (const Reply(200, '[]'), MalformedResponse),
    };

    for (final MapEntry(key: cause, value: (answer, expected))
        in failures.entries) {
      test('reports $cause and writes nothing', () async {
        final server = FakeServer.always(answer);

        final result = await failure(edit(radarr.client(server)));

        expect(result.runtimeType, expected);
        expect(server.requests, isNotEmpty);
        expect(
          server.requests.map((request) => request.method),
          everyElement(HttpMethod.get),
        );
      });
    }
  });

  group('an edit whose write fails', () {
    final failures = <String, (Answer, Type)>{
      ...writeFailures,
      // As recorded.
      'a quality profile that does not exist': (
        Reply.json([
          {
            'propertyName': 'QualityProfileId',
            'errorMessage': 'Quality Profile does not exist',
          },
        ], status: 400),
        Validation,
      ),
    };

    for (final MapEntry(key: cause, value: (answer, expected))
        in failures.entries) {
      test('reports $cause and is sent once', () async {
        final server = FakeServer(
          (request) => request.method == HttpMethod.get
              ? Reply.json(_record(radarr))
              : answer,
        );

        final result = await failure(edit(radarr.client(server)));

        expect(result.runtimeType, expected);
        expect(server.requests.map((request) => request.method), [
          HttpMethod.get,
          HttpMethod.put,
        ]);
      });
    }
  });
}
