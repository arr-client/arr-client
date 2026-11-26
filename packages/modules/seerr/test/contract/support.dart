// What the Seerr contract tests share.
//
// The files under test/fixtures/<version>/ are the answers of throwaway
// servers holding made-up users, requests and issues about public domain and
// long published titles: ghcr.io/seerr-team/seerr:v3.5.2,
// fallenbagel/jellyseerr:2.7.3 and sctx/overseerr:1.35.0. Lists from TMDB were
// trimmed to a few entries. All went through tool/sanitize_fixture.dart.
// Headers are not recorded in files; the cookies used here have the recorded
// shape with made-up values.

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seerr/seerr_module.dart';

import '../allow_list.dart';

/// A product at the version its fixtures were recorded from.
enum Product {
  seerr('Seerr', '3.5.2'),
  jellyseerr('Jellyseerr', '2.7.3'),
  overseerr('Overseerr', '1.35.0');

  const Product(this.label, this.version);

  /// The name a probe reports.
  final String label;
  final String version;
}

/// The permission bits of server/lib/permissions.ts, the same in all three.
abstract final class Bits {
  static const admin = 2;
  static const manageUsers = 8;
  static const manageRequests = 16;
  static const request = 32;
  static const autoApprove = 128;
  static const request4k = 1024;
  static const request4kMovie = 2048;
  static const request4kTv = 4096;
  static const requestAdvanced = 8192;
  static const requestView = 16384;
  static const requestMovie = 262144;
  static const requestTv = 524288;
  static const manageIssues = 1048576;
  static const viewIssues = 2097152;
  static const createIssues = 4194304;
}

/// A recorded body.
String fixture(String name, [Product product = Product.seerr]) =>
    File('test/fixtures/${product.version}/$name.json').readAsStringSync();

/// A recorded JSON object.
Map<String, Object?> recorded(String name, [Product product = Product.seerr]) =>
    jsonDecode(fixture(name, product)) as Map<String, Object?>;

/// The `results` of a recorded page.
List<Map<String, Object?>> results(
  String name, [
  Product product = Product.seerr,
]) => [
  for (final entry in recorded(name, product)['results']! as List<Object?>)
    entry! as Map<String, Object?>,
];

typedef Answer = Result<ServiceResponse, HttpError>;

const jsonType = 'application/json; charset=utf-8';

/// What the servers answer to a request that wants a session or a permission
/// it has not got, and to a wrong API key.
const noPermission =
    '{"status":403,"error":"You do not have permission to access this '
    'endpoint"}';

const csrfRefusal = '{"message":"invalid csrf token"}';

ServiceResponse response(
  int status,
  String body, {
  String? type = jsonType,
  List<String> cookies = const [],
}) => ServiceResponse(
  statusCode: status,
  bytes: utf8.encode(body),
  headers: {
    if (type != null && body.isNotEmpty) 'content-type': [type],
    if (cookies.isNotEmpty) 'set-cookie': cookies,
  },
);

/// [body] with [status], as the core client reports it.
Answer answered(
  int status,
  String body, {
  String? type = jsonType,
  List<String> cookies = const [],
}) {
  final answer = response(status, body, type: type, cookies: cookies);
  if (status < 300) {
    return type != null && type.startsWith('text/html')
        ? Err(HttpError(const ProxyInterception(), response: answer))
        : Ok(answer);
  }
  final failure = switch (status) {
    400 => Validation([
      if (body.startsWith('{'))
        if (jsonDecode(body) case {'message': final String message}) message,
    ]),
    401 => const AuthFailed(),
    403 => const Forbidden(),
    404 => const NotFound(),
    409 => const Conflict(),
    _ => ServerError(statusCode: status),
  };
  return Err(HttpError(failure, response: answer));
}

Answer json(Object? value, {int status = 200}) =>
    answered(status, jsonEncode(value));

Answer ok(String body) => answered(200, body);

/// A failure with no response.
Answer unsent(ServiceFailure failure) => Err(HttpError(failure));

/// The header [name] of [request], whatever its case.
String? header(ServiceRequest request, String name) {
  for (final MapEntry(:key, :value) in request.headers.entries) {
    if (key.toLowerCase() == name.toLowerCase()) return value;
  }
  return null;
}

/// The cookies in a `Cookie` header.
Map<String, String> cookiesOf(String? header) => {
  for (final pair in (header ?? '').split(';'))
    if (pair.contains('='))
      pair.substring(0, pair.indexOf('=')).trim(): pair
          .substring(pair.indexOf('=') + 1)
          .trim(),
};

// The recorded attributes. The cookies are marked Secure whatever the
// transport (research R18).
const csrfSecret = 'zqCsrfSecret';
const csrfToken = 'zqCsrfToken-123_abc';
const secretCookie =
    '_csrf=$csrfSecret; Path=/; HttpOnly; Secure; SameSite=Strict';
const tokenCookie = 'XSRF-TOKEN=$csrfToken; Path=/; Secure; SameSite=Strict';

/// A server that answers by method and path. [on] wins over what a healthy
/// server of [product] answers.
class FakeSeerr implements ServiceHttpClient {
  FakeSeerr({this.product = Product.seerr, this.csrf = false});

  /// Answers every request alike.
  factory FakeSeerr.always(Answer answer) = _Always;

  final Product product;

  /// CSRF protection is on.
  bool csrf;

