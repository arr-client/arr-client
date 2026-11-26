// What the contract tests share: the two services, their recorded shapes and a
// server that answers as `ServiceHttpClient` of the core would report it.
//
// Fixtures: recorded from a throwaway Radarr 7.0.3.10918 and Sonarr
// 4.0.20.3014 in the dev stack's images and passed through
// tool/sanitize_fixture.dart. health, qualityprofile, queue_empty and
// history_empty are of the fresh servers. The queue and history items were made
// with qBittorrent as download client and releases pushed to the server; an
// import was done by hand. What a test needs beyond them it changes.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servarr/servarr.dart';

import '../allow_list.dart';

const instanceId = 'i1';

/// One service of the family: what its module passes to the shared client.
class Service {
  const Service({
    required this.name,
    required this.version,
    required this.includeUnknown,
    required this.refs,
  });

  final String name;
  final String version;
  final String includeUnknown;
  final ServarrRefs Function(JsonObject record) refs;

  /// A decoded fixture, fresh on each call so that a test may change it.
  Object? fixture(String file) =>
      jsonDecode(File('test/fixtures/$version/$file.json').readAsStringSync());

  JsonObject object(String file) => fixture(file)! as JsonObject;

  List<JsonObject> list(String file) =>
      (fixture(file)! as List<Object?>).cast<JsonObject>();

  /// The records of a paged fixture.
  List<JsonObject> records(String file) =>
      (object(file)['records']! as List<Object?>).cast<JsonObject>();

  ServarrClient client(FakeServer server) => ServarrClient(
    AllowListClient(allowList(includeUnknown), server),
    apiPath: 'api/v3',
    includeUnknownParameter: includeUnknown,
    refs: refs,
  );
}

ItemRef? _ref(MediaKind kind, Object? id) => id is int
    ? ItemRef(instanceId: instanceId, kind: kind, remoteId: id)
    : null;

final radarr = Service(
  name: 'Radarr',
  version: '7.0.3.10918',
  includeUnknown: 'includeUnknownMovieItems',
  refs: (record) =>
      (item: _ref(MediaKind.movie, record['movieId']), parent: null),
);

final sonarr = Service(
  name: 'Sonarr',
  version: '4.0.20.3014',
  includeUnknown: 'includeUnknownSeriesItems',
  refs: (record) => (
    item: _ref(MediaKind.episode, record['episodeId']),
    parent: _ref(MediaKind.series, record['seriesId']),
  ),
);

final services = [radarr, sonarr];

/// What the fake server sends back.
sealed class Answer {
  const Answer();
}

/// An HTTP response.
class Reply extends Answer {
  const Reply(this.status, this.body, {this.type = 'application/json'});

  Reply.json(Object? value, {int status = 200})
    : this(status, jsonEncode(value));

  final int status;
  final String body;
  final String type;
}

/// No response at all.
class NoReply extends Answer {
  const NoReply(this.failure);

  final ServiceFailure failure;
}

/// Answers each request from [handle] and classifies the answer as the core
/// client does: a success status is `Ok` unless it is a web page, anything else
/// is `Err` with the response. It never retries.
class FakeServer implements ServiceHttpClient {
  FakeServer(this.handle);

  /// Answers by path below `api/v3/`; any other path is a 404.
  FakeServer.paths(Map<String, Object?> bodies)
    : this((request) {
        final path = request.path.replaceFirst('api/v3/', '');
        return bodies.containsKey(path)
            ? Reply.json(bodies[path])
            : Reply.json({'message': 'NotFound'}, status: 404);
      });

  /// The same answer to everything.
  FakeServer.always(Answer answer) : this((_) => answer);

  final Answer Function(ServiceRequest request) handle;
  final requests = <ServiceRequest>[];

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    requests.add(request);
    // Guards against a client that never stops asking.
    if (requests.length > 100) throw StateError('Too many requests');
    switch (handle(request)) {
      case NoReply(:final failure):
        return Err(HttpError(failure));
      case Reply(:final status, :final body, :final type):
        final response = ServiceResponse(
          statusCode: status,
          bytes: Uint8List.fromList(utf8.encode(body)),
          headers: {
            'content-type': ['$type; charset=utf-8'],
          },
        );
        final failure = switch (status) {
          >= 200 && < 300 =>
            type == 'text/html' ? const ProxyInterception() : null,
          400 => const Validation([]),
          401 => const AuthFailed(),
          403 => const Forbidden(),
          404 => const NotFound(),
          409 => const Conflict(),
          _ => ServerError(statusCode: status),
        };
        return failure == null
            ? Ok(response)
            : Err(HttpError(failure, response: response));
    }
  }
}

int _number(ServiceRequest request, String name) =>
    int.parse(request.query[name]!.single);

/// A page of [records] as a Servarr `PagingResource`. Past the end the queue
/// answers with its last page instead (`QueueController`); with [clamp] false
/// the page is empty, as history answers.
///
/// [limit] makes the server send fewer records a page than asked for, so that
/// a few records already take several pages.
Reply page(
  ServiceRequest request,
  List<Object?> records, {
  int? limit,
  bool clamp = true,
}) {
  var number = _number(request, 'page');
  final asked = _number(request, 'pageSize');
  final size = limit == null ? asked : min(asked, limit);
  List<Object?> slice() =>
      records.skip((number - 1) * size).take(size).toList();
  if (clamp && slice().isEmpty && number > 1) {
    // The server divides whole numbers before rounding up.
    number = max(records.length ~/ size, 1);
  }
  return Reply.json({
    'page': number,
    'pageSize': size,
    'sortKey': request.query['sortKey']?.single ?? 'timeleft',
    'sortDirection': request.query['sortDirection']?.single ?? 'ascending',
    'totalRecords': records.length,
    'records': slice(),
  });
}

Future<T> value<T>(ServiceResult<T> result) async => switch (await result) {
  Ok(:final value) => value,
  Err(:final error) => fail('Expected success, got ${error.runtimeType}'),
};

Future<ServiceFailure> failure<T>(ServiceResult<T> result) async =>
    switch (await result) {
      Ok() => fail('Expected a failure'),
      Err(:final error) => error,
    };
