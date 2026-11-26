// The movie screen (spec story 2), opened as the app opens it and fed by the
// module's own adapters over a Radarr that answers from recordings.

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:radarr/radarr_module.dart';
import 'package:ui/ui.dart';

import '../contract/library_support.dart';

/// Notes which histories were asked for.
class _Navigator extends Fake implements AppNavigator {
  final histories = <ItemRef>[];

  @override
  Future<void> openHistory(ItemRef ref) async => histories.add(ref);
}

class _NoArtwork implements ArtworkLoader {
  @override
  ImageProvider<Object>? image(MediaImage image) => null;
}

/// Holds back every answer until [open] completes.
class _SlowRadarr extends FakeRadarr {
  final open = Completer<void>();

  @override
  Future<Result<ServiceResponse, HttpError>> send(
    ServiceRequest request,
  ) async {
    await open.future;
    return super.send(request);
  }
}

/// Movie 1 of the recordings, with the values sanitizing took away.
Map<String, Object?> _movie() => {
  ...fixture('movie_1')! as Map<String, Object?>,
  'title': 'The Long Voyage Home and Other Stories',
  'overview': 'A crew far from port.',
  'studio': 'Harbour Pictures',
  'path': '/media/movies/voyage',
  'genres': ['Drama', 'Adventure'],
  'certification': 'PG-13',
  'runtime': 136,
  'inCinemas': '2008-04-10T00:00:00Z',
  'digitalRelease': '2008-07-01T00:00:00Z',
  'physicalRelease': null,
  'qualityProfileId': 4,
};

const _credits = [
  {'personName': 'Ada Actor', 'type': 'cast', 'character': 'The Captain'},
  {'personName': 'Dee Director', 'type': 'crew', 'job': 'Director'},
  {'personName': 'Nat Nameless', 'type': 'crew'},
];

FakeRadarr _server([FakeRadarr? server]) => (server ?? FakeRadarr())
  ..answers['api/v3/movie/1'] = jsonAnswer(_movie())
  ..answers['api/v3/credit'] = jsonAnswer(_credits);

