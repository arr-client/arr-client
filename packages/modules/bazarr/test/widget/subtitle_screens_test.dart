// The subtitle screens (spec story 10), as the app builds them from the
// module's routes, over the recorded server. The allow-list refuses any write
// Bazarr is not meant to get.

import 'dart:async';

import 'package:bazarr/bazarr_module.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../contract/support.dart';

/// Holds a request in [held] until its completer is.
class _Server extends FakeBazarr {
  final held = <String, Completer<void>>{};

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    final answer = await super.send(request);
    await held[asked(request)]?.future;
    return answer;
  }
}

const _main = '/instances/$instanceId/bazarr/subtitles';
const _movie = '$_main/movies/1';
const _movieSearch = '$_movie/search';

Future<Harness> _open(
  WidgetTester tester,
  String location, {
  FakeBazarr? server,
  Size size = const Size(400, 3000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = Harness(latest, server);
  final module = BazarrModule();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      for (final screen in module.routes())
        GoRoute(
          path: '/instances/:instanceId/${screen.path}',
          builder: (context, state) => screen.builder(
            context,
            harness.context,
            {...state.pathParameters, ...state.uri.queryParameters},
          ),
        ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        theme: ArrTheme.light(),
        localizationsDelegates: const [
          BazarrLocalizations.delegate,
          ...uiLocalizationsDelegates,
        ],
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// What was written to the server.
List<ServiceRequest> _writes(Harness harness) => [
  for (final request in harness.server.requests)
    if (request.method != HttpMethod.get) request,
];

/// The first file of movie 1.
Map<String, Object?> _file() =>
    (records('movies').first['subtitles']! as List<Object?>).first!
        as Map<String, Object?>;

String _titleOf(int movie) =>
    records('movies').singleWhere((r) => r['radarrId'] == movie)['title']!
        as String;

void main() {
  testWidgets('lists what is wanted and opens a title', (tester) async {
    final harness = await _open(tester, _main);
    final wanted = records('movies_wanted');

    expect(find.byType(ListTile), findsNWidgets(wanted.length));
    expect(
      find.textContaining('Missing: fr, de (hearing impaired), es'),
      findsWidgets,
    );
    expect(harness.server.sent, ['GET movies/wanted']);

    await _tap(tester, find.widgetWithText(ChoiceChip, 'Episodes'));
    expect(
      find.byType(ListTile),
      findsNWidgets(records('episodes_wanted').length),
    );

    await _tap(tester, find.widgetWithText(ChoiceChip, 'Movies'));
    await _tap(tester, find.text(_titleOf(1)));
    expect(find.text('Missing languages'), findsOneWidget);
    expect(find.text('Subtitle files'), findsOneWidget);
  });

  testWidgets('shows history, also an entry without a language', (
    tester,
  ) async {
    final server = FakeBazarr();
    final history = records('movies_history');
    history.first['language'] = {
      'name': null,
      'code2': null,
      'forced': null,
      'hi': null,
    };
    server.routes['GET movies/history'] = jsonAnswer({
      'data': history,
      'total': history.length,
    });
    await _open(tester, _main, server: server);

    await _tap(tester, find.text('History'));

    expect(find.byType(ListTile), findsNWidgets(history.length));
    expect(find.textContaining('Language: Unknown language'), findsOneWidget);
    expect(find.textContaining('seconds ago'), findsWidgets);
  });

  testWidgets('reads the next page when asked', (tester) async {
    final server = FakeBazarr();
    final wanted = records('movies_wanted');
    server.routes['GET movies/wanted'] = jsonAnswer({
      'data': [wanted.first],
      'total': 60,
    });
    final harness = await _open(tester, _main, server: server);
    server.routes['GET movies/wanted'] = jsonAnswer({
      'data': [wanted.last],
      'total': 60,
    });

    await _tap(tester, find.text('Show more'));

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(queryOf(harness.server.requests.last)['start'], '50');
    expect(find.text('Show more'), findsNothing);
  });

  testWidgets('browses to a series, its episodes and one of them', (
    tester,
  ) async {
    await _open(tester, _main);
    final series = records('series').first;
    final episode = records('episodes_series_1').first;

    await _tap(tester, find.text('Browse'));
    await _tap(tester, find.widgetWithText(ChoiceChip, 'Series'));
    await _tap(tester, find.textContaining(series['title']! as String));
    expect(find.byType(ListTile), findsNWidgets(4));

    await _tap(tester, find.textContaining(episode['title']! as String));
    expect(find.text('Subtitle files'), findsOneWidget);
    expect(find.text(series['title']! as String), findsOneWidget);
  });

  testWidgets('says an automatic search was sent, not done', (tester) async {
    final harness = await _open(tester, _movie);

    await _tap(tester, find.text('Search and download').first);

    expect(_writes(harness), hasLength(1));
    expect(find.text('Search request sent to Home.'), findsOneWidget);
    expect(find.textContaining('It may still be working'), findsOneWidget);
    expect(find.textContaining('done'), findsNothing);

    harness.server.requests.clear();
    await _tap(tester, find.widgetWithText(OutlinedButton, 'Refresh'));
    expect(harness.server.sent, ['GET movies']);
    expect(find.textContaining('It may still be working'), findsNothing);
  });

  testWidgets('says a request without an answer may still be running', (
    tester,
  ) async {
    final server = FakeBazarr();
    server.routes['PATCH movies/subtitles'] = failedAnswer(
      const OutcomeUnknown(),
    );
    final harness = await _open(tester, _movie, server: server);

    await _tap(tester, find.text('Search and download').first);

    expect(find.textContaining('may still be running'), findsNWidgets(2));
    expect(_writes(harness), hasLength(1));
  });

  testWidgets('sends one change of a title at a time, also after leaving', (
    tester,
  ) async {
    final server = _Server();
    server.held['PATCH movies/subtitles'] = Completer();
    final harness = await _open(tester, _main, server: server);
    await _tap(tester, find.text(_titleOf(1)));

    await tester.tap(find.text('Search and download').first);
    await tester.pump();
    // The progress bar never settles.
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text(_titleOf(1)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    for (final button in tester.widgetList<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Delete subtitle'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    )) {
      expect(button.onPressed, isNull);
    }
    expect(find.text('Sending the request to Home.'), findsOneWidget);
    server.held.remove('PATCH movies/subtitles')!.complete();
    await tester.pumpAndSettle();
    expect(_writes(harness), hasLength(1));
  });

  testWidgets('deletes only the file confirmed, naming it', (tester) async {
    final harness = await _open(tester, _movie);
    final path = _file()['path']! as String;

    await _tap(tester, find.text('Delete subtitle').first);
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text(path)),
      findsOneWidget,
    );
    await _tap(tester, find.text('Cancel'));
    expect(_writes(harness), isEmpty);

    await _tap(tester, find.text('Delete subtitle').first);
    harness.server.requests.clear();
    await _tap(
      tester,
      find.descendant(of: dialog, matching: find.bySubtype<FilledButton>()),
    );

    expect(harness.server.sent, ['DELETE movies/subtitles', 'GET movies']);
    expect(formOf(harness.server.requests.first)['path'], path);
    expect(find.text('Subtitle file deleted from Home.'), findsOneWidget);
    expect(find.textContaining('Request sent'), findsNothing);
  });

  testWidgets('shows the end of a very long path', (tester) async {
    final server = FakeBazarr();
    final movies = records('movies');
    final path = '/${'folder/' * 100}the film.en.srt';
    ((movies.first['subtitles']! as List<Object?>).first!
            as Map<String, Object?>)['path'] =
        path;
    server.routes['GET movies'] = jsonAnswer({'data': movies, 'total': 3});
    await _open(tester, _movie, server: server);

    await _tap(tester, find.text('Delete subtitle').first);

    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text(path)),
      findsOneWidget,
    );
  });

  testWidgets('synchronizes after confirmation and says it was sent', (
    tester,
  ) async {
    final harness = await _open(tester, _movie);

    await _tap(tester, find.text('Synchronize').first);
    expect(_writes(harness), isEmpty);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.bySubtype<FilledButton>(),
      ),
    );

    expect(formOf(_writes(harness).single)['path'], _file()['path']);
    expect(find.text('Synchronization request sent to Home.'), findsOneWidget);
    expect(find.textContaining('It may still be working'), findsOneWidget);
  });

  testWidgets('searches the providers and downloads once', (tester) async {
    final harness = await _open(tester, _movie);
    final candidates = records('providers_movies');

    await _tap(tester, find.text('Search providers'));

    expect(find.text('Score: 100'), findsNWidgets(candidates.length));
    expect(
      find.text('Matches: hash, hearing impaired'),
      findsNWidgets(candidates.length),
    );
    expect(find.text('Language: fr'), findsOneWidget);

    await _tap(tester, find.text('Download').first);

    expect(
      formOf(_writes(harness).single)['subtitle'],
      candidates.first['subtitle'],
    );
    expect(find.text('Download request sent to Home.'), findsOneWidget);
    expect(find.text('Download requested'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);

    await _tap(tester, find.text('Back to subtitles'));
    expect(find.text('Subtitle files'), findsOneWidget);
    expect(find.textContaining('It may still be working'), findsOneWidget);
  });

  testWidgets('lets a refused download be tried again', (tester) async {
    final server = FakeBazarr();
    server.routes['POST providers/movies'] = failedAnswer(
      const ServerError(statusCode: 500),
    );
    await _open(tester, _movieSearch, server: server);

    await _tap(tester, find.text('Download').first);

    expect(find.text('Download requested'), findsNothing);
    expect(find.text('Download'), findsNWidgets(2));
  });

  testWidgets('says that the providers offered nothing', (tester) async {
    final server = FakeBazarr();
    server.routes['GET providers/movies'] = jsonAnswer({'data': <Object?>[]});

    await _open(tester, _movieSearch, server: server);

    expect(find.text('The providers offered no subtitles.'), findsOneWidget);
  });

  testWidgets('says a title the server does not know is gone', (tester) async {
    await _open(tester, '$_main/movies/999');

    expect(find.byType(ItemGoneView), findsOneWidget);
  });

  testWidgets('keeps what was read when a refresh fails', (tester) async {
    final harness = await _open(tester, _movie);
    harness.server.down = failedAnswer(const Unreachable());

    await _tap(tester, find.byTooltip('Refresh'));

    expect(find.byType(StaleNotice), findsOneWidget);
    expect(find.text('Subtitle files'), findsOneWidget);
  });

  for (final location in [_main, _movie, _movieSearch, '$_main/series/1']) {
    testWidgets('fits large text on a small phone: $location', (tester) async {
      final semantics = tester.ensureSemantics();
      await _open(tester, location, size: const Size(320, 640), textScale: 2);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