  /// By `'GET api/v1/...'`.
  final on = <String, Answer>{};

  final requests = <ServiceRequest>[];

  /// Everything that is not a read.
  List<ServiceRequest> get writes => [
    for (final request in requests)
      if (request.method != HttpMethod.get) request,
  ];

  /// The reads of [path].
  List<ServiceRequest> reads(String path) => [
    for (final request in requests)
      if (request.method == HttpMethod.get && request.path == 'api/v1/$path')
        request,
  ];

  /// Answers [route] with [answer] from now on.
  void set(String route, Answer answer) => on[route] = answer;

  @override
  Future<Answer> send(ServiceRequest request) async {
    requests.add(request);
    if (!csrf) return decide(request);
    final cookies = cookiesOf(header(request, 'cookie'));
    if (request.method != HttpMethod.get) {
      final accepted =
          cookies['_csrf'] == csrfSecret &&
          header(request, 'x-xsrf-token') == csrfToken;
      return accepted ? decide(request) : answered(403, csrfRefusal);
    }
    final answer = decide(request);
    final set = [if (cookies['_csrf'] == null) secretCookie, tokenCookie];
    return switch (answer) {
      Ok(:final value) => Ok(
        ServiceResponse(
          statusCode: value.statusCode,
          bytes: value.bytes,
          headers: {...value.headers, 'set-cookie': set},
        ),
      ),
      Err() => answer,
    };
  }

  Answer decide(ServiceRequest request) {
    final route = '${request.method.name.toUpperCase()} ${request.path}';
    if (on[route] case final answer?) return answer;
    final name = switch (route) {
      'GET api/v1/status' => 'status',
      'GET api/v1/settings/public' => 'settings_public_4k_cached',
      'GET api/v1/auth/me' => 'auth_me_admin',
      _ => null,
    };
    return name == null
        ? answered(404, '{"message":"not found"}')
        : ok(fixture(name, product));
  }
}

class _Always extends FakeSeerr {
  _Always(this.answer);

  final Answer answer;

  @override
  Answer decide(ServiceRequest request) => answer;
}

/// `settings/public` of [product] with the given switches.
Map<String, Object?> publicSettings({
  Product product = Product.seerr,
  bool movie4k = false,
  bool series4k = false,
  bool cacheImages = false,
}) => {
  ...recorded('settings_public_4k_cached', product),
  'movie4kEnabled': movie4k,
  'series4kEnabled': series4k,
  'cacheImages': cacheImages,
};

class _FakeArtwork extends Fake implements ArtworkLoader {}

class _FakeNavigator extends Fake implements AppNavigator {}

class _FakeCache extends Fake implements CacheScope {}

class _SilentLogger implements Logger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

Instance instance({
  Product? product,
  String? version,
  AuthKind authKind = AuthKind.apiKey,
  String url = 'http://server.test/seerr',
}) => Instance(
  id: 'i1',
  profileId: 'p1',
  name: 'Requests',
  serviceType: 'seerr',
  url: Uri.parse(url),
  authKind: authKind,
  detectedVersion: version ?? product?.version,
  // What the registry hands a module after a probe.
  lastProbe: product == null
      ? null
      : ProbeSnapshot(
          product: product.label,
          version: version ?? product.version,
          capabilities: const {
            CapabilityKind.discovery,
            CapabilityKind.request,
          },
        ),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// A context whose every request is checked against the allow-list.
InstanceContext context(
  ServiceHttpClient http, {
  Instance? of,
  SessionAuthenticator? session,
}) => InstanceContext(
  instance: of ?? instance(product: Product.seerr),
  http: AllowListClient(allowList, http),
  artwork: _FakeArtwork(),
  navigator: _FakeNavigator(),
  cache: _FakeCache(),
  logger: _SilentLogger(),
  session: session,
);

/// The context of an instance probed as [http]'s product.
InstanceContext contextOf(
  FakeSeerr http, {
  String? version,
  String url = 'http://server.test/seerr',
}) => context(
  http,
  of: instance(product: http.product, version: version, url: url),
);

DiscoveryProvider discovery(FakeSeerr http, {String? version}) => SeerrModule()
    .capability<DiscoveryProvider>(contextOf(http, version: version))!;

RequestProvider requests(
  FakeSeerr http, {
  String url = 'http://server.test/seerr',
}) => SeerrModule().capability<RequestProvider>(contextOf(http, url: url))!;

/// A title to act on.
DiscoveryTitle title({
  int tmdbId = 19,
  int? mediaId = 11,
  DiscoveryMediaType type = DiscoveryMediaType.movie,
}) => DiscoveryTitle(
  tmdbId: tmdbId,
  mediaId: mediaId,
  mediaType: type,
  title: 'A title',
  availability: Availability.unknown,
  availability4k: Availability.unknown,
);

/// The body sent as JSON.
Map<String, Object?> sent(ServiceRequest request) =>
    jsonDecode(jsonEncode((request.body! as JsonBody).value))
        as Map<String, Object?>;

T valueOf<T>(Result<T, ServiceFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => fail('Expected success, got $error'),
};

void expectOk(Result<void, ServiceFailure> result) {
  if (result case Err(:final error)) fail('Expected success, got $error');
}

ServiceFailure failureOf<T>(Result<T, ServiceFailure> result) =>
    switch (result) {
      Ok() => fail('Expected a failure'),
      Err(:final error) => error,
    };
