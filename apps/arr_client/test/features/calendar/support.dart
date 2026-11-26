/// The calendar over fake services whose releases and imports the test sets,
/// on a clock the test sets.
library;

import 'dart:async';

import 'package:arr_client/app/localization.dart';
import 'package:arr_client/app/providers.dart';
import 'package:arr_client/features/calendar/calendar_screen.dart';
import 'package:arr_client/features/calendar/today.dart';
import 'package:arr_client/src/l10n/generated/app_localizations.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/support.dart';

/// What one instance's server has.
class FakeServer {
  final releases = <CalendarEvent>[];

  /// By the local midnight of the day.
  final imports = <DateTime, List<ImportedItem>>{};

  /// Every read fails with this while set.
  ServiceFailure? failure;

  /// Reads wait for this while set.
  Completer<void>? held;

  /// Whether the module has a screen for an item.
  var hasDetails = false;

  final ranges = <(DateTime, DateTime)>[];
  final days = <DateTime>[];
}

class _Calendar implements CalendarProvider {
  _Calendar(this.server);

  final FakeServer server;

  Future<Result<List<T>, ServiceFailure>> _answer<T>(List<T> value) async {
    await server.held?.future;
    final failure = server.failure;
    return failure == null ? Ok(value) : Err(failure);
  }

  @override
  ServiceResult<List<CalendarEvent>> events(DateTime from, DateTime to) {
    server.ranges.add((from, to));
    return _answer([
      for (final event in server.releases)
        if (!event.date.isBefore(from) && event.date.isBefore(to)) event,
    ]);
  }

  @override
  ServiceResult<List<ImportedItem>> importedOn(DateTime day) {
    server.days.add(day);
    return _answer(server.imports[day] ?? []);
  }

  @override
  ServiceResult<List<ImportedItem>> recentlyAdded() async => const Ok([]);
}

class _Details implements LibraryProvider {
  _Details(this.server, this.instanceId);

  final FakeServer server;
  final String instanceId;

  @override
  MediaKind get itemKind => MediaKind.movie;

  @override
  ModuleRoute detailRoute(ItemRef ref) => server.hasDetails
      ? ModuleRoute(instanceId: instanceId, path: 'items/${ref.remoteId}')
      // As the real modules until their screens exist.
      : throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CalendarModule extends FakeModule {
  _CalendarModule()
    : super(
        'calendar',
        offers: {CapabilityKind.calendar, CapabilityKind.library},
      );

  /// By instance name.
  final servers = <String, FakeServer>{};

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final server = servers.putIfAbsent(context.instance.name, FakeServer.new);
    final Capability? found = switch (T) {
      const (CalendarProvider) => _Calendar(server),
      const (LibraryProvider) => _Details(server, context.instance.id),
      _ => null,
    };
    return found as T?;
  }
}

/// The calendar of an app with one instance for each of [names].
class CalendarHarness {
  CalendarHarness._(this.app, this._module, this.ids, this.now);

  final TestApp app;
  final _CalendarModule _module;

  /// Instance ids by name.
  final Map<String, String> ids;

  /// What the clock says.
  DateTime now;

  FakeServer server(String name) =>
      _module.servers.putIfAbsent(name, FakeServer.new);

  static Future<CalendarHarness> start(
    WidgetTester tester, {
    required DateTime now,
    List<String> names = const ['Films', 'Shows'],
    Size size = const Size(400, 800),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final module = _CalendarModule();
    final app = await TestApp.start(tester, modules: [module]);
    final ids = {for (final name in names) name: await app.add(module, name)};
    return CalendarHarness._(app, module, ids, now);
  }

  /// A release of [name]'s item [id].
  void release(
    String name,
    String title,
    DateTime date, {
    int id = 1,
    CalendarDateKind kind = CalendarDateKind.digitalRelease,
    ItemState state = ItemState.missing,
  }) => server(name).releases.add(
    CalendarEvent(
      itemRef: ItemRef(
        instanceId: ids[name]!,
        kind: MediaKind.movie,
        remoteId: id,
      ),
      title: title,
      date: date,
      dateKind: kind,
      state: state,
    ),
  );

  /// An import of [name] at [at], listed under the local day of [at].
  void imported(String name, String title, DateTime at, {int? id = 1}) {
    final local = at.toLocal();
    (server(name).imports[DateTime(local.year, local.month, local.day)] ??= [])
        .add(
          ImportedItem(
            title: title,
            importedAt: at.toUtc(),
            itemRef: id == null
                ? null
                : ItemRef(
                    instanceId: ids[name]!,
                    kind: MediaKind.movie,
                    remoteId: id,
                  ),
            quality: const Quality(id: 7, name: 'WEBDL-1080p'),
          ),
        );
  }

  Future<void> pump(
    WidgetTester tester, {
    CalendarTab tab = CalendarTab.agenda,
    double textScale = 1,
    bool settle = true,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => CalendarScreen(initialTab: tab),
        ),
        GoRoute(
          path: '/instances/:instanceId/items/:itemId',
          builder: (context, state) => Scaffold(
            body: Text('details of ${state.pathParameters['itemId']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(app.services),
          clockProvider.overrideWithValue(() => now),
        ],
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
    // A progress indicator never settles: then only let the reads answer.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
    }
  }

  Future<void> stop(WidgetTester tester) => app.stop(tester);
}
