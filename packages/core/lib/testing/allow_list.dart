/// The request allow-list harness (FR-019): test support for modules.
///
/// A module writes the requests it may make in `test/allow_list.dart`, from
/// contracts/upstream-apis.md, and runs its adapter tests through an
/// [AllowListClient]. The core holds only the checking logic.
///
/// ```dart
/// final allowList = AllowList([
///   AllowedRequest.read('api/v3/movie/{id}'),
///   AllowedRequest.write(
///     HttpMethod.post,
///     'api/v3/command',
///     body: const BodyRule.jsonObject({
///       'name': ParamRule.only({'MoviesSearch'}),
///     }),
///   ),
/// ]);
///
/// final client = AllowListClient(allowList, fakeClient);
/// ```
library;

import '../src/network/service_request.dart';
import 'allowed_request.dart';

export 'allow_list_client.dart';
export 'allow_list_violation.dart';
export 'allowed_request.dart';
export 'body_rule.dart';
export 'param_rule.dart';

/// Every request a module may make. What no entry permits is refused.
final class AllowList {
  /// Creates an [AllowList].
  AllowList(Iterable<AllowedRequest> entries)
    : entries = List.unmodifiable(entries);

  /// The permitted requests.
  final List<AllowedRequest> entries;

  // Headers with which a server or proxy can be told to treat a request as
  // another method, path or body type than the one checked here.
  static const _forbiddenHeaders = {
    'content-type',
    'host',
    'x-http-method',
    'x-http-method-override',
    'x-method-override',
    'x-original-url',
    'x-rewrite-url',
  };

  /// Whether some entry permits [request].
  bool permits(ServiceRequest request) =>
      !request.headers.keys.any(
        (name) => _forbiddenHeaders.contains(
          name.trim().toLowerCase().replaceAll('_', '-'),
        ),
      ) &&
      entries.any((entry) => entry.permits(request));
}
