// `GET history/since` and `POST history/failed/{id}`.
//
// `eventsSince` sends the time in UTC as `date` and maps the records as
// `history` does. The server answers oldest first; the result is newest first,
// and by id where the dates are the same. The client neither filters nor pages:
// which events are after the time is the server's to say. (The recorded servers
// compare to the fraction of a second but report whole seconds: asked since
// the reported time of an event, they leave that whole second out.)

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'activity_support.dart';
import 'support.dart';

FakeServer _server(Object? body) => only('history/since', Reply.json(body));

void main() {
  final since = DateTime.utc(2026, 11, 26, 13, 57);

  for (final service in services) {
    group('${service.name} events since', () {
      test('asks for the events since the time, in UTC', () async {
        for (final time in [since, since.toLocal()]) {
          final server = _server(<Object?>[]);

          await value(service.client(server).eventsSince(time));

          final request = server.requests.single;
          expect(request.method, HttpMethod.get);
          expect(request.path, 'api/v3/history/since');
          expect(request.query.keys, ['date']);
          final date = request.query['date']!.single;
          expect(date, endsWith('Z'));
          expect(DateTime.parse(date), since);
          expect(request.body, isNull);
        }
      });

      test('lists them newest first', () async {
        final records = service.list('history_since');
        expect(records.map((record) => record['id']), [
          8,
          9,
          10,
          11,
          12,
          13,
          14,
        ]);

        final events = await value(
          service.client(_server(records)).eventsSince(since),
        );

        expect(events.map((event) => event.id), [14, 13, 12, 11, 10, 9, 8]);
        expect(events.map((event) => event.eventType), [
          HistoryEventType.deleted,
          HistoryEventType.renamed,
          HistoryEventType.grabbed,
          HistoryEventType.failed,
          // downloadIgnored
          HistoryEventType.other,
          HistoryEventType.failed,
          HistoryEventType.imported,
        ]);
      });

      test('maps an event as the history does', () async {
        final records = service.list('history_since');

        final event = (await value(
          service.client(_server(records)).eventsSince(since),
        )).last;

        expect(event.id, 8);
        expect(
          event.date,
          DateTime.utc(2026, 11, 26, 13, 57, service == radarr ? 54 : 55),
        );
        expect(event.sourceTitle, records.first['sourceTitle']);
        expect(event.downloadId, records.first['downloadId']);
        expect(
          event.itemRef,
          service == radarr
              ? itemRef(MediaKind.movie, 7)
              : itemRef(MediaKind.episode, 20),
        );
        expect(event.details['fileId'], '1');
      });

      test('keeps no address of a grab', () async {
        final events = await value(
          service
              .client(_server(service.list('history_since')))
              .eventsSince(since),
        );

        final grab = events.singleWhere(
          (event) => event.eventType == HistoryEventType.grabbed,
        );
        expect(grab.details, isNotEmpty);
        expect(
          grab.details.keys,
          isNot(anyElement(anyOf('downloadUrl', 'nzbInfoUrl', 'guid'))),
        );
      });

      test('is empty when nothing happened', () async {
        final server = _server(<Object?>[]);

        expect(await value(service.client(server).eventsSince(since)), isEmpty);
        expect(server.requests, hasLength(1));
      });

      test('cannot understand an event without an id', () async {
        final records = service.list('history_since');
        records[1].remove('id');

        expect(
          await failure(service.client(_server(records)).eventsSince(since)),
          isA<MalformedResponse>(),
        );
      });

      test('cannot understand a page', () async {
        expect(
          await failure(
            service
                .client(_server(service.object('history_activity')))
                .eventsSince(since),
          ),
          isA<MalformedResponse>(),
        );
      });
    });

    group('${service.name} mark as failed', () {
      test('marks the grab', () async {
        final server = only('history/failed/3', const Reply(200, '{}'));

        await value(service.client(server).markFailed(3));

        final request = server.requests.single;
        expect(request.method, HttpMethod.post);
        expect(request.path, 'api/v3/history/failed/3');
        expect(request.query, isEmpty);
        expect(request.body, isNull);
      });

      test('reports an event that is gone', () async {
        final server = only(
          'history/failed/999999',
          Reply.json({'message': 'does not exist'}, status: 404),
        );

        expect(
          await failure(service.client(server).markFailed(999999)),
          isA<NotFound>(),
        );
        expect(server.requests, hasLength(1));
      });
    });
  }
}
