import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeClient implements ServiceHttpClient {
  final sent = <ServiceRequest>[];

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    sent.add(request);
    return Ok(ServiceResponse(statusCode: 200, bytes: Uint8List(0)));
  }
}

final class _Command {
  const _Command(this.name);

  final String name;

  Map<String, Object?> toJson() => {'name': name};
}

ServiceRequest _get(
  String path, {
  Map<String, List<String>> query = const {},
  Map<String, String> headers = const {},
  RequestBody? body,
}) => ServiceRequest(
  HttpMethod.get,
  path,
  query: query,
  headers: headers,
  body: body,
);

final _list = AllowList([
  AllowedRequest.read('api/v3/movie'),
  AllowedRequest.read('api/v3/movie/{id}'),
  AllowedRequest.read(
    'api/v3/queue',
    query: {
      'page': const ParamRule.any(),
      'includeUnknownMovieItems': const ParamRule.only({'true'}),
    },
  ),
  AllowedRequest.read('imageproxy/**'),
  AllowedRequest.write(HttpMethod.delete, 'api/v3/queue/{id}'),
  AllowedRequest.write(
    HttpMethod.post,
    'api/v1/request/{id}/{approve|decline}',
  ),
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/command',
    body: const BodyRule.jsonObject({
      'name': ParamRule.only({'MoviesSearch', 'RefreshMovie'}),
    }),
  ),
  AllowedRequest.write(
    HttpMethod.post,
    'api/v3/manualimport',
    body: const BodyRule.json(),
  ),
  // A service that chooses the operation by parameter.
  AllowedRequest.read(
    'api',
    query: {
      'mode': const ParamRule.only({'queue'}),
    },
  ),
  AllowedRequest.write(
    HttpMethod.get,
    'api',
    query: {
      'mode': const ParamRule.only({'queue'}),
      'name': const ParamRule.only({'delete'}),
      'value': const ParamRule.any(required: true),
    },
  ),
  AllowedRequest.authentication(
    HttpMethod.post,
    'api/v2/auth/login',
    body: const BodyRule.form({
      'username': ParamRule.any(required: true),
      'password': ParamRule.any(required: true),
    }),
  ),
]);

