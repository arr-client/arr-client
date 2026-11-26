/// The add and edit form in the running app, with services that answer without
/// a server.
library;

import 'dart:async';

import 'package:arr_client/app/localization.dart';
import 'package:arr_client/app/navigation/locations.dart';
import 'package:arr_client/app/providers.dart';
import 'package:arr_client/features/onboarding/certificate_review.dart';
import 'package:arr_client/features/onboarding/failure_text.dart';
import 'package:arr_client/features/onboarding/instance_form_screen.dart';
import 'package:arr_client/src/l10n/generated/app_localizations.dart';
import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/support.dart';

const key = 'zq-key-0123456789';

typedef Answer = Result<ProbeResult, ServiceFailure>;

const Answer works = Ok(ProbeResult(product: 'Films', version: '5.1'));

class SignIn implements SessionHandler {
  final credentials = <Credential>[];

  @override
  ServiceResult<String> login({
    required AuthKind authKind,
    required Credential credential,
    required ServiceHttpClient http,
  }) async {
    credentials.add(credential);
    return const Ok('SID=session-123456');
  }

  @override
  bool isSessionExpired(ServiceResponse response) => false;
}

/// A service whose probe answers what the test sets.
class FormModule extends FakeModule {
  FormModule({
    this.authKinds = const [AuthKind.apiKey],
    this.header = 'X-Api-Key',
    this.notes = const [],
  }) : super('films', offers: {CapabilityKind.library});

  final List<AuthKind> authKinds;
  final String header;
  final List<AuthNote> notes;

  /// What the next tests find.
  Future<Answer> Function() answer = () async => works;

  final probed = <Instance>[];
  final signIn = SignIn();

  @override
  ModuleDescriptor get descriptor => ModuleDescriptor(
    displayName: 'Films',
    icon: Icons.movie,
    category: ModuleCategory.movies,
    authKinds: authKinds,
    apiKeyHeader: ApiKeyHeader(header),
    defaultPort: 7878,
    minimumVersion: '1',
    testedVersion: '9',
    authNotes: notes,
  );

  @override
  SessionHandler? get sessionHandler => signIn;

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) {
    probed.add(context.instance);
    return answer();
  }
}

class Denied implements LocalNetworkPermission {
  var requests = 0;

  @override
  Future<LocalNetworkPermissionState> status(String host) async =>
      LocalNetworkPermissionState.denied;

  @override
  Future<LocalNetworkPermissionState> request(String host) async {
    requests++;
    return LocalNetworkPermissionState.denied;
  }
}

Finder field(String name) => find.byKey(ValueKey(name));

Finder button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String name, String text) async {
  await tester.ensureVisible(field(name));
  await tester.enterText(field(name), text);
  await tester.pump();
}

/// From Home on a first launch to the form.
Future<void> openForm(WidgetTester tester) async {
  await press(tester, button('Add service'));
  await press(tester, find.widgetWithText(ListTile, 'Films'));
}

Future<void> fill(WidgetTester tester) async {
  await enter(tester, 'address', '192.168.1.10:7878');
  await enter(tester, 'apiKey', ' $key ');
}

Future<List<Instance>> saved(TestApp app) async =>
    app.services.profiles.instances(await app.activeProfile);

Future<(TestApp, FormModule)> start(
  WidgetTester tester, {
  FormModule? module,
  LocalNetworkPermission? permission,
}) async {
  final films = module ?? FormModule();
  final app = await TestApp.start(
    tester,
    modules: [films],
    localNetwork: permission,
  );
  await app.pump(tester);
  return (app, films);
}

void go(WidgetTester tester, String location) =>
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);

