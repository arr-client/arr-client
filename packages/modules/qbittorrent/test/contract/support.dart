// What the qBittorrent contract tests share.
//
// The files under test/fixtures/<version>/ are the answers of throwaway
// qBittorrent servers holding made-up torrents: 5.3.1 is the dev stack's image,
// 4.4.5 and 5.1.4 are qbittorrentofficial/qbittorrent-nox. All went through
// tool/sanitize_fixture.dart. Headers are not recorded in files; the ones used
// here have the recorded shape with made-up session values.

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';

import '../allow_list.dart';

/// One version of each login behaviour, and the minimum.
const versions = ['4.4.5', '5.1.4', '5.3.1'];

/// A recorded body, without the line end the sanitizer adds.
String fixture(String version, String name) =>
    File('test/fixtures/$version/$name').readAsStringSync().trimRight();

/// A recorded torrent list.
List<Map<String, Object?>> torrents(
  String version, [
  String name = 'torrents_info.json',
]) => [
  for (final entry in jsonDecode(fixture(version, name)) as List<Object?>)
    entry! as Map<String, Object?>,
];

/// The `Set-Cookie` values of an accepted login, by version.
const setCookies = {
  '4.4.5': 'SID=zqSession445; HttpOnly; path=/; SameSite=Strict',
  '5.1.4': 'SID=zqSession514; HttpOnly; SameSite=Strict; path=/',
  '5.3.1':
      'QBT_SID_8080=zqSession531; HttpOnly; SameSite=Lax; '
      'expires=Thu, 26-Nov-2026 14:42:45 GMT; path=/',
};

// As tool/devstack/proxy/login.conf serves it.
const loginPage = '''
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Sign in</title></head>
<body>
<h1>Sign in to continue</h1>
<form method="post" action="/login">
<label>User name <input name="username"></label>
<label>Password <input name="password" type="password"></label>
<button type="submit">Sign in</button>
</form>
</body>
</html>
''';

const textType = 'text/plain; charset=UTF-8';

ServiceResponse response(
  int statusCode,
  String body, {
  String? type = textType,
  List<String> cookies = const [],
}) => ServiceResponse(
  statusCode: statusCode,
  bytes: utf8.encode(body),
  headers: {
    if (type != null && body.isNotEmpty) 'content-type': [type],
    if (cookies.isNotEmpty) 'set-cookie': cookies,
  },
);

typedef Answer = Result<ServiceResponse, HttpError>;

Answer ok(String body, {String? type = textType}) =>
    Ok(response(200, body, type: type));

Answer json(Object? value) => ok(jsonEncode(value), type: 'application/json');

/// A failure as the core client reports it.
Answer error(
  ServiceFailure failure, {
  int? status,
  String body = '',
  String? type = textType,
}) => Err(
  HttpError(
    failure,
    response: status == null ? null : response(status, body, type: type),
  ),
);

/// A server of one version: the reads it answers, by path.
class FakeHttp implements ServiceHttpClient {
  FakeHttp(this.answer);

  /// Answers every request alike.
  FakeHttp.always(Answer answer) : this((_) => answer);

  /// What a healthy server of [version] answers.
  FakeHttp.server(String version, {String? appVersion, Answer? torrentList})
    : this(
        (request) => switch (request.path) {
          'api/v2/app/version' => ok(
            appVersion ?? fixture(version, 'app_version.txt'),
          ),
          'api/v2/app/webapiVersion' => ok(
            fixture(version, 'app_webapi_version.txt'),
          ),
          'api/v2/torrents/info' =>
            torrentList ??
                ok(
                  fixture(version, 'torrents_info.json'),
                  type: 'application/json',
                ),
          _ => error(const NotFound(), status: 404, body: 'Not Found'),
        },
      );

  final Answer Function(ServiceRequest request) answer;
  final requests = <ServiceRequest>[];

  @override
  Future<Answer> send(ServiceRequest request) async {
    requests.add(request);
    return answer(request);
  }
}

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

/// A context whose every request is checked against the allow-list.
InstanceContext context(
  ServiceHttpClient http, {
  AuthKind authKind = AuthKind.userPassword,
  Instance? instance,
  SessionAuthenticator? session,
}) => InstanceContext(
  instance:
      instance ??
      Instance(
        id: 'i1',
        profileId: 'p1',
        name: 'Downloads',
        serviceType: 'qbittorrent',
        url: Uri.parse('http://server.test/qbittorrent'),
        authKind: authKind,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
  http: AllowListClient(allowList, http),
  artwork: _FakeArtwork(),
  navigator: _FakeNavigator(),
  cache: _FakeCache(),
  logger: _SilentLogger(),
  session: session,
);

/// qBittorrent refuses requests that carry these through a rewriting proxy.
void expectNoOrigin(ServiceRequest request) {
  final names = {for (final name in request.headers.keys) name.toLowerCase()};
  expect(names, isNot(contains('origin')), reason: request.path);
  expect(names, isNot(contains('referer')), reason: request.path);
}

T valueOf<T>(Result<T, ServiceFailure> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => fail('Expected success, got $error'),
};

ServiceFailure failureOf<T>(Result<T, ServiceFailure> result) =>
    switch (result) {
      Ok(:final value) => fail('Expected a failure, got $value'),
      Err(:final error) => error,
    };

/// A refusal that says what else may have caused it (upstream-apis.md).
final Matcher isAuthFailedWithHint = isA<AuthFailed>().having(
  (failure) => failure.hint,
  'hint',
  isNotNull,
);

/// What a bare 401 may be reported as: a rejected host name looks the same as
/// rejected credentials.
final Matcher isUnauthorized = anyOf(isA<HostRejected>(), isAuthFailedWithHint);
