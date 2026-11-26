// A Radarr that can also be searched and added to, for the lookup and add tests.
//
// The lookup_*.json and add_*.json recordings are from a throwaway Radarr
// 7.0.3.10918 and went through tool/sanitize_fixture.dart:
//
//   lookup_term      two results: movie 1, in the library, and one that is not,
//                    with no pictures, year or IMDb id
//   lookup_new       `tmdb:10378` before it was added; no `id` at all
//   lookup_existing  `tmdb:10378` once it was in the library
//   add_movie        the answer to adding it
//   add_exists       the 400 for adding it again
//   add_invalid      the 400 for a quality profile that does not exist
//
// Sanitizing replaced the `/MediaCoverProxy/...` address of lookup_new's
// pictures, so the tests that need one set it in code.

import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radarr/radarr_module.dart';

import 'library_support.dart';

/// The movie of lookup_new, lookup_existing and add_movie.
const bunnyTmdbId = 10378;

const lookupPath = 'api/v3/movie/lookup';
const addPath = 'api/v3/movie';

/// A second root folder beside the recorded one, which has id 1.
const otherFolder = <String, Object?>{
  'id': 2,
  'path': '/redacted/other',
  'accessible': true,
  'freeSpace': 1000,
  'unmappedFolders': <Object>[],
};

ServiceResponse _jsonResponse(int status, String body) => ServiceResponse(
  statusCode: status,
  bytes: utf8.encode(body),
  headers: const {
    'content-type': ['application/json; charset=utf-8'],
  },
);

/// What the core client returns for a 400 with [body]: [Validation] with the
/// server's messages, and the response.
Result<ServiceResponse, HttpError> rejected(Object? body) => Err(
  HttpError(
    Validation([
      if (body is List<Object?>)
        for (final entry in body)
          if (entry case {'errorMessage': final String message}) message,
    ]),
    response: _jsonResponse(400, jsonEncode(body)),
  ),
);

/// [FakeRadarr] with `GET movie/lookup`, `GET rootfolder` and `POST movie`.
class LookupRadarr extends FakeRadarr {
  /// The results of `GET movie/lookup` by term. A term not here, other than
  /// `tmdb:10378`, finds nothing.
  final found = <String, List<Map<String, Object?>>>{
    'big buck bunny': records(fixture('lookup_term')),
    'bunny': records(fixture('lookup_new')),
  };

  /// The TMDB ids that `POST movie` refuses as already added, and that decide
  /// how `tmdb:10378` is found. Adding puts one here.
  final held = <int>{};

  /// The root folders.
  List<Map<String, Object?>> folders = [
    ...records(fixture('rootfolder')),
    {...otherFolder},
  ];

  /// Answers `POST movie` instead.
  Result<ServiceResponse, HttpError>? addAnswer;

  /// The bodies of `POST movie`, as they went over the wire.
  final posted = <Map<String, Object?>>[];

  /// The terms that were looked up.
  List<String> get terms => [
    for (final request in requests)
      if (request.path == lookupPath) request.query['term']!.single,
  ];

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    final answer = switch ((request.method, request.path)) {
      (HttpMethod.post, addPath) => () => _add(request),
      (HttpMethod.get, lookupPath) => () => jsonAnswer(
        _find(request.query['term']!.single),
      ),
      (HttpMethod.get, 'api/v3/rootfolder') => () => jsonAnswer(folders),
      _ => null,
    };
    if (answer == null) return super.send(request);
    requests.add(request);
    return down ?? answers[request.path] ?? answer();
  }

  List<Map<String, Object?>> _find(String term) =>
      found[term] ??
      (term == 'tmdb:$bunnyTmdbId'
          ? records(
              fixture(
                held.contains(bunnyTmdbId) ? 'lookup_existing' : 'lookup_new',
              ),
            )
          : []);

  Result<ServiceResponse, HttpError> _add(ServiceRequest request) {
    // Encoded as the client does, so that what cannot be sent fails here.
    final body = jsonDecode(
      jsonEncode((request.body! as JsonBody).value),
    ) as Map<String, Object?>;
    posted.add(body);
    if (addAnswer case final answer?) return answer;
    if (!held.add(body['tmdbId']! as int)) {
      return rejected(fixture('add_exists'));
    }
    return Ok(_jsonResponse(201, jsonEncode(fixture('add_movie'))));
  }
}

/// A [Harness] whose server is a [LookupRadarr].
class LookupHarness extends Harness {
  LookupHarness() : super(LookupRadarr());

  LookupRadarr get radarr => server as LookupRadarr;

  LookupProvider get lookup =>
      RadarrModule().capability<LookupProvider>(context) ??
      (throw TestFailure('Radarr has no LookupProvider'));
}
