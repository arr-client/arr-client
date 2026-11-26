/// The certificate screens (T046, FR-005) in the running app: accepting is
/// deliberate, a changed certificate is told apart and never accepted by
/// itself, and an authority can take the place of an accepted certificate.
library;

import 'dart:convert';
import 'dart:io';

import 'package:arr_client/app/localization.dart';
import 'package:arr_client/app/navigation/locations.dart';
import 'package:arr_client/features/onboarding/certificate/authority_import_screen.dart';
import 'package:arr_client/features/onboarding/certificate/certificate_file.dart';
import 'package:arr_client/features/onboarding/certificate/certificate_widgets.dart';
import 'package:arr_client/src/l10n/generated/app_localizations.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/support.dart';
import 'instance_form_test.dart'
    show
        FormModule,
        button,
        enter,
        field,
        fill,
        go,
        key,
        openForm,
        press,
        saved,
        start,
        works;

final oldPin = 'ab' * 32;
final newPin = 'cd' * 32;

/// As the screens write them.
final oldPrint = formatFingerprint(oldPin);
final newPrint = formatFingerprint(newPin);

const host = 'nas.test:7878';

String get caPem =>
    File('../../packages/core/test/network/certs/ca.pem').readAsStringSync();

String get storedCa => switch (readCertificateAuthority(utf8.encode(caPem))) {
  Ok(:final value) => value.pem,
  Err() => throw StateError('The test authority cannot be read'),
};

CertificateInfo presented(String sha256) => CertificateInfo(
  sha256: sha256,
  subject: '/CN=nas.test',
  issuer: '/CN=nas.test',
  notBefore: DateTime.utc(2025),
  notAfter: DateTime.utc(2125),
);

/// A server that presents the certificate [sha256], which no authority vouches
/// for unless [signed].
void serve(FormModule films, String sha256, {bool signed = false}) {
  films.answer = () async {
    final probe = films.probed.last;
    if (probe.certPin case final pin?) {
      return pin == sha256 ? works : Err(CertificateChanged(presented(sha256)));
    }
    return signed && probe.customCa != null
        ? works
        : Err(CertificateUntrusted(presented(sha256)));
  };
}

Future<Instance> addPinned(TestApp app, {String? customCa}) async {
  final result = await app.services.profiles.addInstance(
    await app.activeProfile,
    InstanceDraft(
      name: 'Films',
      serviceType: 'films',
      url: Uri.parse('https://$host'),
      authKind: AuthKind.apiKey,
      acceptedCertPin: oldPin,
      customCa: customCa,
    ),
    credential: const Credential(apiKey: key),
  );
  return (result as Ok<Instance, RuleViolation>).value;
}

/// The app also probes a saved service by itself: this forgets what it did so
/// far.
Future<(TestApp, FormModule, Instance)> editPinned(WidgetTester tester) async {
  final (app, films) = await start(tester);
  final instance = await addPinned(app);
  await tester.pumpAndSettle();
  go(tester, editInstanceLocation(instance.id));
  await tester.pumpAndSettle();
  films.probed.clear();
  return (app, films, instance);
}

Future<Instance> reload(TestApp app, Instance instance) async =>
    (await app.services.profiles.instance(instance.id))!;

Future<void> addSecure(WidgetTester tester) async {
  await openForm(tester);
  await fill(tester);
  await enter(tester, 'address', 'https://$host');
}

bool enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(button(label)).enabled;

Finder fingerprint(String text) => find.bySemanticsLabel(text);

