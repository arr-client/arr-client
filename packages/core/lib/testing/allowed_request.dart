import '../src/network/http_method.dart';
import '../src/network/service_request.dart';
import 'body_rule.dart';
import 'param_rule.dart';

/// The classes of contracts/upstream-apis.md.
enum RequestClass {
  /// R: reads.
  read,

  /// W: changes server data.
  write,

  /// A: authentication or session.
  authentication,
}

/// One request a module may make.
///
/// The path is written as `ServiceRequest.path` is, from the instance's address:
/// `api/v3/movie`. It is matched whole, segment by segment and with case. A
/// segment of the pattern is one of:
///
/// * a literal, such as `movie`;
/// * a name in braces, such as `{id}`, which matches a number only, so that
///   `queue/{id}` does not also permit `queue/bulk`;
/// * alternatives in braces, such as `{approve|decline}`;
/// * `**`, last and in a read only, for one or more further segments.
///
/// A request path may use only letters, digits and `-._~`, and no segment of
/// it may be empty or end in a dot. Anything else, such as a percent escape, is
/// refused whatever the pattern, because a server could read it as another
/// path.
///
/// A query parameter that [query] does not name is refused, and so is a body
/// that [body] does not describe.
final class AllowedRequest {
  /// A read, which is always a GET without a body.
  AllowedRequest.read(String path, {Map<String, ParamRule> query = const {}})
    : this._(
        RequestClass.read,
        HttpMethod.get,
        path,
        query,
        const BodyRule.none(),
      );

  /// A change of server data. Some services make one with a GET.
  AllowedRequest.write(
    HttpMethod method,
    String path, {
    Map<String, ParamRule> query = const {},
    BodyRule body = const BodyRule.none(),
  }) : this._(RequestClass.write, method, path, query, body);

  /// A login, logout or other session request.
  AllowedRequest.authentication(
    HttpMethod method,
    String path, {
    Map<String, ParamRule> query = const {},
    BodyRule body = const BodyRule.none(),
  }) : this._(RequestClass.authentication, method, path, query, body);

  AllowedRequest._(
    this.requestClass,
    this.method,
    this.path,
    Map<String, ParamRule> query,
    this.body,
  ) : query = Map.unmodifiable(query),
      _segments = path.split('/') {
    for (final (index, segment) in _segments.indexed) {
      final valid = segment == '**'
          ? requestClass == RequestClass.read &&
                index > 0 &&
                index == _segments.length - 1
          : _placeholder.hasMatch(segment) ||
                (_alternatives(segment)?.every(_isPlain) ?? _isPlain(segment));
      if (!valid) throw ArgumentError.value(path, 'path', 'Not a path pattern');
    }
  }

  static final _plain = RegExp(r'^[A-Za-z0-9._~-]+$');
  static final _number = RegExp(r'^[0-9]+$');
  static final _placeholder = RegExp(r'^\{[A-Za-z]+\}$');

  /// R, W or A.
  final RequestClass requestClass;

  /// The only method permitted.
  final HttpMethod method;

  /// The path pattern.
  final String path;

  /// The query parameters permitted, by exact name.
  final Map<String, ParamRule> query;

  /// The body permitted.
  final BodyRule body;

  final List<String> _segments;

  /// Whether this entry permits [request]. Headers are checked by `AllowList`.
  bool permits(ServiceRequest request) =>
      request.method == method &&
      _matchesPath(request.path) &&
      ParamRule.permitsAll(query, request.query) &&
      body.permits(request.body);

  bool _matchesPath(String requested) {
    final actual = requested.split('/');
    if (!actual.every(_isPlain)) return false;
    final open = _segments.last == '**';
    final fixed = open ? _segments.length - 1 : _segments.length;
    if (open ? actual.length <= fixed : actual.length != fixed) return false;
    for (var i = 0; i < fixed; i++) {
      final pattern = _segments[i];
      final matches = _placeholder.hasMatch(pattern)
          ? _number.hasMatch(actual[i])
          : _alternatives(pattern)?.contains(actual[i]) ?? pattern == actual[i];
      if (!matches) return false;
    }
    return true;
  }

  // A trailing dot covers `.` and `..`; some servers also drop one.
  static bool _isPlain(String segment) =>
      _plain.hasMatch(segment) && !segment.endsWith('.');

  static List<String>? _alternatives(String segment) =>
      segment.startsWith('{') && segment.endsWith('}') && segment.contains('|')
      ? segment.substring(1, segment.length - 1).split('|')
      : null;
}
