/// The pre-add details and the add sheet (spec story 3).
library;

import 'dart:async';

import 'package:arr_client/app/navigation/locations.dart';
import 'package:arr_client/features/search/add_request.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/fake_library.dart';
import '../../app/navigation_test.dart' show usePhone;
import '../../app/support.dart';

const _title = 'Alien';

/// What a fake instance was asked, and what it answers.
class _Server {
  _Server(this.kind);

  final MediaKind kind;

  /// What the instance has, as `find` reports it.
  int? held;

  ServiceFailure? findFailure;
  ServiceFailure? optionsFailure;

  List<ServerOption> options = [
    const ServerOption(
      kind: ServerOptionKind.rootFolder,
      id: 1,
      label: '/data/first',
      freeSpace: 1073741824,
    ),
    const ServerOption(
      kind: ServerOptionKind.rootFolder,
      id: 2,
      label: '/data/second',
    ),
    const ServerOption(
      kind: ServerOptionKind.qualityProfile,
      id: 3,
      label: 'Any',
    ),
    const ServerOption(
      kind: ServerOptionKind.qualityProfile,
      id: 4,
      label: 'HD',
    ),
    const ServerOption(kind: ServerOptionKind.tag, id: 7, label: 'kids'),
  ];

  var found = 0;
  var askedOptions = 0;
  final added = <(AddCandidate, AddChoices)>[];

  /// While set, `add` waits for it.
  Completer<void>? gate;

  /// How `add` fails; null while it succeeds.
  ServiceFailure? addFailure;

  /// Run when `add` is called, before it answers.
  void Function()? onAdd;
}

class _Lookup implements LookupProvider {
  _Lookup(this.server, this.instanceId);

  final _Server server;
  final String instanceId;

  ItemRef _ref(int id) =>
      ItemRef(instanceId: instanceId, kind: server.kind, remoteId: id);

  @override
  Set<MediaKind> get itemKinds => {server.kind};

  @override
  ServiceResult<List<AddCandidate>> lookup(String term) async => const Ok([]);

  @override
  ServiceResult<AddCandidate> find(AddCandidate candidate) async {
    server.found++;
    if (server.findFailure case final failure?) return Err(failure);
    return Ok(
      AddCandidate(
        kind: server.kind,
        title: candidate.title,
        externalIds: candidate.externalIds,
        existingRefs: [if (server.held case final id?) _ref(id)],
        sourceByInstance: {
          instanceId: {'foundThere': true},
        },
      ),
    );
  }

  @override
  ServiceResult<AddOptions> addOptions(MediaKind kind) async {
    server.askedOptions++;
    if (server.optionsFailure case final failure?) return Err(failure);
    return Ok(
      AddOptions(
        serverOptions: server.options,
        monitorOptions: [
          MonitorOption(id: 'first', label: (_) => 'Monitor first'),
          MonitorOption(id: 'second', label: (_) => 'Monitor second'),
        ],
      ),
    );
  }

  @override
  ServiceResult<ItemRef> add(AddCandidate candidate, AddChoices choices) async {
    server.added.add((candidate, choices));
    server.onAdd?.call();
    await server.gate?.future;
    return switch (server.addFailure) {
      null => Ok(_ref(42)),
      final failure => Err(failure),
    };
  }
}

class _Module extends FakeModule {
  _Module(super.id, this.servers, {super.itemKind})
    : super(offers: {CapabilityKind.library, CapabilityKind.lookup});

  final Map<String, _Server> servers;

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final server = servers.putIfAbsent(
      context.instance.name,
      () => _Server(itemKind),
    );
    final Capability? found = switch (T) {
      const (LookupProvider) => _Lookup(server, context.instance.id),
      const (LibraryProvider) =>
        FakeLibrary(itemKind: itemKind)
          ..route = (ref) => ModuleRoute(
            instanceId: ref.instanceId,
            path: '$id/items/${ref.remoteId}',
          ),
      _ => null,
    };
    return found as T?;
  }
}

class _Add {
  _Add._(this.app, this.servers);

  final TestApp app;
  final Map<String, _Server> servers;
  final ids = <String, String>{};

