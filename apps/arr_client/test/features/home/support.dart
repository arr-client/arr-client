/// Home over fake services whose answers the test sets, on a clock the test
/// sets.
library;

import 'dart:async';

import 'package:arr_client/app/localization.dart';
import 'package:arr_client/app/navigation/router.dart';
import 'package:arr_client/app/providers.dart';
import 'package:arr_client/features/calendar/today.dart';
import 'package:arr_client/src/l10n/generated/app_localizations.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../app/support.dart';
import '../activity/queue/support.dart' show FakeQueue, step;

/// What one instance's server has.
class FakeServer {
  final releases = <CalendarEvent>[];
  final imports = <ImportedItem>[];
  var issues = <HealthIssue>[];
  var disks = <DiskSpace>[];
  var reportsDisks = true;
  final queue = FakeQueue();

  /// Every read but the queue's fails with this while set.
  ServiceFailure? failure;

  /// Those reads wait for this while set.
  Completer<void>? held;

  /// How often each was read.
  var importReads = 0;
  var eventReads = 0;
  var healthReads = 0;

  Future<Result<List<T>, ServiceFailure>> answer<T>(List<T> value) async {
    await held?.future;
    final failure = this.failure;
    return failure == null ? Ok(value) : Err(failure);
  }
}

class _Calendar implements CalendarProvider {
  _Calendar(this.server);

  final FakeServer server;

  @override
  ServiceResult<List<CalendarEvent>> events(DateTime from, DateTime to) {
    server.eventReads++;
    return server.answer([
      for (final event in server.releases)
        if (!event.date.isBefore(from) && event.date.isBefore(to)) event,
    ]);
  }

  @override
  ServiceResult<List<ImportedItem>> importedOn(DateTime day) {
    server.importReads++;
    return server.answer([
      for (final item in server.imports)
        if (dayOf(item.importedAt) == day) item,
    ]);
  }

  @override
  ServiceResult<List<ImportedItem>> recentlyAdded() =>
      server.answer(List.of(server.imports));
}

class _Health implements HealthProvider {
  _Health(this.server);

  final FakeServer server;

  @override
  bool get providesDiskSpace => server.reportsDisks;

  @override
  ServiceResult<List<HealthIssue>> health() {
    server.healthReads++;
    return server.answer(server.issues);
  }

  @override
  ServiceResult<List<DiskSpace>> diskSpace() => server.answer(server.disks);
}

class _HomeModule extends FakeModule {
  _HomeModule(Set<CapabilityKind> offers) : super('home', offers: offers);

  /// By instance name.
  final servers = <String, FakeServer>{};

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final server = servers.putIfAbsent(context.instance.name, FakeServer.new);
    final Capability? found = switch (T) {
      const (CalendarProvider) => _Calendar(server),
      const (HealthProvider) => _Health(server),
      const (QueueProvider) => server.queue,
      _ => null,
    };
    return found as T?;
  }
}

/// Home of an app with one instance for each of [names].
class HomeHarness {
  HomeHarness._(this.app, this._module, this.ids, this.now);

  final TestApp app;
  final _HomeModule _module;

  /// Instance ids by name.
  final Map<String, String> ids;

  /// What the clock says.
  DateTime now;

  FakeServer server(String name) =>
      _module.servers.putIfAbsent(name, FakeServer.new);

  /// The screen is tall unless told, so that every section is built.
  static Future<HomeHarness> start(
    WidgetTester tester, {
    required DateTime now,
    List<String> names = const ['Films', 'Shows'],
    Size size = const Size(400, 4000),
    Set<CapabilityKind> offers = const {
      CapabilityKind.calendar,
      CapabilityKind.health,
      CapabilityKind.queue,
    },
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final module = _HomeModule(offers);
    final app = await TestApp.start(tester, modules: [module]);
    final ids = {for (final name in names) name: await app.add(module, name)};
    return HomeHarness._(app, module, ids, now);
  }

  ItemRef _ref(String name, int id) =>
      ItemRef(instanceId: ids[name]!, kind: MediaKind.movie, remoteId: id);

  void release(String name, String title, DateTime date, {int id = 1}) =>
      server(name).releases.add(
        CalendarEvent(
          itemRef: _ref(name, id),
          title: title,
          date: date,
          dateKind: CalendarDateKind.digitalRelease,
          state: ItemState.missing,
        ),
      );

  void imported(String name, String title, DateTime at, {int id = 1}) =>
      server(name).imports.add(
        ImportedItem(
          title: title,
          importedAt: at.toUtc(),
          itemRef: _ref(name, id),
          quality: const Quality(id: 7, name: 'WEBDL-1080p'),
        ),
      );

  Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
    final router = createRouter(app.services.modules);
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
    // A progress indicator never settles, so only let things answer.
    await settle(tester);
    await step(tester);
  }

  Future<void> stop(WidgetTester tester) => app.stop(tester);
}

/// The rows' titles under the heading [section], up to the next heading.
List<String> rowsOf(WidgetTester tester, String section) {
  double top(Finder finder) => tester.getTopLeft(finder).dy;
  final start = top(find.text(section).first);
  final ends = [
    for (final heading in const [
      'Coming up',
      'Downloaded today',
      'Recently added',
      'Active downloads',
      'Health',
      'Disk space',
      'Services',
      'Go to',
    ])
      if (heading != section)
        for (final element in find.text(heading).evaluate())
          if (top(find.byWidget(element.widget)) > start)
            top(find.byWidget(element.widget)),
  ]..sort();
  return [
    for (final element in find.byType(ListTile).evaluate())
      if (element.widget case ListTile(title: Text(:final data?)))
        if (top(find.byWidget(element.widget)) > start &&
            (ends.isEmpty || top(find.byWidget(element.widget)) < ends.first))
          data,
  ];
}
