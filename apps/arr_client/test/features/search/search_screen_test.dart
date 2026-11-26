/// The app-wide search (spec story 3).
library;

import 'dart:async';

import 'package:arr_client/features/search/add_request.dart';
import 'package:arr_client/features/search/search_notifier.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation_test.dart' show usePhone;
import '../../app/support.dart';

/// One question a fake service was asked, to be answered by the test.
class Question {
  Question(this.term);

  final String term;
  final _answer = Completer<Result<Object, ServiceFailure>>();
}

/// What the fake services of one instance were asked.
class Server {
  final asked = <Question>[];

  List<String> get terms => [for (final question in asked) question.term];

  void answer(List<AddCandidate> found) =>
      asked.last._answer.complete(Ok(found));

  void answerTitles(List<DiscoveryTitle> found) => asked.last._answer.complete(
    Ok(ResultPage(items: found, page: 1, hasMore: false)),
  );

  void fail([ServiceFailure failure = const Unreachable()]) =>
      asked.last._answer.complete(Err(failure));
}

class _Lookup implements LookupProvider {
  _Lookup(this.server, this.kind);

  final Server server;
  final MediaKind kind;

  @override
  Set<MediaKind> get itemKinds => {kind};

  @override
  ServiceResult<List<AddCandidate>> lookup(String term) async {
    final question = Question(term);
    server.asked.add(question);
    return switch (await question._answer.future) {
      Ok(:final value) => Ok(value as List<AddCandidate>),
      Err(:final error) => Err(error),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Discovery implements DiscoveryProvider {
  _Discovery(this.server, this.instanceId);

  final Server server;
  final String instanceId;

  @override
  ServiceResult<ResultPage<DiscoveryTitle>> search(
    String term, {
    int page = 1,
  }) async {
    final question = Question(term);
    server.asked.add(question);
    return switch (await question._answer.future) {
      Ok(:final value) => Ok(value as ResultPage<DiscoveryTitle>),
      Err(:final error) => Err(error),
    };
  }

  @override
  ModuleRoute detailRoute(DiscoveryTitle title) => ModuleRoute(
    instanceId: instanceId,
    path: 'requests/items/${title.tmdbId}',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A service that is searched. Each instance answers from the [Server] of its
/// name.
class SearchModule extends FakeModule {
  SearchModule(super.id, this.servers, {super.itemKind, bool discovery = false})
    : super(
        offers: {discovery ? CapabilityKind.discovery : CapabilityKind.lookup},
      );

  final Map<String, Server> servers;

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final server = servers.putIfAbsent(context.instance.name, Server.new);
    final Capability? found = switch (T) {
      const (LookupProvider) => _Lookup(server, itemKind),
      const (DiscoveryProvider) => _Discovery(server, context.instance.id),
      _ => null,
    };
    return found as T?;
  }
}

/// Servers by instance name, a running app and its search screen.
class Search {
  Search._(this.app, this.servers, this.modules);

  final TestApp app;
  final Map<String, Server> servers;
  final Map<String, SearchModule> modules;

  /// The id of each instance by name.
  final ids = <String, String>{};

  static Future<Search> start(
    WidgetTester tester, {
    Map<String, String> instances = const {
      'Films': 'movies',
      'Films 4K': 'movies',
      'Shows': 'shows',
    },
    Size size = const Size(400, 800),
  }) async {
    usePhone(tester, size);
    final servers = <String, Server>{};
    final modules = {
      'movies': SearchModule('movies', servers),
      'shows': SearchModule('shows', servers, itemKind: MediaKind.series),
      'requests': SearchModule('requests', servers, discovery: true),
    };
    final app = await TestApp.start(tester, modules: modules.values);
    final search = Search._(app, servers, modules);
    for (final MapEntry(key: name, value: module) in instances.entries) {
      search.ids[name] = await app.add(modules[module]!, name);
    }
    await app.pump(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    return search;
  }

  Server operator [](String name) => servers[name]!;

  ItemRef held(String instance, [MediaKind kind = MediaKind.movie]) =>
      ItemRef(instanceId: ids[instance]!, kind: kind, remoteId: 5);

  AddCandidate movie(
    String instance,
    String title,
    int tmdb, {
    bool inLibrary = false,
    List<MediaImage> images = const [],
  }) => AddCandidate(
    kind: MediaKind.movie,
    title: title,
    year: 1979,
    overview: 'The crew of a ship answers a signal.',
    externalIds: ExternalIds(tmdbId: tmdb),
    images: images,
    existingRefs: [if (inLibrary) held(instance)],
    sourceByInstance: {
      ids[instance]!: {'tmdbId': tmdb},
    },
  );

  AddCandidate series(String instance, String title, int tvdb) => AddCandidate(
    kind: MediaKind.series,
    title: title,
    externalIds: ExternalIds(tvdbId: tvdb),
    sourceByInstance: {
      ids[instance]!: {'tvdbId': tvdb},
    },
  );

  Future<void> stop(WidgetTester tester) => app.stop(tester);
}

/// The progress bar never settles while a service has yet to answer.
Future<void> step(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> typeAndWait(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(searchDebounce);
  await step(tester);
}

Finder tab(String text) => find.widgetWithText(Tab, text);

DiscoveryTitle title(String name, int tmdb) => DiscoveryTitle(
  tmdbId: tmdb,
  mediaType: DiscoveryMediaType.movie,
  title: name,
  availability: Availability.unknown,
  availability4k: Availability.unknown,
);

void main() {
  testWidgets('typing is searched once it pauses', (tester) async {
    final search = await Search.start(tester);
    expect(find.textContaining('Type a name'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'al');
    await tester.pump(searchDebounce ~/ 2);
    await tester.enterText(find.byType(TextField), 'alien');
    await tester.pump(searchDebounce ~/ 2);
    expect(search['Films'].asked, isEmpty);
    await tester.pump(searchDebounce ~/ 2);

    for (final server in ['Films', 'Films 4K', 'Shows']) {
      expect(search[server].terms, ['alien'], reason: server);
    }
    await search.stop(tester);
  });

  testWidgets('one character is searched only when submitted', (tester) async {
    final search = await Search.start(tester);

    await typeAndWait(tester, 'm');
    expect(search['Films'].asked, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await step(tester);

    expect(search['Films'].terms, ['m']);
    await search.stop(tester);
  });

  testWidgets('results are grouped by type, merged and marked', (tester) async {
    final search = await Search.start(tester);
    await typeAndWait(tester, 'alien');

    search['Films'].answer([
      search.movie('Films', 'Alien', 1, inLibrary: true),
    ]);
    search['Films 4K'].answer([
      search.movie('Films 4K', 'Alien', 1, inLibrary: true),
      search.movie('Films 4K', 'Aliens', 2),
    ]);
    search['Shows'].answer([search.series('Shows', 'Alien: Earth', 7)]);
    await tester.pumpAndSettle();

    expect(tab('Movies (2)'), findsOneWidget);
    expect(tab('Series (1)'), findsOneWidget);
    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('In Films, Films 4K'), findsOneWidget);
    expect(find.text('Aliens'), findsOneWidget);
    expect(find.textContaining('In Films'), findsOneWidget);
    expect(find.text('1979'), findsNWidgets(2));
    expect(find.text('Alien: Earth'), findsNothing);
    expect(find.bySemanticsLabel('3 results'), findsOneWidget);

    await tester.tap(tab('Series (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Alien: Earth'), findsOneWidget);
    await search.stop(tester);
  });

  testWidgets('results appear as they arrive and stay where they are', (
    tester,
  ) async {
    final search = await Search.start(tester);
    await typeAndWait(tester, 'alien');

    search['Films 4K'].answer([search.movie('Films 4K', 'Aliens', 2)]);
    await step(tester);
    expect(find.text('Aliens'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final first = tester.getTopLeft(find.text('Aliens'));

    // The instance listed first answers last, with another title on top.
    search['Films'].answer([
      search.movie('Films', 'Alien', 1),
      search.movie('Films', 'Aliens', 2, inLibrary: true),
    ]);
    search['Shows'].answer([]);
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Aliens')), first);
    expect(tester.getTopLeft(find.text('Alien')).dy, greaterThan(first.dy));
    expect(find.text('In Films'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await search.stop(tester);
  });

  testWidgets('a mark that arrives later does not move the next row', (
    tester,
  ) async {
    final search = await Search.start(tester);
    await typeAndWait(tester, 'alien');
    search['Films'].answer([
      search.movie('Films', 'Alien', 1),
      search.movie('Films', 'Aliens', 2),
    ]);
    await step(tester);
    final second = tester.getTopLeft(find.text('Aliens'));

    search['Films 4K'].answer([
      search.movie('Films 4K', 'Alien', 1, inLibrary: true),
    ]);
    await step(tester);

    expect(find.text('In Films 4K'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Aliens')), second);
    await search.stop(tester);
  });

  testWidgets('what a replaced search answers late is dropped', (tester) async {
    final search = await Search.start(tester, instances: {'Films': 'movies'});
    await typeAndWait(tester, 'alien');
    await typeAndWait(tester, 'heat');
    final server = search['Films'];
    expect(server.terms, ['alien', 'heat']);

    server.answer([search.movie('Films', 'Heat', 2)]);
    await tester.pumpAndSettle();
    server.asked.first._answer.complete(
      Ok([search.movie('Films', 'Alien', 1)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Heat'), findsOneWidget);
    expect(find.text('Alien'), findsNothing);
    await search.stop(tester);
  });

  testWidgets('clearing the field drops the results and what is under way', (
    tester,
  ) async {
    final search = await Search.start(tester, instances: {'Films': 'movies'});
    await typeAndWait(tester, 'alien');

    await tester.tap(find.byTooltip('Clear search'));
    await step(tester);
    search['Films'].answer([search.movie('Films', 'Alien', 1)]);
    await tester.pumpAndSettle();

    expect(find.textContaining('Type a name'), findsOneWidget);
    expect(find.text('Alien'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await search.stop(tester);
  });

  testWidgets('a failed service is named beside what the others gave', (
    tester,
  ) async {
    final search = await Search.start(tester);
    await typeAndWait(tester, 'alien');
    search['Films'].answer([search.movie('Films', 'Alien', 1)]);
    search['Films 4K'].fail();
    search['Shows'].fail(const ServerError());
    await tester.pumpAndSettle();

    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('Films 4K could not be searched'), findsOneWidget);
    expect(find.text('Shows could not be searched'), findsOneWidget);
    await tester.tap(tab('Series (0)'));
    await tester.pumpAndSettle();
    expect(
      find.text('The services that answered found nothing for "alien".'),
      findsOneWidget,
    );
    await tester.tap(tab('Movies (1)'));
    await tester.pumpAndSettle();
    final place = tester.getTopLeft(find.text('Alien'));

    await tester.tap(find.byTooltip('Retry'));
    await step(tester);

    // Only those that failed are asked again.
    expect(search['Films'].asked, hasLength(1));
    expect(search['Films 4K'].terms, ['alien', 'alien']);
    expect(search['Shows'].terms, ['alien', 'alien']);
    expect(find.textContaining('could not be searched'), findsNothing);
    expect(tester.getTopLeft(find.text('Alien')), place);

    search['Films 4K'].answer([
      search.movie('Films 4K', 'Alien', 1, inLibrary: true),
    ]);
    search['Shows'].fail();
    await tester.pumpAndSettle();

    expect(find.text('In Films 4K'), findsOneWidget);
    expect(find.text('Films 4K could not be searched'), findsNothing);
    expect(find.text('Shows could not be searched'), findsOneWidget);
    await search.stop(tester);
  });

  testWidgets('nothing found says so', (tester) async {
    final search = await Search.start(tester, instances: {'Films': 'movies'});
    await typeAndWait(tester, 'zzz');
    search['Films'].answer([]);
    await tester.pumpAndSettle();

    expect(find.text('Nothing found for "zzz".'), findsOneWidget);
    // One type needs no tabs.
    expect(find.byType(TabBar), findsNothing);
    await search.stop(tester);
  });

  testWidgets('a result opens the add flow with every record of it', (
    tester,
  ) async {
    final search = await Search.start(tester);
    await typeAndWait(tester, 'alien');
    search['Films'].answer([
      search.movie('Films', 'Alien', 1, inLibrary: true),
    ]);
    search['Films 4K'].answer([search.movie('Films 4K', 'Alien', 1)]);
    search['Shows'].answer([]);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alien'));
    await tester.pumpAndSettle();

    final message = find.text('Adding Alien is not built yet.');
    final extra = GoRouterState.of(tester.element(message)).extra;
    final candidate = (extra! as AddRequest).candidate;
    expect(candidate.externalIds.tmdbId, 1);
    expect(
      candidate.sourceByInstance.keys,
      unorderedEquals([search.ids['Films'], search.ids['Films 4K']]),
    );
    expect(candidate.existingRefs, [search.held('Films')]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Alien'), findsOneWidget);
    expect(search['Films'].asked, hasLength(1));
    await search.stop(tester);
  });

  testWidgets('a request service merges by id; its own titles open there', (
    tester,
  ) async {
    final search = await Search.start(
      tester,
      instances: {'Films': 'movies', 'Wishes': 'requests'},
    );
    await typeAndWait(tester, 'alien');
    search['Wishes'].answerTitles([title('Alien', 1), title('Prometheus', 3)]);
    search['Films'].answer([search.movie('Films', 'Alien', 1)]);
    await tester.pumpAndSettle();

    expect(find.text('Alien'), findsOneWidget);
    expect(tab('Movies (2)'), findsOneWidget);
    expect(tab('Series (0)'), findsOneWidget);

    await tester.tap(find.text('Prometheus'));
    await tester.pumpAndSettle();
    // The request service's own screen of the title.
    expect(find.text('Wishes item 3 null'), findsOneWidget);
    search.app.services.navigator.router!.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alien'));
    await tester.pumpAndSettle();
    expect(find.text('Adding Alien is not built yet.'), findsOneWidget);
    await search.stop(tester);
  });

  testWidgets('artwork of another host follows the preference', (tester) async {
    final search = await Search.start(tester, instances: {'Films': 'movies'});
    await typeAndWait(tester, 'alien');
    search['Films'].answer([
      search.movie(
        'Films',
        'Alien',
        1,
        images: [
          MediaImage(
            type: MediaImageType.poster,
            remoteUrl: Uri.parse('https://images.invalid/alien.jpg'),
          ),
        ],
      ),
    ]);
    await step(tester);
    expect(find.byType(Image), findsOneWidget);

    await search.app.services.preferences.setLoadThirdPartyArtwork(false);
    await settle(tester);

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    // The cache of the first picture has a timer.
    await tester.pump(const Duration(seconds: 11));
    await search.stop(tester);
  });

  testWidgets('a removed instance is searched no longer', (tester) async {
    final search = await Search.start(tester);
    await typeAndWait(tester, 'alien');
    search['Films'].answer([search.movie('Films', 'Alien', 1)]);
    search['Films 4K'].answer([search.movie('Films 4K', 'Aliens', 2)]);
    search['Shows'].answer([]);
    await tester.pumpAndSettle();

    await search.app.services.profiles.deleteInstance(search.ids['Films 4K']!);
    await settle(tester);

    expect(search['Films'].terms, ['alien', 'alien']);
    expect(search['Films 4K'].asked, hasLength(1));
    expect(find.text('Aliens'), findsNothing);
    await search.stop(tester);
  });

  testWidgets('a change of connection state does not search again', (
    tester,
  ) async {
    final search = await Search.start(tester, instances: {'Films': 'movies'});
    await typeAndWait(tester, 'alien');
    search['Films'].answer([search.movie('Films', 'Alien', 1)]);
    await tester.pumpAndSettle();

    search.app.services.registry.resetConnections();
    await settle(tester);

    expect(search['Films'].asked, hasLength(1));
    expect(find.text('Alien'), findsOneWidget);
    await search.stop(tester);
  });

  testWidgets('another profile is searched instead', (tester) async {
    final search = await Search.start(tester, instances: {'Films': 'movies'});
    await typeAndWait(tester, 'alien');
    final away = await search.app.addProfile('Away');
    search.ids['Cabin'] = await search.app.add(
      search.modules['movies']!,
      'Cabin',
      profileId: away,
    );

    unawaited(search.app.services.registry.switchTo(away));
    await settle(tester);

    expect(search['Cabin'].terms, ['alien']);
    // What the old profile still answers is not shown.
    search['Films'].answer([search.movie('Films', 'Alien', 1)]);
    search['Cabin'].answer([search.movie('Cabin', 'Aliens', 2)]);
    await tester.pumpAndSettle();
    expect(find.text('Alien'), findsNothing);
    expect(find.text('Aliens'), findsOneWidget);
    await search.stop(tester);
  });

  testWidgets('leaving while searching is quiet', (tester) async {
    final search = await Search.start(tester, instances: {'Films': 'movies'});
    await typeAndWait(tester, 'alien');
    await tester.pageBack();
    await tester.pumpAndSettle();

    search['Films'].answer([search.movie('Films', 'Alien', 1)]);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await search.stop(tester);
  });

  testWidgets('large text fits a small phone, with targets and labels', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final semantics = tester.ensureSemantics();
    final search = await Search.start(tester, size: const Size(320, 640));
    await typeAndWait(tester, 'alien');
    search['Films'].answer([
      search.movie(
        'Films',
        'A title long enough to need more than one line of a small phone',
        1,
        inLibrary: true,
      ),
    ]);
    search['Films 4K'].fail();
    search['Shows'].fail();
    await tester.pumpAndSettle();
    // With the keyboard open.
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(
      find.bySemanticsLabel(RegExp('A title long.*In Films', dotAll: true)),
      findsOneWidget,
    );
    semantics.dispose();
    await search.stop(tester);
  });
}