  static Future<_Add> start(
    WidgetTester tester, {
    List<String> films = const ['Films'],
    List<String> shows = const [],
    Size size = const Size(400, 800),
  }) async {
    usePhone(tester, size);
    final servers = <String, _Server>{};
    final movies = _Module('movies', servers);
    final series = _Module('shows', servers, itemKind: MediaKind.series);
    final app = await TestApp.start(tester, modules: [movies, series]);
    final add = _Add._(app, servers);
    for (final name in films) {
      add.ids[name] = await app.add(movies, name);
      servers.putIfAbsent(name, () => _Server(MediaKind.movie));
    }
    for (final name in shows) {
      add.ids[name] = await app.add(series, name);
      servers.putIfAbsent(name, () => _Server(MediaKind.series));
    }
    await app.pump(tester);
    return add;
  }

  _Server operator [](String name) => servers[name]!;

  /// A title that the searches of [searched] gave, and [held] have.
  AddCandidate candidate({
    List<String> searched = const ['Films'],
    List<String> held = const [],
    MediaKind kind = MediaKind.movie,
  }) => AddCandidate(
    kind: kind,
    title: _title,
    year: 1979,
    overview: 'The crew of a ship answers a signal.',
    externalIds: const ExternalIds(tmdbId: 1, tvdbId: 2),
    existingRefs: [
      for (final name in held)
        ItemRef(instanceId: ids[name]!, kind: kind, remoteId: 5),
    ],
    sourceByInstance: {
      for (final name in searched) ids[name]!: {'searched': true},
    },
  );

