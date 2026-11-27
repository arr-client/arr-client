// The discover, title, request and quota screens (spec story 9), as the app
// builds them from the module's routes, over recorded answers. The allow-list
// refuses any request Seerr is not meant to get.

import 'dart:async';

import 'package:core/core.dart';
import 'package:core/testing/allow_list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:seerr/seerr_module.dart';
import 'package:ui/ui.dart';

import '../allow_list.dart';
import '../contract/support.dart';

/// Holds a request in [held] until its completer is.
class _Server extends FakeSeerr {
  final held = <String, Completer<void>>{};

  @override
  Future<Answer> send(ServiceRequest request) async {
    final answer = await super.send(request);
    await held['${request.method.name.toUpperCase()} ${request.path}']?.future;
    return answer;
  }
}

class _NoArtwork implements ArtworkLoader {
  @override
  ImageProvider<Object>? image(MediaImage image) => null;
}

class _Navigator extends Fake implements AppNavigator {}

class _Cache extends Fake implements CacheScope {}

class _Logger implements Logger {
  @override
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {}
}

/// A movie nobody has asked for.
const _movie = 'seerr/titles/movie/19';
const _series = 'seerr/titles/series/1100';

/// A member who may request movies and series, but nothing in 4K.
const _member = 'auth_me_member';

Map<String, Object?> _results(List<(int, String, int?)> titles) => {
  'page': 1,
  'totalPages': 2,
  'results': [
    for (final (id, name, status) in titles)
      {
        'id': id,
        'mediaType': 'movie',
        'title': name,
        'releaseDate': '1968-10-04',
        if (status != null)
          'mediaInfo': {'id': id, 'status': status, 'status4k': 1},
      },
  ],
};

Map<String, Object?> _movieTitle({
  int? status,
  List<Object?> requests = const [],
}) => {
  'id': 19,
  'title': 'Metropolis',
  'releaseDate': '1927-02-06',
  if (status != null)
    'mediaInfo': {
      'id': 4,
      'status': status,
      'status4k': 1,
      'requests': requests,
    },
};

_Server _server({String me = _member}) => _Server()
  ..set('GET api/v1/auth/me', ok(fixture(me)))
  ..set('GET api/v1/user/2/quota', ok(fixture('quota_used')))
  ..set('GET api/v1/user/1/quota', ok(fixture('quota_used')))
  ..set(
    'GET api/v1/discover/trending',
    json(_results([(19, 'Metropolis', null), (20, 'Nosferatu', 5)])),
  )
  ..set('GET api/v1/movie/19', json(_movieTitle()))
  ..set(
    'GET api/v1/tv/1100',
    json({...recorded('tv'), 'name': 'A series', 'mediaInfo': null}),
  )
  ..set('POST api/v1/request', answered(201, fixture('request_created_movie')));

/// As saved after a probe that found [permissions].
Instance _instance(Set<ServicePermission> permissions) {
  final saved = instance(product: Product.seerr);
  return Instance(
    id: saved.id,
    profileId: saved.profileId,
    name: saved.name,
    serviceType: saved.serviceType,
    url: saved.url,
    authKind: saved.authKind,
    lastProbe: ProbeSnapshot(
      product: Product.seerr.label,
      version: Product.seerr.version,
      capabilities: saved.lastProbe!.capabilities,
      permissions: permissions,
    ),
    createdAt: saved.createdAt,
    updatedAt: saved.updatedAt,
  );
}

