// The search, grab and indexer status screen (spec story 11), as the app builds
// it from the module's route, over the recorded server. The allow-list refuses
// any write Prowlarr is not meant to get.

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prowlarr/prowlarr_module.dart';
import 'package:ui/ui.dart';

import '../contract/support.dart';

const _key = 'zqSECRETkey';

/// The recorded results, each with its own title and with keys where the server
/// has them.
List<Map<String, Object?>> _results() => [
  for (final (index, record) in records(fixture('search')).indexed)
    {
      ...record,
      'title': ['Alpha', 'Charlie', 'Bravo'][index],
      'size': [100, 300, 200][index],
      'guid': 'https://tracker.test/$index?passkey=$_key',
      'infoUrl': 'https://tracker.test/info?passkey=$_key',
      'commentUrl': 'https://tracker.test/comment?passkey=$_key',
      'downloadUrl': 'http://server.test/1/download?apikey=$_key',
      'magnetUrl': 'magnet:?xt=urn:btih:0&tr=$_key',
    },
];

/// Holds a request in [held] until its completer is.
class _Server extends FakeProwlarr {
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

Widget _app(Harness harness, {double textScale = 1}) {
  final screen = ProwlarrModule().routes().single;
  return ProviderScope(
    child: MaterialApp(
      theme: ArrTheme.light(),
      localizationsDelegates: const [
        ProwlarrLocalizations.delegate,
        ...uiLocalizationsDelegates,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) =>
            screen.builder(context, harness.context, const {}),
      ),
    ),
  );
}