  Future<void> open(WidgetTester tester, [AddCandidate? candidate]) async {
    unawaited(
      app.services.navigator.router!.push<void>(
        addLocation,
        extra: AddRequest(candidate ?? this.candidate()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<AddChoices?> remembered(WidgetTester tester, String name) async {
    AddChoices? choices;
    var read = false;
    unawaited(
      app.services.preferences.lastAddChoices(ids[name]!).then((value) {
        choices = value;
        read = true;
      }),
    );
    await settle(tester, until: () => read);
    return choices;
  }

  Future<void> stop(WidgetTester tester) => app.stop(tester);
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
}

Finder _button(String text) => find.widgetWithText(FilledButton, text);

bool _enabled(WidgetTester tester, String text) =>
    tester.widget<FilledButton>(_button(text)).onPressed != null;

/// Scrolls to [finder] in the sheet and taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Presses Add and lets the answer, and the saving after it, arrive.
Future<void> _send(WidgetTester tester, String name) async {
  await tester.tap(_button('Add to $name'));
  await settle(tester);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String from, String to) async {
  await _tap(tester, find.text(from));
  await tester.tap(find.text(to).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the details are shown before adding', (tester) async {
    final add = await _Add.start(tester);
    await add.open(tester);

    expect(find.text(_title), findsOneWidget);
    expect(find.text('1979'), findsOneWidget);
    expect(find.textContaining('answers a signal'), findsOneWidget);
    expect(find.text('Already added'), findsNothing);
    expect(add['Films'].askedOptions, 0);
    await add.stop(tester);
  });

  testWidgets('adds with the first choices and remembers them', (tester) async {
    final add = await _Add.start(tester);
    await add.open(tester);
    await _openSheet(tester);

    expect(find.text('/data/first (1.0 GiB free)'), findsOneWidget);
    expect(find.text('Released'), findsOneWidget);
    // The search of this instance gave the title: it is not looked up again.
    expect(add['Films'].found, 0);

    await _send(tester, 'Films');

    final (candidate, choices) = add['Films'].added.single;
    expect(candidate.sourceByInstance[add.ids['Films']], {'searched': true});
    expect(choices.rootFolderId, 1);
    expect(choices.qualityProfileId, 3);
    expect(choices.monitorOptionId, 'first');
    expect(choices.searchNow, isTrue);
    expect(choices.minimumAvailability, MinimumAvailability.released);
    expect(choices.seriesType, isNull);
    expect(choices.seasonFolder, isNull);
    expect(choices.tagIds, isEmpty);
    expect(find.text('Added to Films.'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Open in Films'), findsOneWidget);
    expect(_button('Add'), findsNothing);
    expect((await add.remembered(tester, 'Films'))?.qualityProfileId, 3);

    await _tap(tester, find.text('Open in Films'));
    expect(find.text('Films item 42 null'), findsOneWidget);
    await add.stop(tester);
  });

  testWidgets('sends what was chosen and preselects it next time', (
    tester,
  ) async {
    final add = await _Add.start(tester);
    await add.open(tester);
    await _openSheet(tester);

    await _choose(tester, '/data/first (1.0 GiB free)', '/data/second');
    await _choose(tester, 'Any', 'HD');
    await _choose(tester, 'Monitor first', 'Monitor second');
    await _choose(tester, 'Released', 'In cinemas');
    await _tap(tester, find.text('Search for it now'));
    await _tap(tester, find.text('kids'));
    await _send(tester, 'Films');

    final (_, choices) = add['Films'].added.single;
    expect(choices.rootFolderId, 2);
    expect(choices.qualityProfileId, 4);
    expect(choices.monitorOptionId, 'second');
    expect(choices.minimumAvailability, MinimumAvailability.inCinemas);
    expect(choices.searchNow, isFalse);
    expect(choices.tagIds, {7});

    // The profile chosen before is gone from the server meanwhile.
    add['Films'].options.removeWhere((option) => option.label == 'HD');
    add.app.services.navigator.router!.pop();
    await tester.pumpAndSettle();
    await add.open(tester);
    // Sent before: the instance is asked what it has by now.
    await _openSheet(tester);

    expect(add['Films'].found, 1);
    expect(find.text('/data/second'), findsOneWidget);
    expect(find.text('Any'), findsOneWidget);
    expect(find.text('Monitor second'), findsOneWidget);
    expect(find.text('In cinemas'), findsOneWidget);
    await add.stop(tester);
  });

  testWidgets('a later visit does not offer what was added', (tester) async {
    final add = await _Add.start(tester, films: ['Films', 'Films 4K']);
    await add.open(tester);
    await _openSheet(tester);
    await _send(tester, 'Films');
    add['Films'].held = 42;

    // Another instance is offered next.
    await _openSheet(tester);
    expect(_button('Add to Films 4K'), findsOneWidget);
    add.app.services.navigator.router!.pop();
    await tester.pumpAndSettle();
    add.app.services.navigator.router!.pop();
    await tester.pumpAndSettle();

    // The search result is as it was, from before the add.
    await add.open(tester);
    expect(find.text('Already added'), findsOneWidget);
    expect(find.text('Open in Films'), findsOneWidget);
    expect(add['Films'].added, hasLength(1));
    await add.stop(tester);
  });

  testWidgets('a series has a type and season folders', (tester) async {
    final add = await _Add.start(tester, films: [], shows: ['Shows']);
    await add.open(
      tester,
      add.candidate(searched: ['Shows'], kind: MediaKind.series),
    );
    await _openSheet(tester);

    expect(find.text('Minimum availability'), findsNothing);
    await _choose(tester, 'Standard', 'Anime');
    await _tap(tester, find.text('Use season folders'));
    await _send(tester, 'Shows');

    final (_, choices) = add['Shows'].added.single;
    expect(choices.seriesType, SeriesType.anime);
    expect(choices.seasonFolder, isFalse);
    expect(choices.searchNow, isFalse);
    expect(choices.minimumAvailability, isNull);
    await add.stop(tester);
  });

  testWidgets('an instance that has it offers to open it; another takes it', (
    tester,
  ) async {
    final add = await _Add.start(tester, films: ['Films', 'Films 4K']);
    await add.open(tester, add.candidate(held: ['Films']));

    expect(find.text('Already added'), findsOneWidget);
    expect(find.text('Open in Films'), findsOneWidget);
    await _openSheet(tester);

    // The one that does not have it is chosen, and looks the title up itself.
    expect(add['Films 4K'].found, 1);
    expect(add['Films'].askedOptions, 0);
    await _choose(tester, 'Films 4K', 'Films (already has it)');
    expect(find.text('Films already has Alien.'), findsOneWidget);
    expect(find.textContaining('Add to'), findsNothing);

    await _choose(tester, 'Films (already has it)', 'Films 4K');
    await _send(tester, 'Films 4K');

    final (candidate, _) = add['Films 4K'].added.single;
    expect(candidate.sourceByInstance, {
      add.ids['Films 4K']: {'foundThere': true},
    });
    expect(add['Films'].added, isEmpty);
    await add.stop(tester);
  });

  testWidgets('when every instance has it there is nothing to add', (
    tester,
  ) async {
    final add = await _Add.start(tester);
    await add.open(tester, add.candidate(held: ['Films']));

    expect(_button('Add'), findsNothing);
    expect(find.textContaining('already has it'), findsOneWidget);
    await add.stop(tester);
  });

  testWidgets('without a service that can add it says so', (tester) async {
    final add = await _Add.start(tester);
    await add.open(tester, add.candidate(searched: [], kind: MediaKind.series));

    expect(find.textContaining('No service in this profile'), findsOneWidget);
    expect(_button('Add'), findsNothing);
    await add.stop(tester);
  });

  testWidgets('a lookup that fails can be retried', (tester) async {
    final add = await _Add.start(tester);
    add['Films'].findFailure = const NotFound();
    await add.open(tester, add.candidate(searched: []));
    await _openSheet(tester);

    expect(find.text('Films could not find this title.'), findsOneWidget);
    add['Films'].findFailure = const Unreachable();
    await _tap(tester, find.text('Retry'));
    expect(find.textContaining('did not answer'), findsOneWidget);

    add['Films'].findFailure = null;
    add['Films'].optionsFailure = const AuthFailed();
    await _tap(tester, find.text('Retry'));
    expect(find.textContaining('sign-in was rejected'), findsOneWidget);

    add['Films'].optionsFailure = null;
    await _tap(tester, find.text('Retry'));
    expect(_enabled(tester, 'Add to Films'), isTrue);
    await add.stop(tester);
  });

  testWidgets('without a root folder nothing can be added', (tester) async {
    final add = await _Add.start(tester);
    add['Films'].options.removeWhere(
      (option) => option.kind == ServerOptionKind.rootFolder,
    );
    await add.open(tester);
    await _openSheet(tester);

    expect(find.textContaining('no root folder'), findsOneWidget);
    expect(_enabled(tester, 'Add to Films'), isFalse);
    await add.stop(tester);
  });

  testWidgets('a double tap sends once', (tester) async {
    final add = await _Add.start(tester);
    final gate = add['Films'].gate = Completer<void>();
    await add.open(tester);
    await _openSheet(tester);

    await tester.tap(_button('Add to Films'));
    await tester.tap(_button('Add to Films'));
    await tester.pump();
    expect(_enabled(tester, 'Adding to Films'), isFalse);
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byType(DropdownButton<String>).first,
          )
          .onChanged,
      isNull,
    );

    gate.complete();
    await settle(tester);
    await tester.pumpAndSettle();
    expect(add['Films'].added, hasLength(1));
    await add.stop(tester);
  });

  testWidgets('leaving while it is sent neither sends again nor loses the '
      'outcome', (tester) async {
    final add = await _Add.start(tester);
    final gate = add['Films'].gate = Completer<void>();
    await add.open(tester);
    await _openSheet(tester);
    await tester.tap(_button('Add to Films'));
    await tester.pump();

    // Back from the sheet, then from the screen, and in again.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    await add.open(tester);
    await tester.tap(_button('Add'));
    // The bar of what is being sent never settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_enabled(tester, 'Adding to Films'), isFalse);

    // The server has it once the add is answered.
    add['Films'].held = 42;
    gate.complete();
    await settle(tester);
    await tester.pumpAndSettle();

    expect(add['Films'].added, hasLength(1));
    expect(find.text('Films already has Alien.'), findsOneWidget);
    expect((await add.remembered(tester, 'Films'))?.rootFolderId, 1);
    await add.stop(tester);
  });

  testWidgets('a failure after the sheet is closed is still told', (
    tester,
  ) async {
    final add = await _Add.start(tester);
    final gate = add['Films'].gate = Completer<void>();
    add['Films'].addFailure = const Unreachable();
    await add.open(tester);
    await _openSheet(tester);
    await tester.tap(_button('Add to Films'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));

    gate.complete();
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Films: The server did not'), findsOneWidget);
    await add.stop(tester);
  });

  testWidgets('added elsewhere meanwhile: says so and offers to open', (
    tester,
  ) async {
    final add = await _Add.start(tester);
    add['Films'].addFailure = const Conflict();
    add['Films'].onAdd = () => add['Films'].held = 9;
    await add.open(tester);
    await _openSheet(tester);
    await _send(tester, 'Films');

    expect(find.text('Films already has Alien.'), findsOneWidget);
    expect(add['Films'].added, hasLength(1));
    // A refused add is not a choice to remember.
    expect(await add.remembered(tester, 'Films'), isNull);

    await _tap(tester, find.widgetWithText(FilledButton, 'Open in Films'));
    expect(find.text('Films item 9 null'), findsOneWidget);
    add.app.services.navigator.router!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Already added'), findsOneWidget);
    await add.stop(tester);
  });

  testWidgets('a conflict about something else is said as such', (
    tester,
  ) async {
    final add = await _Add.start(tester);
    add['Films'].addFailure = const Conflict();
    await add.open(tester);
    await _openSheet(tester);
    await _send(tester, 'Films');

    expect(find.textContaining('clashes with'), findsOneWidget);
    expect(add['Films'].added, hasLength(1));
    await add.stop(tester);
  });

  testWidgets('an unknown outcome is reported, checked and not sent again', (
    tester,
  ) async {
    final add = await _Add.start(tester);
    add['Films'].addFailure = const OutcomeUnknown();
    await add.open(tester);
    await _openSheet(tester);
    await _send(tester, 'Films');

    expect(find.textContaining('may or may not'), findsOneWidget);
    expect(find.textContaining('does not list it yet'), findsOneWidget);
    expect(add['Films'].found, 1);
    expect(add['Films'].added, hasLength(1));
    // Only the user sends it again.
    expect(_enabled(tester, 'Add to Films'), isTrue);
    await add.stop(tester);
  });

  testWidgets('an unknown outcome that did add it offers to open it', (
    tester,
  ) async {
    final add = await _Add.start(tester);
    add['Films'].addFailure = const OutcomeUnknown();
    add['Films'].onAdd = () => add['Films'].held = 11;
    await add.open(tester);
    await _openSheet(tester);
    await _send(tester, 'Films');

    expect(find.text('Alien is on Films now.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open in Films'), findsOneWidget);
    expect(add['Films'].added, hasLength(1));
    await add.stop(tester);
  });

  testWidgets('an unknown outcome that cannot be checked offers no add', (
    tester,
  ) async {
    final add = await _Add.start(tester);
    add['Films'].addFailure = const OutcomeUnknown();
    add['Films'].findFailure = const Unreachable();
    await add.open(tester);
    await _openSheet(tester);
    await _send(tester, 'Films');

    expect(find.textContaining('may or may not'), findsOneWidget);
    expect(find.textContaining('did not answer'), findsOneWidget);
    expect(find.textContaining('Add to'), findsNothing);

    add['Films'].findFailure = null;
    await _tap(tester, find.text('Retry'));
    expect(find.textContaining('may or may not'), findsOneWidget);
    expect(_enabled(tester, 'Add to Films'), isTrue);
    expect(add['Films'].added, hasLength(1));
    await add.stop(tester);
  });

  testWidgets('refused values: the choices are read again and kept', (
    tester,
  ) async {
    final add = await _Add.start(tester);
    add['Films'].addFailure = const Validation([]);
    add['Films'].onAdd = () =>
        add['Films'].options.removeWhere((option) => option.id == 1);
    await add.open(tester);
    await _openSheet(tester);
    await _choose(tester, 'Any', 'HD');
    await _send(tester, 'Films');

    expect(find.textContaining('rejected the values'), findsOneWidget);
    expect(find.text('/data/second'), findsOneWidget);
    expect(find.text('HD'), findsOneWidget);
    expect(add['Films'].askedOptions, 2);
    await add.stop(tester);
  });

  testWidgets('works at 200% text and says what its controls are', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final add = await _Add.start(
      tester,
      films: ['Films', 'A server with a rather long name'],
      size: const Size(320, 640),
    );
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await add.open(tester, add.candidate(held: ['Films']));
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

    await _openSheet(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Search for it now'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(_button('Add to A server with a rather long name'), findsOneWidget);
    semantics.dispose();
    await add.stop(tester);
  });
}
