/// The composition root with the modules the app ships.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arr_client/app/composition.dart';
import 'package:arr_client/app/localization.dart';
import 'package:arr_client/app/modules.dart';
import 'package:arr_client/app/navigation/destinations.dart';
import 'package:bazarr/bazarr_module.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:prowlarr/prowlarr_module.dart';
import 'package:radarr/radarr_module.dart';
import 'package:sonarr/sonarr_module.dart';

import 'support.dart';

/// Answers `system/status` as Radarr or Sonarr, by the first part of the path.
Future<HttpServer> serveStatus() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    final (product, version) = request.uri.pathSegments.first == 'radarr'
        ? ('Radarr', '6.0.0.1')
        : ('Sonarr', '4.0.20.3014');
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'appName': product, 'version': version}));
    await request.response.close();
  });
  return server;
}

void main() {
  test('the app is built with every module that has screens', () {
    expect(serviceModules().map((module) => module.id), [
      'radarr',
      'sonarr',
      'qbittorrent',
      'prowlarr',
      'bazarr',
    ]);
  });

  testWidgets('has the strings of every module', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(),
      ),
    );
    final context = tester.element(find.byType(Scaffold));

    // Labels and hints that a module supplies throw without its delegate.
    expect(RadarrLocalizations.of(context).monitorNone, isNotEmpty);
    expect(SonarrLocalizations.of(context).monitorAll, isNotEmpty);
    expect(ProwlarrLocalizations.of(context).searchTab, isNotEmpty);
    expect(BazarrLocalizations.of(context).wantedTab, isNotEmpty);
    for (final module in serviceModules()) {
      for (final note in module.descriptor.authNotes) {
        expect(note.text(context), isNotEmpty);
      }
    }
  });

  test('probes saved instances and offers what they have', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The binding answers every request itself; these must reach the server.
    HttpOverrides.global = null;
    final server = await serveStatus();
    final services = await AppServices.start(
      database: NativeDatabase.memory(),
      secrets: MemorySecrets(),
      connectivity: FakeConnectivity(),
      localNetwork: FakePermission(),
      cacheDirectory: () async => Directory('build/test-cache'),
    );
    addTearDown(services.close);
    final profile = (await services.preferences.read()).activeProfileId!;
    expect(Navigation.of(services.registry.scope).destinations, [
      AppDestination.home,
      AppDestination.more,
    ]);

    final probed = Completer<void>();
    final changes = services.registry.changes.listen((scope) {
      final instances = scope?.instances ?? const <ActiveInstance>[];
      if (instances.length == 2 &&
          instances.every((one) => one.connection is ConnectionOnline) &&
          instances.every((one) => one.capabilities.isNotEmpty) &&
          !probed.isCompleted) {
        probed.complete();
      }
    });
    addTearDown(changes.cancel);
    // As an instance saved after a failed test: nothing known of it yet.
    for (final type in ['radarr', 'sonarr']) {
      final added = await services.profiles.addInstance(
        profile,
        InstanceDraft(
          name: type,
          serviceType: type,
          url: Uri.parse('http://127.0.0.1:${server.port}/$type'),
          authKind: AuthKind.apiKey,
        ),
        credential: const Credential(apiKey: 'zq-key-0123456789'),
      );
      expect(added, isA<Ok<Instance, RuleViolation>>());
    }
    await probed.future.timeout(const Duration(seconds: 10));

    final navigation = Navigation.of(services.registry.scope);
    expect(navigation.destinations, [
      AppDestination.home,
      AppDestination.library,
      AppDestination.activity,
      AppDestination.more,
    ]);
    expect(navigation.libraryTabs, [LibraryTab.movies, LibraryTab.series]);
    expect(navigation.canSearch, isTrue);
  });
}