void main() {
  group('permits', () {
    final requests = {
      'a listed path': _get('api/v3/movie'),
      'a number': _get('api/v3/movie/17'),
      'a declared and a required parameter': _get(
        'api/v3/queue',
        query: {
          'page': ['2'],
          'includeUnknownMovieItems': ['true'],
        },
      ),
      'further segments': _get('imageproxy/tmdb/t/p/w300/a-b_c.jpg'),
      'an alternative': ServiceRequest(
        HttpMethod.post,
        'api/v1/request/3/decline',
      ),
      'a listed command': ServiceRequest(
        HttpMethod.post,
        'api/v3/command',
        body: const JsonBody({
          'name': 'MoviesSearch',
          'movieIds': [1],
        }),
      ),
      'what toJson gives': ServiceRequest(
        HttpMethod.post,
        'api/v3/command',
        body: const JsonBody(_Command('RefreshMovie')),
      ),
      'a JSON list': ServiceRequest(
        HttpMethod.post,
        'api/v3/manualimport',
        body: const JsonBody([1]),
      ),
      'a read chosen by parameter': _get(
        'api',
        query: {
          'mode': ['queue'],
        },
      ),
      'a write chosen by parameter': _get(
        'api',
        query: {
          'mode': ['queue'],
          'name': ['delete'],
          'value': ['abc'],
        },
      ),
      'a login form': ServiceRequest(
        HttpMethod.post,
        'api/v2/auth/login',
        body: const FormBody({'username': 'a', 'password': 'b'}),
      ),
      'an ordinary header': _get(
        'api/v3/movie',
        headers: {'Accept': 'application/json'},
      ),
    };
    for (final MapEntry(:key, :value) in requests.entries) {
      test(key, () => expect(_list.permits(value), isTrue));
    }
  });

  group('refuses the path', () {
    for (final path in [
      '',
      'api/v3/config/host',
      'api/v3/movie/',
      'api/v3//movie',
      'api/v3/movie/17/extra',
      'api/v3',
      'api/v3/Movie',
      'API/v3/movie',
      'api/v3/movie.',
      'api/v3/movie/lookup',
      'api/v3/movie/-1',
      'api/v3/movie/1.5',
      'api/v3/movie/1;x',
      'api/v3/movie/1\n',
      'api/v3/movie\u0000',
      'api/v3/movie ',
      'api/v3/movie/１',
      'api/v3/movie%2F17',
      'api/v3/%6Dovie',
      'imageproxy',
      'imageproxy/',
      'imageproxy/%2e%2e/api/v1/settings',
      'imageproxy/%252e%252e/api',
      'imageproxy/..%2fapi',
      'imageproxy/..;/api',
      'imageproxy/.../api',
      'imageproxy/a//b',
      'imageproxy/．．/api',
    ]) {
      test('${Uri.encodeComponent(path)} as sent', () {
        expect(_list.permits(_get(path)), isFalse);
      });
    }

    test('that ServiceRequest already refuses to build', () {
      for (final path in [
        'imageproxy/../api',
        'api/v3/movie?x=1',
        r'api\v3\movie',
        '/api/v3/movie',
      ]) {
        expect(() => _get(path), throwsArgumentError);
      }
    });
  });

  group('refuses', () {
    ServiceRequest command(Object? value) => ServiceRequest(
      HttpMethod.post,
      'api/v3/command',
      body: JsonBody(value),
    );

    final requests = {
      for (final method in HttpMethod.values)
        if (method != HttpMethod.get)
          '${method.name} on a read': ServiceRequest(method, 'api/v3/movie'),
      'a GET on a write': _get('api/v3/queue/1'),
      'a word where a number is listed': ServiceRequest(
        HttpMethod.delete,
        'api/v3/queue/bulk',
      ),
      'another alternative': ServiceRequest(
        HttpMethod.post,
        'api/v1/request/3/retry',
      ),
      'an unlisted parameter': _get(
        'api/v3/movie',
        query: {
          '_method': ['DELETE'],
        },
      ),
      'an unlisted parameter with no value': _get(
        'api/v3/movie',
        query: {'x': []},
      ),
      'a missing required parameter': _get('api/v3/queue'),
      'a required parameter with no value': _get(
        'api/v3/queue',
        query: {'includeUnknownMovieItems': []},
      ),
      'another value': _get(
        'api',
        query: {
          'mode': ['config'],
        },
      ),
      'a value in another case': _get(
        'api',
        query: {
          'mode': ['Queue'],
        },
      ),
      'a name in another case': _get(
        'api',
        query: {
          'Mode': ['queue'],
        },
      ),
      'a restricted parameter twice': _get(
        'api',
        query: {
          'mode': ['queue', 'config'],
        },
      ),
      'a write parameter without its companion': _get(
        'api',
        query: {
          'mode': ['queue'],
          'name': ['delete'],
        },
      ),
      'a body on a read': _get(
        'api',
        query: {
          'mode': ['queue'],
        },
        body: const FormBody({'mode': 'config'}),
      ),
      'a missing body': ServiceRequest(HttpMethod.post, 'api/v3/command'),
      'another command': command({'name': 'Backup'}),
      'no command name': command(<String, Object?>{}),
      'a null command name': command({'name': null}),
      'a list of command names': command({
        'name': ['MoviesSearch'],
      }),
      'a second name in another case': command({
        'name': 'MoviesSearch',
        'Name': 'Backup',
      }),
      'a command list': command([
        {'name': 'MoviesSearch'},
      ]),
      'a body that cannot be sent': command({'name': Object()}),
      'a form for JSON': ServiceRequest(
        HttpMethod.post,
        'api/v3/command',
        body: const FormBody({'name': 'MoviesSearch'}),
      ),
      'an unlisted form field': ServiceRequest(
        HttpMethod.post,
        'api/v2/auth/login',
        body: const FormBody({'username': 'a', 'password': 'b', 'x': 'y'}),
      ),
      for (final header in [
        'X-HTTP-Method-Override',
        'x-http-method',
        'X-Method-Override',
        'X_HTTP_Method_Override',
        'X-Original-URL',
        'X-Rewrite-URL',
        'Host',
        'Content-Type',
      ])
        'the header $header': _get('api/v3/movie', headers: {header: 'x'}),
    };
    for (final MapEntry(:key, :value) in requests.entries) {
      test(key, () => expect(_list.permits(value), isFalse));
    }

    test('everything when the list is empty', () {
      expect(AllowList([]).permits(_get('api/v3/movie')), isFalse);
    });
  });

  test('a closed JSON object has no field beside the listed ones', () {
    final list = AllowList([
      AllowedRequest.write(
        HttpMethod.post,
        'api/v3/release',
        body: const BodyRule.jsonObject({
          'guid': ParamRule.nonEmpty(),
        }, closed: true),
      ),
    ]);
    ServiceRequest grab(Object? body) =>
        ServiceRequest(HttpMethod.post, 'api/v3/release', body: JsonBody(body));

    expect(list.permits(grab({'guid': 'a'})), isTrue);
    expect(list.permits(grab({'guid': 'a', 'shouldOverride': true})), isFalse);
    expect(list.permits(grab({'guid': 'a', 'Guid': 'b'})), isFalse);
    expect(list.permits(grab(<String, Object?>{})), isFalse);
  });

  group('a value that must not be empty', () {
    final list = AllowList([
      AllowedRequest.read(
        'api/v3/release',
        query: {'movieId': const ParamRule.nonEmpty()},
      ),
      AllowedRequest.write(
        HttpMethod.post,
        'api/v3/command',
        body: const BodyRule.jsonObject({'movieIds': ParamRule.nonEmpty()}),
      ),
      AllowedRequest.authentication(
        HttpMethod.post,
        'api/v2/auth/login',
        body: const BodyRule.form({'username': ParamRule.nonEmpty()}),
      ),
    ]);
    ServiceRequest read(List<String> values) =>
        _get('api/v3/release', query: {'movieId': values});
    ServiceRequest command(Object? value) => ServiceRequest(
      HttpMethod.post,
      'api/v3/command',
      body: JsonBody({'movieIds': value}),
    );
    ServiceRequest login(String username) => ServiceRequest(
      HttpMethod.post,
      'api/v2/auth/login',
      body: FormBody({'username': username}),
    );

    final filled = {
      'a parameter': read(['1']),
      'a repeated parameter': read(['1', '2']),
      'a number': command(0),
      'a string': command('1'),
      'a list': command([1]),
      'an object': command({'id': 1}),
      'a form field': login('a'),
    };
    for (final MapEntry(:key, :value) in filled.entries) {
      test('permits $key', () => expect(list.permits(value), isTrue));
    }

    final empty = {
      'a missing parameter': _get('api/v3/release'),
      'an empty parameter': read(['']),
      'a blank parameter': read([' ']),
      'a repeated parameter, once empty': read(['', '1']),
      'a missing field': ServiceRequest(
        HttpMethod.post,
        'api/v3/command',
        body: const JsonBody(<String, Object?>{}),
      ),
      'null': command(null),
      'an empty string': command(''),
      'an empty list': command(<Object?>[]),
      'a list of null': command([null]),
      'a list of an empty string': command(['']),
      'an empty object': command(<String, Object?>{}),
      'an empty form field': login(''),
    };
    for (final MapEntry(:key, :value) in empty.entries) {
      test('refuses $key', () => expect(list.permits(value), isFalse));
    }
  });

  group('rejects the pattern', () {
    for (final path in [
      '',
      '/api',
      'api/',
      'api//a',
      'api/../a',
      'api?x=1',
      'api/%2e',
      'api/*',
      'api/{}',
      'api/{a|}',
      'api/{a|..}',
      '**',
      'api/**/a',
    ]) {
      test('"$path"', () {
        expect(() => AllowedRequest.read(path), throwsArgumentError);
      });
    }

    test('with an open end outside a read', () {
      expect(
        () => AllowedRequest.write(HttpMethod.delete, 'api/**'),
        throwsArgumentError,
      );
    });
  });

  group('AllowListClient', () {
    late _FakeClient inner;
    late List<Object> reported;
    late AllowListClient client;

    setUp(() {
      inner = _FakeClient();
      reported = [];
      // Its own zone, so that the violations expected here do not fail us.
      runZonedGuarded(
        () => client = AllowListClient(_list, inner),
        (error, stackTrace) => reported.add(error),
      );
    });

    test('passes on a listed request and its answer', () async {
      final request = _get('api/v3/movie');

      final result = await client.send(request);

      expect(result, isA<Ok<ServiceResponse, HttpError>>());
      expect(inner.sent, [request]);
      expect(reported, isEmpty);
    });

    test('keeps an unlisted request back and fails', () async {
      await expectLater(
        client.send(_get('api/v3/config/host')),
        throwsA(isA<AllowListViolation>()),
      );

      expect(inner.sent, isEmpty);
      expect(reported, [isA<AllowListViolation>()]);
    });

    test('reports a violation the caller swallows', () async {
      await client
          .send(_get('api/v3/config/host'))
          .then<void>((_) {}, onError: (Object _) {});

      expect(reported, [isA<AllowListViolation>()]);
    });

    test('names the request without its values', () {
      final violation = AllowListViolation(
        ServiceRequest(
          HttpMethod.post,
          'api/v3/config',
          query: {
            'apikey': ['secret1'],
          },
          headers: {'Cookie': 'secret2'},
          body: const FormBody({'password': 'secret3'}),
        ),
      );

      expect('$violation', contains('POST "api/v3/config"'));
      expect('$violation', isNot(contains('secret')));
    });
  });
}
