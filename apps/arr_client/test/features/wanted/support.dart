/// The wanted screen over fake services whose lists the test sets.
library;

import 'dart:async';

import 'package:arr_client/app/localization.dart';
import 'package:arr_client/app/providers.dart';
import 'package:arr_client/features/wanted/wanted_screen.dart';
import 'package:arr_client/src/l10n/generated/app_localizations.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/support.dart';

/// What one instance's server has, and what it was sent.
class FakeServer {
  /// The missing list, page by page.
  var missing = <List<LibraryItem>>[[]];

  /// The cutoff unmet list, page by page.
  var cutoff = <List<LibraryItem>>[[]];

  /// Every read fails with this while set.
  ServiceFailure? failure;

  /// The read of this page fails.
  int? failingPage;

  /// Reads wait for this while set.
  Completer<void>? held;

  /// The pages of the missing list that were read.
  final reads = <int>[];

  /// The remote ids of each search sent.
  final searches = <List<int>>[];

  /// How a search is answered.
  Result<Command, ServiceFailure> answer = const Ok(
    Command(id: 1, name: 'Search', status: CommandStatus.queued),
  );

  /// Searches wait for this while set.
  Completer<void>? sending;
}

class _Wanted implements WantedProvider {
  _Wanted(this.server);

  final FakeServer server;

  Future<Result<ResultPage<LibraryItem>, ServiceFailure>> _page(
    List<List<LibraryItem>> pages,
    int page,
  ) async {
    await server.held?.future;
    final failure =
        server.failure ??
        (server.failingPage == page ? const Unreachable() : null);
    if (failure != null) return Err(failure);
    return Ok(
      ResultPage(
        items: pages[page - 1],
        page: page,
        hasMore: page < pages.length,
      ),
    );
  }

  @override
  ServiceResult<ResultPage<LibraryItem>> missing({int page = 1}) {
    server.reads.add(page);
    return _page(server.missing, page);
  }

  @override
  ServiceResult<ResultPage<LibraryItem>> cutoffUnmet({int page = 1}) =>
      _page(server.cutoff, page);
}

class _Commands implements CommandProvider {
  _Commands(this.server);

  final FakeServer server;

  @override
  bool supports(CommandAction action, MediaTarget target) => true;

  @override
  ServiceResult<Command> search(List<MediaTarget> targets) async {
    server.searches.add([for (final target in targets) target.item.remoteId]);
    await server.sending?.future;
    return server.answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WantedModule extends FakeModule {
  _WantedModule({required bool commands})
    : super(
        'wanted',
        offers: {CapabilityKind.wanted, if (commands) CapabilityKind.command},
      );

  /// By instance name.
  final servers = <String, FakeServer>{};

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final server = servers.putIfAbsent(context.instance.name, FakeServer.new);
    final Capability? found = switch (T) {
      const (WantedProvider) => _Wanted(server),
      const (CommandProvider) => _Commands(server),
      _ => null,
    };
    return found as T?;
  }
}

/// The wanted screen of an app with one instance for each of [names].
class WantedHarness {
  WantedHarness._(this.app, this._module, this.ids);

  final TestApp app;
  final _WantedModule _module;

  /// Instance ids by name.
  final Map<String, String> ids;

  FakeServer server(String name) =>
      _module.servers.putIfAbsent(name, FakeServer.new);

  static Future<WantedHarness> start(
    WidgetTester tester, {
    List<String> names = const ['Films', 'Shows'],
    bool commands = true,
    Size size = const Size(400, 800),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final module = _WantedModule(commands: commands);
    final app = await TestApp.start(tester, modules: [module]);
    final ids = {for (final name in names) name: await app.add(module, name)};
    return WantedHarness._(app, module, ids);
  }

  /// As an item's own screen has it done once the server no longer has it.
  Future<void> removed(String name, MediaKind kind, int id) =>
      app.services.cache.scope(ids[name]!).remove(kind, id);

  Movie movie(
    String name,
    int id, {
    String? title,
    ItemState state = ItemState.missing,
  }) => Movie(
    ref: ItemRef(instanceId: ids[name]!, kind: MediaKind.movie, remoteId: id),
    title: title ?? 'Film $id',
    sortTitle: title ?? 'film $id',
    year: 2020,
    monitored: true,
    state: state,
  );

  Episode episode(String name, int id, {String title = 'Pilot'}) => Episode(
    ref: ItemRef(instanceId: ids[name]!, kind: MediaKind.episode, remoteId: id),
    title: title,
    sortTitle: '$id',
    parentTitle: 'The Show',
    parent: ItemRef(
      instanceId: ids[name]!,
      kind: MediaKind.series,
      remoteId: 9,
    ),
    monitored: true,
    state: ItemState.missing,
    seasonNumber: 1,
    episodeNumber: id,
    hasFile: false,
    airDateUtc: DateTime.utc(2026, 3, 4, 12),
  );

  Future<void> pump(
    WidgetTester tester, {
    double textScale = 1,
    bool settle = true,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => const WantedScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(app.services)],
        retry: (_, _) => null,
        child: MaterialApp.router(
          theme: ArrTheme.light(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          routerConfig: router,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await step(tester);
    }
  }

  Future<void> stop(WidgetTester tester) => app.stop(tester);
}

/// Lets reads and transitions finish while a progress bar keeps moving.
Future<void> step(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
