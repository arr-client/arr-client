// What the release, command and edit tests (T085) share, and the API they expect
// of `package:servarr/servarr.dart` (T088). The records are those of
// `package:core`.
//
//   // Further members of ServarrClient. `path` is below the API path.
//
//   /// The releases the indexers have for [target], the query that names it,
//   /// such as `{'movieId': 1}`, in the server's order. Without a target the
//   /// server answers with its RSS feeds, so an empty one sends nothing and
//   /// fails with `Validation`.
//   ServiceResult<List<Release>> releases(Map<String, int> target);
//
//   /// Has the server download [release], rejected or not.
//   ServiceResult<void> grab(Release release);
//
//   /// Starts the command [name] on [target], the fields that say what it
//   /// acts on. Some commands act on the whole library without them, so an
//   /// empty target, or an empty list in it, sends nothing and fails with
//   /// `Validation`.
//   ServiceResult<Command> startCommand(String name, JsonObject target);
//
//   /// Reads the record at [path], lets [change] alter it and writes the whole
//   /// of it back to [path] (research R13). A `FormatException` of [change],
//   /// for a record it cannot understand, is `MalformedResponse`, and nothing
//   /// is written.
//   ServiceResult<void> update(
//     String path,
//     void Function(JsonObject record) change,
//   );
//
//   /// [update] with the fields set in [changes]. An `unknown` series type or
//   /// minimum availability is not a value to write. With nothing to write,
//   /// nothing is sent.
//   ServiceResult<void> edit(String path, ItemEdit changes);
//
//   /// Changes the items [ids] through the editor at [path], which names them
//   /// [idsField]. With no ids or nothing to change, nothing is sent.
//   ServiceResult<void> bulkEdit(
//     String path, {
//     required String idsField,
//     required List<int> ids,
//     required BulkEdit changes,
//   });
//
// The constructor of ServarrClient does not change.
//
// As in activity_support.dart, a write is sent once, a failure of `http.send`
// is returned unchanged, and what a successful write answers is not read, but
// for `startCommand`.
//
// Fixtures (`manage_*`): recorded from a further throwaway Radarr 7.0.3.10918
// and Sonarr 4.0.20.3014, with a made-up Torznab and Newznab indexer serving
// the releases, qBittorrent as download client and a custom format that scores
// `PROPER`, and passed through tool/sanitize_fixture.dart. manage_item is the
// movie or series as read before it was edited. The answers to a grab, an edit
// and the editor are not read, so the tests give the failures as they were
// seen, without their stack traces.

import 'package:core/core.dart';

import 'support.dart';

/// A server that answers each method and path below `api/v3/`, such as
/// `GET movie/1`, with its entry of [replies], and anything else with a 404.
FakeServer routes(Map<String, Answer> replies) => FakeServer((request) {
  final method = request.method.name.toUpperCase();
  final path = request.path.replaceFirst('api/v3/', '');
  return replies['$method $path'] ?? const Reply(404, '');
});

/// What [request] sends, as the server would read it.
Object? sentBody(ServiceRequest request) => (request.body! as JsonBody).value;

/// A failed answer with the server's message.
Reply refusal(int status, String message) =>
    Reply.json({'message': message}, status: status);

/// The failures every request can meet.
final transportFailures = <String, (Answer, Type)>{
  'an unreachable server': (const NoReply(Unreachable()), Unreachable),
  'a rejected key': (const Reply(401, ''), AuthFailed),
  'a refusal': (const Reply(403, ''), Forbidden),
  'something gone': (const Reply(404, ''), NotFound),
  'a conflict': (const Reply(409, ''), Conflict),
  'rejected values': (const Reply(400, '[]'), Validation),
  'a server error': (refusal(500, 'Example'), ServerError),
  'a login page': (
    const Reply(
      200,
      '<!doctype html><title>Sign in</title>',
      type: 'text/html',
    ),
    ProxyInterception,
  ),
};

/// The failures of a write: those, and one that leaves it open whether the
/// server has the change.
final writeFailures = <String, (Answer, Type)>{
  ...transportFailures,
  'an unknown outcome': (const NoReply(OutcomeUnknown()), OutcomeUnknown),
};