Future<void> back(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> tick(WidgetTester tester) =>
    press(tester, find.byType(CheckboxListTile));

Future<void> importPasted(WidgetTester tester) async {
  await enter(tester, 'authorityText', caPem);
  await tester.pumpAndSettle();
  await press(tester, button('Use this authority'));
}

void main() {
  testWidgets('shows a new certificate and trusts it only when told to', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (app, films) = await start(tester);
    serve(films, newPin);
    await addSecure(tester);
    await press(tester, button('Test connection'));

    await press(tester, button('Review certificate'));

    expect(find.text('Review certificate'), findsOneWidget);
    expect(find.textContaining('$host presented'), findsOneWidget);
    expect(fingerprint(newPrint), findsOneWidget);
    expect(find.text('CN=nas.test'), findsNWidgets(2));
    expect(find.textContaining('no longer presents'), findsNothing);
    expect(enabled(tester, 'Trust this certificate'), isFalse);

    // Leaving trusts nothing and sends nothing.
    await back(tester);
    await press(tester, button('Review certificate'));
    await press(tester, button('Do not trust'));
    expect(films.probed, hasLength(1));
    expect(find.text('Certificate not trusted'), findsOneWidget);

    await press(tester, button('Review certificate'));
    expect(enabled(tester, 'Trust this certificate'), isFalse);
    await tick(tester);
    await press(tester, button('Trust this certificate'));

    expect(find.text('Connected to Films 5.1'), findsOneWidget);
    expect([for (final probe in films.probed) probe.certPin], [null, newPin]);
    // Nothing is stored before the service is saved.
    expect(await saved(app), isEmpty);
    await press(tester, button('Add service'));
    expect((await saved(app)).single.certPin, newPin);
    semantics.dispose();
    await app.stop(tester);
  });

  testWidgets('a changed certificate of a saved service is told apart', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (app, films, instance) = await editPinned(tester);
    serve(films, newPin);
    await press(tester, button('Test connection'));

    await press(tester, button('Review certificate'));

    expect(find.text('Certificate changed'), findsOneWidget);
    expect(find.textContaining('no longer presents'), findsOneWidget);
    expect(find.textContaining('intercepting'), findsOneWidget);
    expect(fingerprint(oldPrint), findsOneWidget);
    expect(fingerprint(newPrint), findsOneWidget);
    // Keeping is the primary choice, accepting needs the statement first.
    expect(
      tester.widget(button('Keep the accepted certificate')),
      isA<FilledButton>(),
    );
    expect(
      tester.widget(button('Trust the new certificate')),
      isA<OutlinedButton>(),
    );
    expect(enabled(tester, 'Trust the new certificate'), isFalse);

    await press(tester, button('Keep the accepted certificate'));

    expect([for (final probe in films.probed) probe.certPin], [oldPin]);
    await press(tester, button('Save anyway'));
    expect((await reload(app, instance)).certPin, oldPin);
    semantics.dispose();
    await app.stop(tester);
  });

  testWidgets('a changed certificate is replaced once accepted', (
    tester,
  ) async {
    final (app, films, instance) = await editPinned(tester);
    serve(films, newPin);
    await press(tester, button('Test connection'));
    await press(tester, button('Review certificate'));

    await tick(tester);
    await press(tester, button('Trust the new certificate'));

    expect(find.text('Connected to Films 5.1'), findsOneWidget);
    expect((await reload(app, instance)).certPin, oldPin);
    await press(tester, button('Save'));
    expect((await reload(app, instance)).certPin, newPin);
    await app.stop(tester);
  });

  // Otherwise the changed certificate would pass for a first one.
  testWidgets('another address and back keeps the accepted certificate', (
    tester,
  ) async {
    final (app, films, _) = await editPinned(tester);
    serve(films, newPin);
    await enter(tester, 'address', 'https://other.test');
    await press(tester, button('Test connection'));
    await press(tester, button('Review certificate'));
    await tick(tester);
    await press(tester, button('Trust this certificate'));

    await enter(tester, 'address', 'https://$host');
    await press(tester, button('Test connection'));

    expect(films.probed.last.certPin, oldPin);
    expect(find.text('Certificate changed'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('imports an authority before any test', (tester) async {
    final (app, films) = await start(tester);
    serve(films, newPin, signed: true);
    await addSecure(tester);
    await press(tester, find.text('Advanced'));
    await press(tester, button('Import certificate authority'));

    expect(find.textContaining('signed for $host'), findsOneWidget);
    expect(button('Use this authority'), findsNothing);
    expect(find.textContaining('no longer used'), findsNothing);
    await enter(tester, 'authorityText', caPem);
    await tester.pumpAndSettle();
    expect(find.text('CN=arr-client test CA'), findsNWidgets(2));
    await press(tester, button('Use this authority'));

    expect(films.probed, isEmpty);
    expect(button('Replace certificate authority'), findsOneWidget);
    expect(find.text('CN=arr-client test CA'), findsNWidgets(2));
    await press(tester, button('Test connection'));
    expect(films.probed.single.customCa, storedCa);
    await press(tester, button('Add service'));
    final instance = (await saved(app)).single;
    expect(instance.customCa, storedCa);
    expect(instance.certPin, isNull);
    await app.stop(tester);
  });

  testWidgets('an authority takes the place of the accepted certificate', (
    tester,
  ) async {
    final (app, films, instance) = await editPinned(tester);
    serve(films, newPin, signed: true);
    await press(tester, find.text('Advanced'));
    await press(tester, button('Import certificate authority'));
    expect(find.textContaining('no longer used'), findsOneWidget);

    await importPasted(tester);
    await press(tester, button('Test connection'));
    expect(films.probed.single.certPin, isNull);
    await press(tester, button('Save'));

    final stored = await reload(app, instance);
    expect(stored.certPin, isNull);
    expect(stored.customCa, storedCa);
    await app.stop(tester);
  });

  testWidgets('offers an authority when reviewing a changed certificate', (
    tester,
  ) async {
    final (app, films, instance) = await editPinned(tester);
    serve(films, newPin, signed: true);
    await press(tester, button('Test connection'));
    await press(tester, button('Review certificate'));

    await press(tester, button('Import a certificate authority instead'));
    expect(find.textContaining('no longer used'), findsOneWidget);
    await importPasted(tester);

    expect(find.text('Connected to Films 5.1'), findsOneWidget);
    expect(films.probed.last.certPin, isNull);
    expect(films.probed.last.customCa, storedCa);
    await press(tester, button('Save'));
    final stored = await reload(app, instance);
    expect(stored.certPin, isNull);
    expect(stored.customCa, storedCa);
    await app.stop(tester);
  });

  testWidgets('removes what was trusted, when saved', (tester) async {
    final (app, films) = await start(tester);
    final instance = await addPinned(app, customCa: storedCa);
    await tester.pumpAndSettle();
    go(tester, editInstanceLocation(instance.id));
    await tester.pumpAndSettle();
    films.probed.clear();
    await press(tester, find.text('Advanced'));
    expect(find.textContaining('it alone decides'), findsOneWidget);

    await press(tester, button('Stop trusting this certificate'));
    await press(tester, button('Remove certificate authority'));
    await press(tester, button('Save without testing'));

    final stored = await reload(app, instance);
    expect(stored.certPin, isNull);
    expect(stored.customCa, isNull);
    await app.stop(tester);
  });

  testWidgets('an unrelated edit keeps what was trusted', (tester) async {
    final (app, _) = await start(tester);
    final instance = await addPinned(app, customCa: storedCa);
    await tester.pumpAndSettle();
    go(tester, editInstanceLocation(instance.id));
    await tester.pumpAndSettle();

    await enter(tester, 'name', 'Cinema');
    await press(tester, button('Save without testing'));

    final stored = await reload(app, instance);
    expect(stored.certPin, oldPin);
    expect(stored.customCa, storedCa);
    await app.stop(tester);
  });

  testWidgets('reads a chosen file and refuses a private key', (tester) async {
    var file = utf8.encode('-----BEGIN PRIVATE KEY-----\nAAAA\n');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          certificateFileProvider.overrideWithValue(
            () async => Uint8List.fromList(file),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AuthorityImportScreen(),
        ),
      ),
    );

    await press(tester, button('Choose file'));
    expect(find.textContaining('holds a private key'), findsOneWidget);
    expect(button('Use this authority'), findsNothing);

    file = utf8.encode('nonsense');
    await press(tester, button('Choose file'));
    expect(find.textContaining('not a certificate'), findsOneWidget);

    file = utf8.encode(caPem);
    await press(tester, button('Choose file'));
    expect(button('Use this authority'), findsOneWidget);
  });

  test('a name cannot disguise itself', () {
    expect(certificateName('/O=Home/CN=nas'), 'O=Home\nCN=nas');
    expect(certificateName('/CN=a\u202eb\nc'), 'CN=a\ufffdb\ufffdc');
    expect(certificateName(''), isNull);
    expect(certificateName('/CN=${'a' * 400}')!.length, 301);
  });

  testWidgets('the screens fit with text at twice the size', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final semantics = tester.ensureSemantics();
    final (app, films, _) = await editPinned(tester);
    serve(films, newPin);
    await press(tester, find.text('Advanced'));
    expect(tester.takeException(), isNull);
    await press(tester, button('Test connection'));

    await press(tester, button('Review certificate'));
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await press(tester, button('Import a certificate authority instead'));
    await enter(tester, 'authorityText', caPem);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(field('authorityText'), findsOneWidget);
    semantics.dispose();
    await app.stop(tester);
  });
}