InstanceContext _instance(Harness harness, [AppNavigator? navigator]) {
  final context = harness.context;
  return InstanceContext(
    instance: context.instance,
    http: context.http,
    artwork: _NoArtwork(),
    navigator: navigator ?? context.navigator,
    cache: context.cache,
    logger: context.logger,
  );
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    Harness harness, {
    String movieId = '1',
    Size size = const Size(400, 4000),
    double textScale = 1,
    ThemeData? theme,
    Widget Function(Widget child)? wrap,
    bool settle = true,
    AppNavigator? navigator,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final instance = _instance(harness, navigator);
    final screen = RadarrModule().routes().single;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          theme: theme ?? ArrTheme.light(),
          localizationsDelegates: const [
            RadarrLocalizations.delegate,
            ...uiLocalizationsDelegates,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: wrap?.call(child!) ?? child!,
          ),
          home: Builder(
            builder: (context) =>
                screen.builder(context, instance, {'movieId': movieId}),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  /// Fetches the movie once, so that it is saved.
  Future<void> save(Harness harness) =>
      succeed(harness.library.item(movieRef(1)));

  test('the route of a movie is the screen the module registers', () {
    final harness = Harness();

    final route = harness.library.detailRoute(movieRef(7));

    expect(route.location, '/instances/i1/radarr/movies/7');
    expect(RadarrModule().routes().single.path, 'radarr/movies/:movieId');
  });

  testWidgets('shows what story 2 lists for a movie', (tester) async {
    await pump(tester, Harness(_server()));

    for (final text in [
      'The Long Voyage Home and Other Stories',
      '2008',
      '136 min',
      'PG-13',
      'Details',
      'Downloaded',
      'Monitored',
      'On Home',
      'A crew far from port.',
      'Drama, Adventure',
      'Harbour Pictures',
      // A calendar day, in whatever zone the device is.
      'Thursday, April 10, 2008',
      'Tuesday, July 1, 2008',
      '/media/movies/voyage',
      'Bluray-1080p',
      '20.8 MiB',
      'English',
      'x264 1920x1080',
      'AC3 5.1',
      'Cast',
      'Ada Actor',
      'as The Captain',
      'Crew',
      'Dee Director',
      'Director',
      'Nat Nameless',
      'History',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.textContaining('IMDb: 6.4 · 2,269 votes'), findsOneWidget);
    expect(find.text('Physical release'), findsNothing);
    final profile =
        records(fixture('qualityprofile'))
                .singleWhere((profile) => profile['id'] == 4)['name']!
            as String;
    expect(find.text(profile), findsOneWidget);
    expect(find.text('File renamed'), findsOneWidget);
    expect(find.textContaining('Saved data'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('The Long Voyage Home and Other Stories'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the refresh button asks the server again', (tester) async {
    final harness = Harness(_server());
    await pump(tester, harness);
    harness.server.answers['api/v3/movie/1'] = jsonAnswer({
      ..._movie(),
      'overview': 'The crew is home.',
    });

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('The crew is home.'), findsOneWidget);
  });

  testWidgets('says when the quality profile cannot be read, and retries', (
    tester,
  ) async {
    final harness = Harness(_server());
    harness.server.answers['api/v3/qualityprofile'] = failedAnswer(
      const ServerError(statusCode: 500),
      status: 500,
    );
    await pump(tester, harness);

    expect(find.text('Quality profile'), findsOneWidget);
    expect(find.textContaining('error 500'), findsOneWidget);

    harness.server.answers.remove('api/v3/qualityprofile');
    harness.server.requests.clear();
    await tester.tap(find.text('Retry quality profile'));
    await tester.pumpAndSettle();

    final profile =
        records(fixture('qualityprofile'))
                .singleWhere((profile) => profile['id'] == 4)['name']!
            as String;
    expect(find.text(profile), findsOneWidget);
    expect(find.textContaining('error 500'), findsNothing);
    expect(
      harness.server.requests.map((request) => request.path),
      isNot(contains('api/v3/movie/1')),
    );
  });

  testWidgets('says when history cannot be read, and retries it', (
    tester,
  ) async {
    final harness = Harness(_server());
    harness.server.answers['api/v3/history/movie'] = failedAnswer(
      const ServerError(statusCode: 500),
      status: 500,
    );
    await pump(tester, harness);

    expect(find.text('History could not be loaded.'), findsOneWidget);

    harness.server.answers.remove('api/v3/history/movie');
    await tester.tap(find.text('Retry history'));
    await tester.pumpAndSettle();

    expect(find.text('File renamed'), findsOneWidget);
    expect(find.text('History could not be loaded.'), findsNothing);
  });

  testWidgets('shows the newest events and leads to the rest', (tester) async {
    final harness = Harness(_server());
    final event = records(fixture('history_movie_1')).first;
    harness.server.answers['api/v3/history/movie'] = jsonAnswer([
      for (var i = 1; i <= 6; i++)
        {...event, 'id': i, 'sourceTitle': 'Release $i'},
    ]);
    final navigator = _Navigator();
    await pump(tester, harness, navigator: navigator);

    expect(find.text('Release 6'), findsOneWidget);
    expect(find.text('Release 1'), findsNothing);

    await tester.tap(find.text('Show all history'));

    expect(navigator.histories, [movieRef(1)]);
  });

  testWidgets('marks the title and the section names as headings', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, Harness(_server()));

    for (final heading in [
      'The Long Voyage Home and Other Stories',
      'File',
      'Cast',
      'Crew',
      'History',
    ]) {
      expect(
        // The title is in the app bar too, which comes first.
        tester.getSemantics(find.text(heading).last),
        isSemantics(label: heading, isHeader: true),
        reason: heading,
      );
    }
    semantics.dispose();
  });

  testWidgets('reads only from the instance that holds the movie', (
    tester,
  ) async {
    final harness = Harness(_server());

    await pump(tester, harness);

    // The allow-list lets no write through, and none is tried.
    expect(harness.server.requests.map((request) => request.method).toSet(), {
      HttpMethod.get,
    });
    expect(
      harness.server.requests.map((request) => request.path),
      containsAll([
        'api/v3/movie/1',
        'api/v3/moviefile',
        'api/v3/credit',
        'api/v3/history/movie',
        'api/v3/qualityprofile',
      ]),
    );
  });

  testWidgets('places both slots with the movie', (tester) async {
    final slots = <DetailSlotName, ItemRef>{};

    await pump(
      tester,
      Harness(_server()),
      wrap: (child) => DetailSlotScope(
        builder: (context, slot) {
          slots[slot.name] = slot.item;
          return const SizedBox.shrink();
        },
        child: child,
      ),
    );

    expect(slots, {
      DetailSlotName.downloadProgress: movieRef(1),
      DetailSlotName.subtitles: movieRef(1),
    });
  });

  testWidgets('shows the saved movie while the server is asked', (
    tester,
  ) async {
    final server = _SlowRadarr();
    final harness = Harness(_server(server));
    server.open.complete();
    await save(harness);
    final slow = _SlowRadarr();
    final waiting = Harness(_server(slow));
    waiting.cache.entries.addAll(harness.cache.entries);

    await pump(tester, waiting, settle: false);

    expect(find.text('The Long Voyage Home and Other Stories'), findsWidgets);
    expect(find.textContaining('Saved data'), findsOneWidget);
    // The saved record names its file.
    expect(find.text('Bluray-1080p'), findsOneWidget);

    slow.open.complete();
    await tester.pumpAndSettle();

    expect(find.textContaining('Saved data'), findsNothing);
    expect(find.text('Ada Actor'), findsOneWidget);
  });

  testWidgets('offline, shows the saved movie with its age and a retry', (
    tester,
  ) async {
    final harness = Harness(_server());
    await save(harness);
    harness.server.down = failedAnswer(const Unreachable());

    await pump(tester, harness);

    expect(find.textContaining('Saved data'), findsOneWidget);
    // The notice, the quality profile and the history each give the reason.
    expect(find.textContaining('did not answer'), findsNWidgets(3));
    expect(find.text('A crew far from port.'), findsOneWidget);
    expect(find.text('Bluray-1080p'), findsOneWidget);
    // Cast, history and the profile's name are not kept for offline use.
    expect(find.text('Not saved for offline viewing'), findsOneWidget);
    expect(find.text('History could not be loaded.'), findsOneWidget);
    expect(find.text('Retry quality profile'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    harness.server.down = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Saved data'), findsNothing);
    expect(find.text('Ada Actor'), findsOneWidget);
    expect(find.text('File renamed'), findsOneWidget);
  });

  testWidgets('with nothing saved, says why it cannot load', (tester) async {
    final harness = Harness(_server());
    harness.server.down = failedAnswer(const Unreachable());

    await pump(tester, harness);

    expect(find.textContaining('did not answer'), findsOneWidget);
    harness.server.down = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('A crew far from port.'), findsOneWidget);
  });

  testWidgets('says a deleted movie is gone and forgets it', (tester) async {
    final harness = Harness(_server());
    await save(harness);
    harness.server.answers['api/v3/movie/1'] = failedAnswer(
      const NotFound(),
      status: 404,
    );

    await pump(tester, harness);

    expect(
      find.text('This item no longer exists on the server.'),
      findsOneWidget,
    );
    expect(find.text('A crew far from port.'), findsNothing);
    expect(harness.cache.entries, isEmpty);
  });

  testWidgets('takes an id no movie can have as gone', (tester) async {
    final harness = Harness(_server());

    await pump(tester, harness, movieId: 'x');

    expect(
      find.text('This item no longer exists on the server.'),
      findsOneWidget,
    );
    expect(harness.server.requests, isEmpty);
  });

  testWidgets('a part that fails leaves the rest and can be retried', (
    tester,
  ) async {
    final harness = Harness(_server());
    harness.server.answers['api/v3/credit'] = failedAnswer(
      const ServerError(statusCode: 500),
      status: 500,
    );

    await pump(tester, harness);

    expect(find.text('A crew far from port.'), findsOneWidget);
    expect(find.text('File renamed'), findsOneWidget);
    expect(find.textContaining('error 500'), findsOneWidget);

    harness.server.answers['api/v3/credit'] = jsonAnswer(_credits);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Ada Actor'), findsOneWidget);
    expect(find.textContaining('error 500'), findsNothing);
  });

  testWidgets('leaves out cast the server does not have, and an absent file', (
    tester,
  ) async {
    final harness = Harness(_server());
    harness.server
      ..answers['api/v3/movie/1'] = jsonAnswer({
        ..._movie(),
        'movieFile': null,
        'hasFile': false,
        'monitored': false,
      })
      ..answers['api/v3/moviefile'] = jsonAnswer(<Object>[])
      ..answers['api/v3/credit'] = jsonAnswer(<Object>[])
      ..answers['api/v3/history/movie'] = jsonAnswer(<Object>[]);

    await pump(tester, harness);

    expect(find.text('Cast'), findsNothing);
    expect(find.text('Crew'), findsNothing);
    expect(find.text('No file'), findsOneWidget);
    expect(find.text('No history'), findsOneWidget);
    expect(find.text('Unmonitored'), findsOneWidget);
    expect(find.text('Not monitored'), findsOneWidget);
  });

  testWidgets('shows the whole cast on request', (tester) async {
    final harness = Harness(_server());
    harness.server.answers['api/v3/credit'] = jsonAnswer([
      for (var i = 1; i <= 12; i++) {'personName': 'Actor $i', 'type': 'cast'},
    ]);
    await pump(tester, harness);

    expect(find.text('Actor 10'), findsOneWidget);
    expect(find.text('Actor 11'), findsNothing);

    await tester.tap(find.text('Show all cast (12)'));
    await tester.pumpAndSettle();

    expect(find.text('Actor 12'), findsOneWidget);
    expect(find.text('Show all cast (12)'), findsNothing);
  });

  for (final (name, theme) in [
    ('light', ArrTheme.light()),
    ('dark', ArrTheme.dark()),
  ]) {
    testWidgets('fits a small phone at 200% text, $name', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = Harness(_server());
      await save(harness);
      harness.server.down = failedAnswer(const Unreachable());
      await pump(
        tester,
        harness,
        size: const Size(320, 640),
        textScale: 2,
        theme: theme,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      harness.server.down = null;
      // At this size the notice scrolls too.
      await tester.ensureVisible(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('File renamed'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
