/// What the list of services says about each (spec story 1).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/support.dart';

/// Never asked: the fake probe sends nothing.
class _SignIn implements SessionHandler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A service of its own for each test, whose probe the test steers.
FakeModule films() => FakeModule('movies', offers: movies.offers);

Future<TestApp> start(WidgetTester tester, FakeModule module) {
  tester.view
    ..physicalSize = const Size(360, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return TestApp.start(tester, modules: [module]);
}

/// Shows the list of services.
Future<void> openList(WidgetTester tester, TestApp app) async {
  await app.pump(tester);
  await tester.tap(find.text('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Services'));
  await tester.pumpAndSettle();
}

Future<Instance> saved(TestApp app, String id) async =>
    (await app.services.profiles.instance(id))!;

Future<void> retry(WidgetTester tester, [String label = 'Retry']) async {
  await tester.tap(find.widgetWithText(TextButton, label));
  await tester.pumpAndSettle();
  await settle(tester);
  await tester.pumpAndSettle();
}

const _certificate = CertificateInfo(
  sha256: 'abababababababababababababababababababababababababababababababab',
);

void main() {
  testWidgets('says that a service has not been checked', (tester) async {
    final module = films();
    final app = await start(tester, module);
    // So that nothing checks it.
    unawaited(app.services.prober.close());
    await app.add(module, 'Films');
    await openList(tester, app);

    expect(find.text('Not yet checked'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Check now'), findsOneWidget);
    expect(module.probes, 0);
    await app.stop(tester);
  });

  testWidgets('shows the check under way and then the server', (tester) async {
    final module = films()..gate = Completer();
    final app = await start(tester, module);
    await app.add(module, 'Films');
    await openList(tester, app);

    expect(find.text('Testing the connection'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);

    module.gate!.complete();
    await tester.pumpAndSettle();
    await settle(tester);

    expect(find.text('Connected to movies 1'), findsOneWidget);
    expect(find.textContaining('newer'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('says why a check failed, and checks again when asked', (
    tester,
  ) async {
    final module = films()..failure = const Unreachable();
    final app = await start(tester, module);
    await app.add(module, 'Films');
    await openList(tester, app);

    expect(find.text('No answer'), findsOneWidget);
    expect(find.textContaining('Nothing usable answered'), findsOneWidget);
    // Only a service that signs in waits before it does so again.
    expect(find.textContaining('for a minute'), findsNothing);
    expect(find.text('Review certificate'), findsNothing);
    expect(module.probes, 1);

    module.failure = null;
    await retry(tester);

    expect(module.probes, 2);
    expect(find.text('Connected to movies 1'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says that the app stopped, until the user retries', (
    tester,
  ) async {
    final module = films();
    final app = await start(tester, module);
    unawaited(app.services.prober.close());
    final id = await app.add(module, 'Films');
    await app.services.profiles.markAuthFailed(id);
    await app.services.registry.refresh();
    await openList(tester, app);

    expect(find.text('API key rejected'), findsOneWidget);
    expect(find.textContaining('stopped trying'), findsOneWidget);
    expect(find.text('Not yet checked'), findsNothing);
    expect((await saved(app, id)).authFailed, isTrue);

    await retry(tester);

    expect((await saved(app, id)).authFailed, isFalse);
    expect(find.text('API key rejected'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('a retry of a latched service probes it once', (tester) async {
    final module = films();
    final app = await start(tester, module);
    final id = await app.add(module, 'Films');
    await openList(tester, app);
    await app.services.profiles.markAuthFailed(id);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('API key rejected'), findsOneWidget);
    final before = module.probes;

    await retry(tester);

    expect(module.probes, before + 1);
    expect(find.text('Connected to movies 1'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('warns of repeated sign-ins and of the wait between them', (
    tester,
  ) async {
    final module = FakeModule(
      'movies',
      offers: movies.offers,
      sessionHandler: _SignIn(),
    )..failure = const ServerError(statusCode: 500);
    final app = await start(tester, module);
    final added = await app.services.profiles.addInstance(
      await app.activeProfile,
      InstanceDraft(
        name: 'Films',
        serviceType: module.id,
        url: Uri.parse('http://server.invalid/'),
        authKind: AuthKind.userPassword,
      ),
      credential: const Credential(username: 'zq-user', password: 'zq-pass'),
    );
    final id = (added as Ok<Instance, RuleViolation>).value.id;
    await openList(tester, app);

    expect(find.text('Server error'), findsOneWidget);
    expect(find.textContaining('not sent again for a minute'), findsOneWidget);

    await app.services.profiles.markAuthFailed(id);
    await tester.pumpAndSettle();
    await settle(tester);

    expect(find.text('Sign-in rejected'), findsOneWidget);
    expect(find.textContaining('get this device blocked'), findsOneWidget);
    expect(find.text('Server error'), findsNothing);
    await app.stop(tester);
  });

  for (final (title, failure) in [
    ('Certificate changed', const CertificateChanged(_certificate)),
    ('Certificate not trusted', const CertificateUntrusted(_certificate)),
  ]) {
    testWidgets('leads to the review: $title', (tester) async {
      final module = films()..failure = failure;
      final app = await start(tester, module);
      await app.add(module, 'Films');
      await openList(tester, app);

      expect(find.text(title), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      await tester.tap(find.text('Review certificate'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Edit Films'), findsOneWidget);
      await app.stop(tester);
    });
  }

  testWidgets('blocks a version too old until a check finds otherwise', (
    tester,
  ) async {
    final module = films()..failure = const UnsupportedVersion(version: '0.9');
    final app = await start(tester, module);
    final id = await app.add(module, 'Films');
    await openList(tester, app);

    expect(find.text('Server version not supported'), findsOneWidget);
    expect(
      find.text('Server version 0.9 is not supported. Update the server.'),
      findsOneWidget,
    );
    expect((await saved(app, id)).unsupportedVersion, '0.9');
    // It offers nothing.
    expect(find.text('Library'), findsNothing);

    // Still said when the server cannot be reached.
    module.failure = const Unreachable();
    await retry(tester);
    expect(find.text('Server version not supported'), findsOneWidget);
    expect(find.text('No answer'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

    module.failure = null;
    await retry(tester);

    expect(find.text('Server version not supported'), findsNothing);
    expect(find.text('Connected to movies 1'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('notes a version newer than tested, also while offline', (
    tester,
  ) async {
    final module = films()..newerThanTested = true;
    final app = await start(tester, module);
    await app.add(module, 'Films');
    await openList(tester, app);
    const notice = 'Version 1 is newer than the ones the app was tested with.';

    expect(find.text(notice), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);

    module.failure = const Unreachable();
    app.services.prober.probe(
      app.services.registry.scope!.instances.single.instance.id,
    );
    await tester.pumpAndSettle();
    await settle(tester);

    expect(find.text('No answer'), findsOneWidget);
    expect(find.text(notice), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says nothing about a disabled service', (tester) async {
    final module = films();
    final app = await start(tester, module);
    final id = await app.add(module, 'Films', enabled: false);
    await app.services.profiles.markAuthFailed(id);
    await openList(tester, app);

    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('API key rejected'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(module.probes, 0);
    await app.stop(tester);
  });

  testWidgets('fits at twice the text size, with buttons of their own', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final module = films()..failure = const CertificateChanged(_certificate);
    final app = await start(tester, module);
    await app.add(module, 'Films');
    await openList(tester, app);
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.widgetWithText(TextButton, 'Retry'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
    for (final label in ['Review certificate', 'Retry']) {
      final node = tester.getSemantics(find.widgetWithText(TextButton, label));
      expect(node.label, label);
      expect(node, isSemantics(isButton: true, hasTapAction: true));
    }
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
    await app.stop(tester);
  });
}
