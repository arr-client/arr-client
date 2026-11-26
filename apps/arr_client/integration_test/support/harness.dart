/// The running app of an integration test: the composition of the app itself
/// (its database, the device's key store and network), with data of its own, and
/// the ways to drive it.
///
/// Nothing here waits by `pumpAndSettle`: with real sockets and storage a frame
/// is not owed while an answer is under way, and an indeterminate progress
/// indicator never settles. A test waits for what it expects to see
/// ([AppHarness.waitFor]).
library;

import 'dart:io';

import 'package:arr_client/app/app.dart';
import 'package:arr_client/app/composition.dart';
import 'package:arr_client/app/platform/local_network.dart';
import 'package:arr_client/app/platform/secret_store.dart';
import 'package:arr_client/src/l10n/generated/app_localizations.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'certificates.dart';
import 'fake_server.dart';

/// A host for which the local network permission is refused. The emulator's
/// Android does not enforce the permission (it starts with Android 17), so the
/// refusal is stood in for; everything the app does about it is real. The
/// address is one kept for documentation, and nothing is sent to it.
const deniedHost = '192.0.2.1';

/// The English strings of the app, which is all it has.
final strings = lookupAppLocalizations(const Locale('en'));

/// One test of the running app. It starts with nothing saved and leaves nothing
/// behind.
void appTest(String description, Future<void> Function(AppHarness app) body) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // A tap that lands elsewhere fails there, not at a later wait.
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(description, (tester) async {
    // No soft keyboard, whose coming and going would move what is tapped.
    tester.testTextInput.register();
    final app = AppHarness._(
      tester,
      await Directory.systemTemp.createTemp('integration'),
    );
    try {
      await app.start();
      await body(app);
    } finally {
      await app._dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

class AppHarness {
  AppHarness._(this.tester, this._directory);

  final WidgetTester tester;

  /// Where the database and the artwork of this test are.
  final Directory _directory;

  /// The device's key store, which remembers what to erase after the test.
  final secrets = _RecordingSecrets();

  final _servers = <FakeServer>[];

  AppServices? _services;

  /// What the running app runs on.
  AppServices get services => _services!;

  /// Starts the app on what is saved.
  Future<void> start() async {
    final services = _services = await startOnDevice(
      dataDirectory: () async => _directory,
      cacheDirectory: () async => Directory('${_directory.path}/cache'),
      secrets: secrets,
      localNetwork: _RefusingOneHost(DeviceLocalNetworkPermission()),
    );
    await tester.pumpWidget(ArrClientApp(key: UniqueKey(), services: services));
    await settle();
  }

  /// Takes the app down and stops its services. What is saved stays.
  Future<void> stop() async {
    await tester.pumpWidget(const SizedBox.shrink());
    final services = _services;
    _services = null;
    await services?.close();
  }

  /// As closing the app and opening it again.
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// A server that is closed after the test.
  Future<FakeServer> serve(
    Handler handler, {
    TestCertificate? certificate,
  }) async {
    final server = await FakeServer.start(handler, certificate: certificate);
    _servers.add(server);
    return server;
  }

  Future<void> _dispose() async {
    try {
      await stop();
    } finally {
      for (final server in _servers) {
        await server.close();
      }
      await secrets.erase();
      await _directory.delete(recursive: true);
    }
  }

  // Waiting.

  /// Draws frames until nothing asks for another, or for two seconds, so that a
  /// route or a menu has arrived before it is tapped.
  Future<void> settle() async {
    final end = DateTime.now().add(const Duration(seconds: 2));
    do {
      await tester.pump(const Duration(milliseconds: 100));
    } while (tester.binding.hasScheduledFrame && DateTime.now().isBefore(end));
  }

  /// Draws frames until [condition] holds, and then, with [thenSettle], until
  /// what appeared has arrived. Fails with what is on screen.
  Future<void> waitUntil(
    bool Function() condition, {
    required String reason,
    Duration timeout = const Duration(seconds: 30),
    bool thenSettle = true,
  }) async {
    final end = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(end)) {
        fail('Waited ${timeout.inSeconds} s for $reason. On screen: $_texts');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (thenSettle) await settle();
  }

  Future<void> waitFor(Finder finder) => waitUntil(
    () => finder.evaluate().isNotEmpty,
    reason: finder.describeMatch(Plurality.one),
  );

  Future<void> waitUntilGone(Finder finder) => waitUntil(
    () => finder.evaluate().isEmpty,
    reason: 'no ${finder.describeMatch(Plurality.one)}',
  );

  String get _texts => [
    for (final element in find.byType(Text).evaluate())
      ?(element.widget as Text).data,
  ].join(' | ');

  // Doing.

  Future<void> tap(Finder finder) async {
    await waitFor(finder);
    await tester.ensureVisible(finder);
    await settle();
    // A snack bar, which goes by itself, moves and covers what is under it:
    // tapped only once nothing is over it and it stays where it is.
    Offset? last;
    await waitUntil(
      () {
        final at = finder.hitTestable().evaluate().isEmpty
            ? null
            : tester.getCenter(finder);
        final stays = at != null && at == last;
        last = at;
        return stays;
      },
      reason: 'to tap ${finder.describeMatch(Plurality.one)}',
      thenSettle: false,
    );
    await tester.tap(finder);
    await settle();
  }

  /// Types [text] into the field with the key [name].
  Future<void> enter(String name, String text) =>
      enterInto(find.byKey(ValueKey(name)), text);

  Future<void> enterInto(Finder field, String text) async {
    await waitFor(field);
    await tester.ensureVisible(field);
    await settle();
    await tester.enterText(field, text);
    await settle();
  }

  /// Leaves the page on top.
  Future<void> back() => tap(find.byType(BackButton).last);

  // Finding.

  /// A button of any of the Material kinds, by its label.
  Finder button(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );

  /// A primary destination, in the bottom bar or the rail.
  Finder destination(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is NavigationBar || widget is NavigationRail,
    ),
    matching: find.text(label),
  );
}

/// The device's key store, keeping the names of what was written.
class _RecordingSecrets implements SecretStore {
  static const _store = KeystoreSecretStore();

  /// The keys written and not deleted since.
  final keys = <String>{};

  @override
  Future<String?> read(String key) => _store.read(key);

  @override
  Future<void> write(String key, String value) {
    keys.add(key);
    return _store.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _store.delete(key);
    keys.remove(key);
  }

  /// What is stored under the keys of this test.
  Future<List<String>> values() async => [
    for (final key in keys) ?await _store.read(key),
  ];

  Future<void> erase() async {
    for (final key in [...keys]) {
      await delete(key);
    }
  }
}

class _RefusingOneHost implements LocalNetworkPermission {
  _RefusingOneHost(this._device);

  final LocalNetworkPermission _device;

  @override
  Future<LocalNetworkPermissionState> status(String host) async =>
      host == deniedHost
      ? LocalNetworkPermissionState.denied
      : await _device.status(host);

  @override
  Future<LocalNetworkPermissionState> request(String host) async =>
      host == deniedHost
      ? LocalNetworkPermissionState.denied
      : await _device.request(host);
}