Future<Harness> _open(
  WidgetTester tester, {
  FakeProwlarr? server,
  Size size = const Size(400, 3000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = Harness(server: server);
  harness.server.routes['GET search'] = jsonAnswer(_results());
  await tester.pumpWidget(_app(harness, textScale: textScale));
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _search(WidgetTester tester, [String term = 'a']) async {
  await tester.enterText(find.byType(TextField), term);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

Finder _grabOf(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(ReleaseRow)),
  matching: find.byType(TextButton),
);

List<String> _titles(WidgetTester tester) => [
  for (final row in tester.widgetList<ReleaseRow>(find.byType(ReleaseRow)))
    row.release.title,
];

/// Everything written on the screen, for readers of both kinds.
String _shown(WidgetTester tester) => [
  for (final widget in tester.allWidgets)
    if (widget case Text(:final data, :final semanticsLabel))
      '$data $semanticsLabel',
].join('\n');

void main() {
  testWidgets('searches only when asked, for a term', (tester) async {
    final harness = await _open(tester);

    expect(find.text('Search your indexers by title.'), findsOneWidget);
    await _search(tester, '  ');
    expect(harness.server.requests, isEmpty);

    await _search(tester);
    expect(harness.server.sent, ['GET search']);
    expect(find.text('3 results'), findsOneWidget);
    expect(_titles(tester), ['Alpha', 'Charlie', 'Bravo']);
    expect(find.textContaining('Size: '), findsNWidgets(3));
    expect(find.textContaining('Age: '), findsNWidgets(3));
    expect(find.textContaining('Indexer: '), findsNWidgets(3));
    expect(find.textContaining('Seeders: '), findsNWidgets(2));
    // Prowlarr does not score.
    expect(find.textContaining('Score'), findsNothing);
  });

  testWidgets('shows, logs and stores nothing of a key', (tester) async {
    final harness = await _open(tester);
    harness.server.routes['POST search'] = failedAnswer(
      const ServerError(statusCode: 500),
      status: 500,
      body: '{"message":"$_key"}',
    );

    await _search(tester);
    await tester.tap(_grabOf('Alpha'));
    await tester.pumpAndSettle();

    expect(_shown(tester), isNot(contains(_key)));
    expect(_shown(tester), isNot(contains('tracker.test')));
    expect(harness.logger.lines.join(), isNot(contains(_key)));
    expect(harness.cache.used, isEmpty);
  });

  testWidgets('sorts the results', (tester) async {
    await _open(tester);
    await _search(tester);

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Size').last);
    await tester.pumpAndSettle();
    expect(_titles(tester), ['Charlie', 'Bravo', 'Alpha']);

    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ascending'));
    await tester.pumpAndSettle();
    expect(_titles(tester), ['Alpha', 'Bravo', 'Charlie']);
  });

  testWidgets('searches again with the filters chosen', (tester) async {
    final harness = await _open(tester);
    await _search(tester);
    final indexer = records(fixture('indexer')).first;
    final name = indexer['name']! as String;

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, name));
    await tester.pumpAndSettle();
    final category = tester.widget<FilterChip>(find.byType(FilterChip).at(2));
    category.onSelected!(true);
    await tester.pumpAndSettle();
    harness.server.requests.clear();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final query = harness.server.requests.single.query;
    expect(query['indexerIds'], ['${indexer['id']}']);
    expect(query['categories'], hasLength(1));
    expect(find.byTooltip('Filters, 2 on'), findsOneWidget);
  });

  testWidgets('says that nothing was found and what that leaves out', (
    tester,
  ) async {
    final harness = await _open(tester);
    harness.server.routes['GET search'] = jsonAnswer(<Object?>[]);

    await _search(tester);

    expect(find.textContaining('left out without a warning'), findsOneWidget);
  });

  testWidgets('words a refused search itself', (tester) async {
    final harness = await _open(tester);
    harness.server.routes['GET search'] = failedAnswer(
      const Validation(['tracker.test $_key']),
      status: 400,
    );

    await _search(tester);

    expect(find.textContaining('Prowlarr refused the search'), findsOneWidget);
    expect(_shown(tester), isNot(contains(_key)));
    harness.server.routes['GET search'] = jsonAnswer(_results());
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(ReleaseRow), findsNWidgets(3));
  });

  testWidgets('grabs once and does not claim a download', (tester) async {
    final harness = await _open(tester);
    await _search(tester);
    harness.server.requests.clear();

    await tester.tap(_grabOf('Alpha'));
    await tester.pumpAndSettle();

    expect(harness.server.sent, ['POST search']);
    expect(
      find.text(
        'Home accepted the grab of Alpha. Check the download client to see '
        'that the download started.',
      ),
      findsOneWidget,
    );
    expect(find.text('Grab accepted'), findsOneWidget);
    expect(_grabOf('Alpha'), findsNothing);
  });

  for (final (failure, message) in const <(ServiceFailure, String)>[
    (NotFound(), 'This search result has expired. Search again.'),
    (Conflict(), 'The indexer did not give Prowlarr the download.'),
    (ServerError(statusCode: 500), 'has a download client'),
    (Validation([_key]), 'Prowlarr refused the grab.'),
  ]) {
    testWidgets('words the refusal ${failure.runtimeType}', (tester) async {
      final harness = await _open(tester);
      harness.server.routes['POST search'] = failedAnswer(failure);
      await _search(tester);

      await tester.tap(_grabOf('Alpha'));
      await tester.pumpAndSettle();

      expect(find.textContaining(message), findsOneWidget);
      expect(_shown(tester), isNot(contains(_key)));
      // It may be tried again.
      expect(_grabOf('Alpha'), findsOneWidget);
    });
  }

  testWidgets('confirms before repeating a grab of unknown outcome', (
    tester,
  ) async {
    final harness = await _open(tester);
    harness.server.routes['POST search'] = failedAnswer(const OutcomeUnknown());
    await _search(tester);
    harness.server.requests.clear();

    await tester.tap(_grabOf('Alpha'));
    await tester.pumpAndSettle();
    expect(find.textContaining('It was not sent again.'), findsOneWidget);
    await tester.tap(_grabOf('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('Grab this result again?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(harness.server.sent, ['POST search']);

    await tester.tap(_grabOf('Alpha'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grab again'));
    await tester.pumpAndSettle();
    expect(harness.server.sent, ['POST search', 'POST search']);
  });

  testWidgets('keeps the results while the indexers are shown', (tester) async {
    final harness = await _open(tester);
    await _search(tester);
    harness.server.requests.clear();

    await tester.tap(find.widgetWithText(Tab, 'Indexers'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Search'));
    await tester.pumpAndSettle();

    expect(find.byType(ReleaseRow), findsNWidgets(3));
    expect(harness.server.sent, isNot(contains('GET search')));
  });

  testWidgets('nothing is grabbed from results being searched again', (
    tester,
  ) async {
    final server = _Server();
    await _open(tester, server: server);
    await _search(tester);
    server.held['GET search'] = Completer();

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.enterText(find.byType(TextField), 'a');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(tester.widget<TextButton>(_grabOf('Alpha')).onPressed, isNull);
    server.held.remove('GET search')!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(_grabOf('Alpha')).onPressed, isNotNull);
  });

  testWidgets('lists the indexers read only, with what is known of failures', (
    tester,
  ) async {
    final harness = await _open(tester);
    final indexers = records(fixture('indexer'));
    indexers.first['enable'] = false;
    harness.server.routes['GET indexer'] = jsonAnswer(indexers);
    harness.server.routes['GET indexerstatus'] = jsonAnswer([
      {
        'indexerId': 2,
        'disabledTill': '2999-01-01T00:00:00Z',
        'mostRecentFailure': '2026-11-26T21:34:29Z',
      },
    ]);

    await tester.tap(find.widgetWithText(Tab, 'Indexers'));
    await tester.pumpAndSettle();

    expect(find.textContaining('may still have failed'), findsOneWidget);
    expect(find.text('Turned off in Prowlarr'), findsOneWidget);
    expect(find.text('Turned on'), findsOneWidget);
    expect(find.textContaining('Paused after failures'), findsOneWidget);
    expect(find.textContaining('Last failure: '), findsOneWidget);
    expect(
      harness.server.requests.map((request) => request.method),
      everyElement(HttpMethod.get),
    );

    // A refresh that fails keeps what was read, and says so.
    harness.server.down = failedAnswer(const Unreachable());
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.byType(StaleNotice), findsOneWidget);
    expect(find.text('Turned on'), findsOneWidget);
  });

  testWidgets('fits large text on a small phone and is labelled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, size: const Size(320, 640), textScale: 2);
    await _search(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(FilterChip), findsNothing);
    await tester.tap(find.widgetWithText(Tab, 'Indexers'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