Future<GoRouter> _open(
  WidgetTester tester,
  FakeSeerr server, {
  String at = 'seerr/discover',
  Size size = const Size(400, 2000),
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Set<ServicePermission> permissions = const {ServicePermission.requestMovies},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final instanceContext = InstanceContext(
    instance: _instance(permissions),
    http: AllowListClient(allowList, server),
    artwork: _NoArtwork(),
    navigator: _Navigator(),
    cache: _Cache(),
    logger: _Logger(),
  );
  final module = SeerrModule();
  final router = GoRouter(
    initialLocation: '/instances/i1/$at',
    routes: [
      for (final screen in module.routes())
        GoRoute(
          path: '/instances/:instanceId/${screen.path}',
          builder: (context, state) => screen.builder(
            context,
            instanceContext,
            {...state.pathParameters, ...state.uri.queryParameters},
          ),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        theme: brightness == Brightness.light
            ? ArrTheme.light()
            : ArrTheme.dark(),
        localizationsDelegates: const [
          SeerrLocalizations.delegate,
          ...uiLocalizationsDelegates,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(_button(label)).onPressed != null;

void main() {
  group('discover', () {
    testWidgets('lists titles with their availability', (tester) async {
      await _open(tester, _server());

      expect(find.text('Metropolis'), findsOneWidget);
      expect(find.text('Movie · 1968'), findsNWidgets(2));
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      // Nothing is said of 4K where the server says nothing.
      expect(find.textContaining('4K'), findsNothing);
    });

    testWidgets('browses another list and searches', (tester) async {
      final server = _server()
        ..set(
          'GET api/v1/discover/movies/upcoming',
          json(_results([(21, 'Soon', 2)])),
        )
        ..set('GET api/v1/search', json(_results([(22, 'Found', 3)])));
      await _open(tester, server);

      await tester.ensureVisible(find.text('Upcoming movies'));
      await _tap(tester, find.text('Upcoming movies'));
      expect(find.text('Soon'), findsOneWidget);
      expect(find.text('Waiting for approval'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a term');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(server.reads('search').single.query['query'], ['a term']);
      expect(find.text('Found'), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Soon'), findsOneWidget);
    });

    testWidgets('reads the next page when asked', (tester) async {
      final server = _server();
      await _open(tester, server);
      server.set(
        'GET api/v1/discover/trending',
        json({
          ..._results([(20, 'Nosferatu', 5), (23, 'Later', null)]),
          'page': 2,
        }),
      );

      await _tap(tester, find.text('Show more'));

      expect(server.reads('discover/trending').last.query['page'], ['2']);
      // The title on both pages is listed once.
      expect(find.text('Nosferatu'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets('keeps what it has when reading again fails', (tester) async {
      final server = _server();
      await _open(tester, server);
      server.set('GET api/v1/discover/trending', unsent(const Unreachable()));

      await _tap(tester, find.byTooltip('Refresh'));

      expect(find.text('Metropolis'), findsOneWidget);
      expect(find.byType(StaleNotice), findsOneWidget);
    });

    testWidgets('says why there is nothing', (tester) async {
      final server = _server()
        ..set('GET api/v1/discover/trending', unsent(const Unreachable()));

      await _open(tester, server);

      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('title', () {
    testWidgets('opens from the list and offers what is permitted', (
      tester,
    ) async {
      await _open(tester, _server());

      await _tap(tester, find.text('Metropolis'));

      expect(find.text('Movie · 1927'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(_button('Request'), findsOneWidget);
      expect(find.text('Request in 4K'), findsNothing);
    });

    testWidgets('tells the list what it has read', (tester) async {
      final server = _server()
        ..set(
          'GET api/v1/movie/19',
          json(
            _movieTitle(
              status: 2,
              requests: [
                {'id': 1, 'status': 1, 'is4k': false},
              ],
            ),
          ),
        );
      await _open(tester, server);
      // A list says nothing of requests.
      expect(find.text('Request waiting for approval'), findsNothing);
      await _tap(tester, find.text('Metropolis'));

      await _tap(tester, find.byType(BackButton));

      expect(find.text('Request waiting for approval'), findsOneWidget);
      expect(server.reads('discover/trending'), hasLength(1));
    });

    testWidgets('offers 4K to who may request it', (tester) async {
      await _open(tester, _server(me: 'auth_me_admin'), at: _movie);

      expect(_button('Request'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Request in 4K'),
        findsOneWidget,
      );
    });

    testWidgets('shows the status of each variant', (tester) async {
      final server = _server(me: 'auth_me_admin')
        ..set(
          'GET api/v1/movie/19',
          json(
            _movieTitle(
              status: 2,
              requests: [
                {'id': 1, 'status': 1, 'is4k': false},
              ],
            ),
          ),
        );

      await _open(tester, server, at: _movie);

      expect(find.text('Waiting for approval'), findsOneWidget);
      expect(find.text('Request waiting for approval'), findsOneWidget);
      expect(_button('Request'), findsNothing);
      expect(find.text('Request in 4K'), findsOneWidget);
    });

    testWidgets('offers nothing for a blocklisted title', (tester) async {
      final server = _server()
        ..set('GET api/v1/movie/19', json(_movieTitle(status: 6)));

      await _open(tester, server, at: _movie);

      expect(find.text('Blocklisted'), findsOneWidget);
      expect(_button('Request'), findsNothing);
    });

    testWidgets('offers nothing when permissions cannot be read', (
      tester,
    ) async {
      final server = _server()
        ..set('GET api/v1/auth/me', unsent(const Unreachable()));

      await _open(tester, server, at: _movie);

      expect(
        find.text('What you may request could not be checked.'),
        findsOneWidget,
      );
      expect(_button('Request'), findsNothing);
    });

    testWidgets('says that a title is gone', (tester) async {
      final server = _server()..set('GET api/v1/movie/19', answered(404, '{}'));

      await _open(tester, server, at: _movie);

      expect(find.byType(ItemGoneView), findsOneWidget);
    });

    testWidgets('a path that names no title says so', (tester) async {
      await _open(tester, _server(), at: 'seerr/titles/person/1');

      expect(find.byType(ItemGoneView), findsOneWidget);
    });
  });

  group('request', () {
    Future<void> openRequest(WidgetTester tester, FakeSeerr server) async {
      await _open(tester, server, at: _movie);
      await _tap(tester, _button('Request'));
    }

    testWidgets('sends a movie once and shows its status', (tester) async {
      final server = _server()..held['POST api/v1/request'] = Completer<void>();
      await openRequest(tester, server);
      expect(find.text('2 of 2 used in the last 7 days'), findsOneWidget);

      await tester.tap(_button('Request movie'));
      await tester.pump();
      expect(_enabled(tester, 'Sending request'), isFalse);
      server.set(
        'GET api/v1/movie/19',
        json(
          _movieTitle(
            status: 2,
            requests: [
              {'id': 8, 'status': 1, 'is4k': false},
            ],
          ),
        ),
      );
      server.held['POST api/v1/request']!.complete();
      await tester.pumpAndSettle();

      expect(sent(server.writes.single), {
        'mediaType': 'movie',
        'mediaId': 19,
        'is4k': false,
      });
      expect(find.text('Requested Metropolis.'), findsOneWidget);
      // Back on the title.
      expect(find.text('Request movie'), findsNothing);
      expect(find.text('Request waiting for approval'), findsOneWidget);
    });

    testWidgets('shows why the server refused', (tester) async {
      final server = _server()
        ..set(
          'POST api/v1/request',
          answered(403, fixture('request_over_quota')),
        );
      await openRequest(tester, server);

      await _tap(tester, _button('Request movie'));

      expect(
        find.text(
          'Metropolis was not requested. The server says: '
          'Movie Quota exceeded.',
        ),
        findsOneWidget,
      );
      expect(_enabled(tester, 'Request movie'), isTrue);
    });

    testWidgets('asks before sending again after an unknown outcome', (
      tester,
    ) async {
      final server = _server()
        ..set('POST api/v1/request', unsent(const OutcomeUnknown()));
      await openRequest(tester, server);
      final reads = server.reads('movie/19').length;

      await _tap(tester, _button('Request movie'));

      expect(find.textContaining('arrived. Check its status'), findsOneWidget);
      expect(server.reads('movie/19').length, greaterThan(reads));
      expect(server.writes, hasLength(1));
      await _tap(tester, find.byIcon(Icons.close));

      await _tap(tester, _button('Request movie'));
      expect(find.text('Send the request again?'), findsOneWidget);
      await _tap(tester, find.text('Cancel'));
      expect(server.writes, hasLength(1));

      await _tap(tester, _button('Request movie'));
      await _tap(tester, _button('Send again'));
      expect(server.writes, hasLength(2));
    });

    testWidgets('sends the seasons chosen', (tester) async {
      final server = _server()
        ..set(
          'POST api/v1/request',
          answered(201, fixture('request_created_tv')),
        );
      await _open(tester, server, at: _series);
      await _tap(tester, _button('Request'));

      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Specials'), findsNothing);
      expect(_enabled(tester, 'Choose seasons'), isFalse);

      await _tap(tester, find.text('All seasons'));
      expect(_button('Request 2 seasons'), findsOneWidget);
      await _tap(tester, find.text('Season 1'));
      await _tap(tester, _button('Request 1 season'));

      expect(sent(server.writes.single), {
        'mediaType': 'tv',
        'mediaId': 1100,
        'is4k': false,
        'seasons': [2],
      });
    });

    testWidgets('sends every open season where they go together', (
      tester,
    ) async {
      final server = _server()
        ..set(
          'GET api/v1/settings/public',
          json({...publicSettings(), 'partialRequestsEnabled': false}),
        )
        ..set(
          'POST api/v1/request',
          answered(201, fixture('request_created_tv')),
        );
      await _open(tester, server, at: _series);
      await _tap(tester, _button('Request'));

      await _tap(tester, _button('Request 2 seasons'));

      expect(sent(server.writes.single)['seasons'], [1, 2]);
    });

    testWidgets('sends nothing where no season is left', (tester) async {
      final server = _server()..set('GET api/v1/tv/1100', ok(fixture('tv')));
      await _open(tester, server, at: _series);
      await _tap(tester, _button('Request'));

      expect(find.text('No season is left to request.'), findsOneWidget);
      expect(find.text('22 episodes · Requested'), findsNWidgets(2));
      expect(_enabled(tester, 'Choose seasons'), isFalse);
    });

    testWidgets('leaves out a quota that cannot be read', (tester) async {
      final server = _server()
        ..set('GET api/v1/user/2/quota', answered(500, '{}'));

      await openRequest(tester, server);

      expect(find.text('Movie requests'), findsNothing);
      expect(_enabled(tester, 'Request movie'), isTrue);
    });

    testWidgets('explains a request that is not offered', (tester) async {
      await _open(tester, _server(), at: '$_movie/request?is4k=true');

      expect(find.text('Your account may not request this.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  testWidgets('shows the quota', (tester) async {
    await _open(tester, _server());

    await _tap(tester, find.byTooltip('Request quota'));

    expect(find.text('Movie requests'), findsOneWidget);
    expect(find.text('2 of 2 used in the last 7 days'), findsOneWidget);
    expect(find.text('2 of 3 used in the last 7 days'), findsOneWidget);
  });

  testWidgets('offers no quota to who may request nothing', (tester) async {
    await _open(tester, _server(), permissions: {});

    expect(find.byTooltip('Request quota'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('fits a narrow screen with large text, $brightness', (
      tester,
    ) async {
      final router = await _open(
        tester,
        _server(me: 'auth_me_admin'),
        size: const Size(320, 640),
        textScale: 2,
        brightness: brightness,
      );
      for (final path in [
        _movie,
        '$_movie/request?is4k=false',
        '$_series/request?is4k=false',
        'seerr/quota',
      ]) {
        unawaited(router.push('/instances/i1/$path'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: path);
      }
    });
  }
}