void main() {
  testWidgets('adds a service: address and key, test, then add', (
    tester,
  ) async {
    final (app, films) = await start(tester);
    await openForm(tester);
    expect(button('Add service'), findsNothing);
    await fill(tester);

    await press(tester, button('Test connection'));

    expect(find.text('Connected to Films 5.1'), findsOneWidget);
    expect(find.text('http://192.168.1.10:7878'), findsOneWidget);
    expect(await saved(app), isEmpty);
    await press(tester, button('Add service'));

    final instance = (await saved(app)).single;
    expect(instance.name, 'Films');
    expect(instance.url, Uri.parse('http://192.168.1.10:7878'));
    expect(instance.authKind, AuthKind.apiKey);
    expect(instance.detectedVersion, '5.1');
    expect(instance.authFailed, isFalse);
    final credential = await app.services.profiles.credential(instance.id);
    expect(credential?.apiKey, key);
    // Back on Home, which no longer asks for a first service.
    expect(find.text('Films added'), findsOneWidget);
    expect(button('Add service'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('says what is missing and sends nothing', (tester) async {
    final (app, films) = await start(tester);
    await openForm(tester);

    await press(tester, button('Test connection'));

    expect(find.text("Enter the server's address"), findsOneWidget);
    expect(find.text('Enter the API key'), findsOneWidget);
    await enter(tester, 'address', 'http://me:pw@nas');
    await tester.pump();
    expect(find.textContaining('Take the user name'), findsOneWidget);
    expect(films.probed, isEmpty);
    await app.stop(tester);
  });

  testWidgets('a failed test can be saved anyway', (tester) async {
    final (app, films) = await start(tester);
    films.answer = () async => const Err(Unreachable());
    await openForm(tester);
    await fill(tester);

    await press(tester, button('Test connection'));

    expect(find.text('No answer'), findsOneWidget);
    await press(tester, button('Save anyway'));
    final instance = (await saved(app)).single;
    expect(instance.lastProbe, isNull);
    expect(instance.authFailed, isFalse);
    await app.stop(tester);
  });

  testWidgets('a refused key saved anyway is not tried again', (tester) async {
    final (app, films) = await start(tester);
    films.answer = () async => const Err(AuthFailed());
    await openForm(tester);
    await fill(tester);
    await press(tester, button('Test connection'));
    expect(find.text('API key rejected'), findsOneWidget);

    await press(tester, button('Save anyway'));

    expect((await saved(app)).single.authFailed, isTrue);
    // The test only: the prober leaves a refused key alone.
    expect(films.probed, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('a change forgets the test, a new name does not', (tester) async {
    final (app, _) = await start(tester);
    await openForm(tester);
    await fill(tester);
    await press(tester, button('Test connection'));

    await enter(tester, 'name', 'Films at home');
    expect(button('Add service'), findsOneWidget);
    await enter(tester, 'apiKey', 'zq-other-9876543210');

    expect(button('Add service'), findsNothing);
    expect(find.textContaining('Connected to'), findsNothing);
    expect(button('Test connection'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a running test can be stopped and its answer is dropped', (
    tester,
  ) async {
    final (app, films) = await start(tester);
    final answer = Completer<Answer>();
    films.answer = () => answer.future;
    await openForm(tester);
    await fill(tester);
    await tester.ensureVisible(button('Test connection'));
    await tester.tap(button('Test connection'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Testing the connection'), findsOneWidget);

    await tester.ensureVisible(button('Stop test'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(button('Stop test'));
    answer.complete(works);
    await tester.pumpAndSettle();

    expect(find.textContaining('Connected to'), findsNothing);
    expect(button('Test connection'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('signs in with a user name and password', (tester) async {
    final (app, films) = await start(
      tester,
      module: FormModule(authKinds: [AuthKind.apiKey, AuthKind.userPassword]),
    );
    await openForm(tester);
    await press(tester, find.text('User name and password'));
    expect(field('apiKey'), findsNothing);
    await enter(tester, 'address', 'https://nas.test/films/');
    await enter(tester, 'username', 'admin');
    await enter(tester, 'password', 'zq-pass-123456');

    await press(tester, button('Test connection'));
    await press(tester, button('Add service'));

    final instance = (await saved(app)).single;
    expect(instance.url, Uri.parse('https://nas.test/films'));
    expect(instance.authKind, AuthKind.userPassword);
    expect(films.signIn.credentials.first.password, 'zq-pass-123456');
    final credential = await app.services.profiles.credential(instance.id);
    expect(credential?.username, 'admin');
    expect(credential?.apiKey, isNull);
    await app.stop(tester);
  });

  testWidgets('saves basic auth and headers, with the notes about them', (
    tester,
  ) async {
    final (app, _) = await start(
      tester,
      module: FormModule(
        notes: [
          AuthNote(
            authKind: AuthKind.apiKey,
            onlyWithBasicAuth: true,
            text: (_) => 'A note about basic',
          ),
          AuthNote(authKind: AuthKind.apiKey, text: (_) => 'A note about keys'),
        ],
      ),
    );
    await openForm(tester);
    await fill(tester);
    expect(find.text('A note about keys'), findsOneWidget);
    expect(find.text('A note about basic'), findsNothing);

    await press(tester, find.text('Advanced'));
    await enter(tester, 'basicUser', 'proxy');
    await enter(tester, 'basicPassword', 'zq-basic-123456');
    expect(find.text('A note about basic'), findsOneWidget);
    await press(tester, button('Add header'));
    await enter(tester, 'headerName0', 'Host');
    await enter(tester, 'headerValue0', 'zq-header-123456');
    // Closed, the part is still checked, and opens to show what is wrong.
    await press(tester, find.text('Advanced'));
    await press(tester, button('Test connection'));
    expect(find.text('Not a header name that can be sent'), findsOneWidget);
    await enter(tester, 'headerName0', 'X-Proxy-Id');
    await press(tester, button('Test connection'));
    await press(tester, button('Add service'));

    final credential = await app.services.profiles.credential(
      (await saved(app)).single.id,
    );
    expect(credential?.basicUser, 'proxy');
    expect(credential?.basicPassword, 'zq-basic-123456');
    expect(credential?.customHeaders, {'X-Proxy-Id': 'zq-header-123456'});
    await app.stop(tester);
  });

  testWidgets('refuses basic auth beside a key in Authorization', (
    tester,
  ) async {
    final (app, films) = await start(
      tester,
      module: FormModule(header: 'Authorization'),
    );
    await openForm(tester);
    await fill(tester);
    await press(tester, find.text('Advanced'));
    await enter(tester, 'basicUser', 'proxy');

    await press(tester, button('Test connection'));

    expect(find.textContaining('cannot be used'), findsOneWidget);
    expect(films.probed, isEmpty);
    await app.stop(tester);
  });

  testWidgets('offers a free name and refuses a taken one', (tester) async {
    final films = FormModule();
    final app = await TestApp.start(tester, modules: [films]);
    await app.add(films, 'Films');
    await app.pump(tester);
    go(tester, addServiceFormLocation('films'));
    await tester.pumpAndSettle();
    expect(find.text('Films 2'), findsOneWidget);
    await fill(tester);
    await press(tester, button('Test connection'));
    await enter(tester, 'name', 'films');

    await press(tester, button('Add service'));

    expect(
      find.text('Another service in this profile has this name'),
      findsOneWidget,
    );
    expect(await saved(app), hasLength(1));
    await app.stop(tester);
  });

  testWidgets('edits an instance, keeping what is not changed', (tester) async {
    final films = FormModule();
    final app = await TestApp.start(tester, modules: [films]);
    final id = await app.add(films, 'Films', enabled: false);
    await app.pump(tester);
    go(tester, editInstanceLocation(id));
    await tester.pumpAndSettle();
    expect(find.text('Edit Films'), findsOneWidget);
    expect(find.text('http://server.invalid/Films'), findsOneWidget);
    await enter(tester, 'name', 'Cinema');

    await press(tester, button('Save without testing'));

    final instance = (await saved(app)).single;
    expect(instance.name, 'Cinema');
    expect(instance.enabled, isFalse);
    expect((await app.services.profiles.credential(id))?.apiKey, isNotNull);
    await app.stop(tester);
  });

  testWidgets('edits a disabled service of a profile that is not active', (
    tester,
  ) async {
    final films = FormModule();
    final app = await TestApp.start(tester, modules: [films]);
    final away = await app.addProfile('Away');
    final id = await app.add(films, 'Films', profileId: away, enabled: false);
    await app.pump(tester);
    go(tester, editInstanceLocation(id));
    await tester.pumpAndSettle();
    await enter(tester, 'address', 'https://away.test');

    await press(tester, button('Save without testing'));

    final instance = (await app.services.profiles.instances(away)).single;
    expect(instance.url, Uri.parse('https://away.test'));
    expect(instance.enabled, isFalse);
    expect(await saved(app), isEmpty);
    await app.stop(tester);
  });

  testWidgets('says that the service to edit has been removed', (tester) async {
    final films = FormModule();
    final app = await TestApp.start(tester, modules: [films]);
    await app.pump(tester);
    go(tester, editInstanceLocation('gone'));
    await tester.pumpAndSettle();

    expect(find.text('This service has been removed.'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a save after the service was removed saves nothing', (
    tester,
  ) async {
    final films = FormModule();
    final app = await TestApp.start(tester, modules: [films]);
    final id = await app.add(films, 'Films');
    await app.pump(tester);
    go(tester, editInstanceLocation(id));
    await tester.pumpAndSettle();
    await app.services.profiles.deleteInstance(id);
    await tester.pumpAndSettle();

    await press(tester, button('Save without testing'));

    expect(find.text('This service has been removed.'), findsOneWidget);
    expect(await saved(app), isEmpty);
    await app.stop(tester);
  });

  testWidgets('a passed test of a refused instance lets it be tried again', (
    tester,
  ) async {
    final films = FormModule();
    final app = await TestApp.start(tester, modules: [films]);
    final id = await app.add(films, 'Films');
    await app.services.profiles.markAuthFailed(id);
    await app.pump(tester);
    go(tester, editInstanceLocation(id));
    await tester.pumpAndSettle();

    await press(tester, button('Test connection'));
    await press(tester, button('Save'));

    expect((await saved(app)).single.authFailed, isFalse);
    await app.stop(tester);
  });

  testWidgets('a refused test of what is saved latches it at once', (
    tester,
  ) async {
    final films = FormModule();
    final app = await TestApp.start(tester, modules: [films]);
    final id = await app.add(films, 'Films', enabled: false);
    await app.pump(tester);
    films.answer = () async => const Err(AuthFailed());
    go(tester, editInstanceLocation(id));
    await tester.pumpAndSettle();

    await press(tester, button('Test connection'));

    expect((await saved(app)).single.authFailed, isTrue);
    await app.stop(tester);
  });

  testWidgets('explains the local network permission before asking', (
    tester,
  ) async {
    final permission = Denied();
    final (app, films) = await start(tester, permission: permission);
    await openForm(tester);
    await fill(tester);

    await tester.ensureVisible(button('Test connection'));
    await tester.tap(button('Test connection'));
    // The progress bar behind the dialog keeps moving.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Allow local network access'), findsOneWidget);
    expect(permission.requests, 0);
    await tester.tap(button('Continue'));
    await tester.pumpAndSettle();

    expect(permission.requests, 1);
    expect(find.text('Local network access not allowed'), findsOneWidget);
    expect(films.probed, isEmpty);
    await app.stop(tester);
  });

  testWidgets('says that certificates cannot be reviewed yet', (tester) async {
    final (app, films) = await start(tester);
    films.answer = () async =>
        const Err(CertificateUntrusted(CertificateInfo(sha256: 'ab')));
    await openForm(tester);
    await fill(tester);

    await press(tester, button('Test connection'));

    expect(find.text('Certificate not trusted'), findsOneWidget);
    expect(find.textContaining('cannot review certificates'), findsOneWidget);
    expect(button('Review certificate'), findsNothing);
    expect(button('Save anyway'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('a certificate screen plugs in, and what it accepts is tested', (
    tester,
  ) async {
    final films = FormModule();
    final app = await TestApp.start(tester, modules: [films]);
    films.answer = () async => films.probed.last.certPin == null
        ? const Err(CertificateUntrusted(CertificateInfo(sha256: 'ab')))
        : works;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(app.services),
          certificateReviewProvider.overrideWithValue(
            (context, {required url, required failure}) async =>
                const CertificateTrust(certPin: 'ab'),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: InstanceFormScreen.add(serviceType: 'films'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await enter(tester, 'address', 'https://nas.test');
    await enter(tester, 'apiKey', key);
    await press(tester, button('Test connection'));

    await press(tester, button('Review certificate'));

    expect(find.text('Connected to Films 5.1'), findsOneWidget);
    expect([for (final probe in films.probed) probe.certPin], [null, 'ab']);
    await app.stop(tester);
  });

  testWidgets('every failure of a test has its own words', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    const certificate = CertificateInfo(sha256: 'ab');

    final texts = [
      for (final failure in const <ServiceFailure>[
        Unreachable(),
        DnsFailure(),
        CertificateUntrusted(certificate),
        CertificateChanged(certificate),
        AuthFailed(),
        Forbidden(),
        WrongService(),
        ProxyInterception(),
        Redirected(host: 'elsewhere.test'),
        HostRejected(),
        UnsupportedVersion(version: '1.0'),
        PermissionDenied(),
        ServerError(statusCode: 500),
        MalformedResponse(),
      ])
        testFailureText(
          context,
          failure,
          service: 'Films',
          authKind: AuthKind.apiKey,
        ),
    ];

    expect({for (final text in texts) text.title}, hasLength(texts.length));
    expect({for (final text in texts) text.message}, hasLength(texts.length));
  });

  testWidgets('fits and stays operable with text at twice the size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final semantics = tester.ensureSemantics();
    final (app, films) = await start(
      tester,
      module: FormModule(authKinds: [AuthKind.apiKey, AuthKind.userPassword]),
    );
    films.answer = () async => const Err(ProxyInterception());
    await openForm(tester);
    await fill(tester);
    await press(tester, find.text('Advanced'));
    await press(tester, button('Add header'));

    await press(tester, button('Test connection'));

    expect(tester.takeException(), isNull);
    expect(find.text('Got a web page instead'), findsOneWidget);
    expect(find.byTooltip('Show API key'), findsOneWidget);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
    await app.stop(tester);
  });
}
