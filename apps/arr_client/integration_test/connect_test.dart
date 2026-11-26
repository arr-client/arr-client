/// User story 1, "Connect my services" (spec.md), in the running app on a
/// device, against servers that the test runs on the device itself.
library;

import 'package:arr_client/features/onboarding/certificate/certificate_widgets.dart';
import 'package:arr_client/features/onboarding/test_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import 'support/certificates.dart';
import 'support/fake_server.dart';
import 'support/fake_services.dart';
import 'support/flows.dart';
import 'support/harness.dart';

const radarrVersion = '5.20.0.1000';
const sonarrVersion = '4.0.9.2000';
const key = 'zq-key-0123456789';
const otherKey = 'zq-other-9876543210';

void main() {
  appTest('shows only what the added services offer, over http', (app) async {
    final radarr = await app.serve(
      fakeRadarr(
        apiKey: key,
        movies: ['Example Movie'],
        queue: [halfDoneDownload('Example.Movie.2020')],
      ).call,
    );
    // Newer than any version that was tested.
    final sonarr = await app.serve(
      fakeSonarr(apiKey: key, version: '99.0.0.1').call,
    );
    final qbittorrent = await app.serve(fakeQbittorrent(apiKey: key));
    final library = app.destination(strings.navLibrary);
    final activity = app.destination(strings.navActivity);
    final discover = app.destination(strings.navDiscover);
    final movies = find.widgetWithText(Tab, strings.tabMovies);
    final series = find.widgetWithText(Tab, strings.tabSeries);

    // A first launch: a profile is there, and nothing is offered yet.
    await app.waitFor(find.text(strings.noServicesYet));
    expect(app.activeProfile('Default'), findsOneWidget);
    expect(library, findsNothing);
    expect(activity, findsNothing);
    expect(discover, findsNothing);
    expect(find.byTooltip(strings.search), findsNothing);

    // A movie server brings the movie areas, and only those.
    await app.addService(
      'Radarr',
      address: radarr.address,
      apiKey: key,
      version: radarrVersion,
    );
    await app.waitFor(library);
    expect(activity, findsOneWidget);
    expect(discover, findsNothing);
    expect(find.byTooltip(strings.search), findsOneWidget);
    await app.goTo(strings.navLibrary);
    await app.waitFor(find.text('Example Movie'));
    expect(movies, findsOneWidget);
    expect(series, findsNothing);

    // Without a download client, the queue has the progress of the library
    // service, and nothing about a client.
    await app.goTo(strings.navActivity);
    await app.waitFor(find.textContaining('50%'));
    expect(find.textContaining('qBittorrent'), findsNothing);

    // A series server brings series. A version newer than tested connects, and
    // says so.
    await app.openServices();
    await app.openAddForm('Sonarr');
    await app.fillForm(address: sonarr.address, apiKey: key);
    await app.testConnection(strings.testPassed('Sonarr', '99.0.0.1'));
    expect(find.text(strings.testNewerVersion), findsOneWidget);
    await app.closeForm(strings.formAdd);
    await app.waitFor(find.text(strings.statusNewerVersion('99.0.0.1')));
    await app.goTo(strings.navLibrary);
    await app.waitFor(series);
    expect(movies, findsOneWidget);

    // A download client brings no area of its own.
    await app.openServices();
    await app.addService(
      'qBittorrent',
      address: qbittorrent.address,
      apiKey: key,
      version: '5.3.1',
    );
    expect(library, findsOneWidget);
    expect(activity, findsOneWidget);
    expect(discover, findsNothing);

    // A disabled service contributes nothing and gets no request, also after
    // the app is opened again; its settings are kept.
    await app.serviceAction('Sonarr', strings.serviceDisable);
    await app.waitFor(find.text(strings.serviceDisabled));
    final sent = sonarr.requests.length;
    await app.restart();
    await app.goTo(strings.navLibrary);
    await app.waitFor(find.text('Example Movie'));
    expect(series, findsNothing);
    await app.goTo(strings.navActivity);
    await app.waitFor(find.textContaining('50%'));
    await app.openServices();
    expect(find.text(sonarr.address), findsOneWidget);
    expect(sonarr.requests, hasLength(sent));

    // Removing the movie server takes its areas away.
    await app.serviceAction('Radarr', strings.serviceRemove);
    await app.tap(app.button(strings.removeService));
    await app.waitUntilGone(find.byTooltip(strings.serviceOptions('Radarr')));
    await app.waitUntilGone(library);
    expect(activity, findsNothing);
    expect(find.byTooltip(strings.search), findsNothing);
  });

  appTest('says of each failure which it is and what to do', (app) async {
    var answer = (ReceivedRequest request) => const Reply(500);
    final server = await app.serve((request) => answer(request));
    final untrusted = await app.serve(
      fakeRadarr(apiKey: key).call,
      certificate: selfSigned,
    );
    // A port that nothing listens on.
    final closed = await app.serve((_) => const Reply(500));
    final nothing = closed.address;
    await closed.close();

    await app.openAddForm('Radarr');
    await app.fillForm(apiKey: key);

    final titles = <String>[];
    final messages = <String>[];
    // Tests [address] and expects the failure [title].
    Future<void> expectFailure(String address, String title) async {
      await app.fillForm(address: address);
      await app.testConnection(title);
      final texts = [
        for (final element
            in find
                .descendant(
                  of: find.byType(TestResult),
                  matching: find.byType(Text),
                )
                .evaluate())
          (element.widget as Text).data!,
      ];
      expect(texts.first, title);
      expect(texts[1].trim(), isNotEmpty, reason: 'what to do about "$title"');
      titles.add(title);
      messages.add(texts[1]);
      expect(app.button(strings.formSaveAnyway), findsOneWidget);
    }

    // The same address with another answer. The address is entered anew, which
    // discards the previous result.
    Future<void> expectAnswer(Reply reply, String title) async {
      answer = (_) => reply;
      await app.fillForm(address: '');
      await expectFailure(server.address, title);
    }

    await expectFailure(nothing, strings.testUnreachableTitle);
    await expectFailure(
      'http://no-such-server.invalid:7878',
      strings.testDnsTitle,
    );
    await expectFailure(
      untrusted.address,
      strings.testCertificateUntrustedTitle,
    );
    // Nothing is sent to a server whose certificate is not trusted.
    expect(untrusted.requests, isEmpty);
    await expectAnswer(const Reply(401), strings.testApiKeyRejectedTitle);
    await expectAnswer(
      Reply.json({'appName': 'Sonarr', 'version': sonarrVersion}),
      strings.testWrongServiceTitle('Radarr'),
    );
    await expectAnswer(
      const Reply.webPage('<html><body>Sign in</body></html>'),
      strings.testProxyTitle,
    );
    await expectAnswer(
      Reply.redirect('http://sign-in.invalid/login'),
      strings.testRedirectedTitle,
    );
    await expectAnswer(
      const Reply.webPage('Bad Request - Invalid Hostname', status: 400),
      strings.testHostRejectedTitle,
    );
    await expectAnswer(
      Reply.json({'appName': 'Radarr', 'version': '4.0.0.1'}),
      strings.testVersionTitle,
    );

    // Permission: the app explains before the system would ask.
    await app.fillForm(address: 'http://$deniedHost:7878');
    await app.tap(app.button(strings.formTest));
    await app.waitFor(find.text(strings.localNetworkExplanation));
    await app.tap(app.button(strings.localNetworkContinue));
    await app.waitFor(find.text(strings.testPermissionTitle));
    titles.add(strings.testPermissionTitle);
    messages.add(
      lookupUiLocalizations(const Locale('en')).failureLocalNetworkPermission,
    );
    expect(find.text(messages.last), findsOneWidget);

    expect(titles, hasLength(10), reason: 'one for each class of FR-007');
    expect(titles.toSet(), hasLength(titles.length));
    expect(messages.toSet(), hasLength(messages.length));
  });

  appTest('saves a rejected key without sending it again', (app) async {
    final radarr = fakeRadarr(apiKey: key, movies: ['Example Movie']);
    final server = await app.serve(radarr.call);

    await app.openAddForm('Radarr');
    await app.fillForm(address: server.address, apiKey: otherKey);
    await app.testConnection(strings.testApiKeyRejectedTitle);
    await app.closeForm(strings.formSaveAnyway);
    await app.openServices();
    await app.waitFor(find.textContaining(strings.statusApiKeyStopped));

    final sent = server.requests.length;
    await app.restart();
    await app.openServices();
    await app.waitFor(find.textContaining(strings.statusApiKeyStopped));
    expect(server.requests, hasLength(sent));

    // Editing the key tries again.
    await app.editService('Radarr');
    await app.fillForm(apiKey: key);
    await app.testConnection(strings.testPassed('Radarr', radarrVersion));
    await app.closeForm(strings.formSave);
    await app.waitFor(find.text(strings.testPassed('Radarr', radarrVersion)));
    await app.goTo(strings.navLibrary);
    await app.waitFor(find.text('Example Movie'));
  });

  appTest('accepts a self-signed certificate, and no other unasked', (
    app,
  ) async {
    final server = await app.serve(
      fakeRadarr(apiKey: key, movies: ['Example Movie']).call,
      certificate: selfSigned,
    );
    Finder fingerprint(TestCertificate certificate) => find.byWidgetPredicate(
      (widget) => widget is Fingerprint && widget.sha256 == certificate.sha256,
    );

    await app.openAddForm('Radarr');
    await app.fillForm(address: server.address, apiKey: key);
    await app.testConnection(strings.testCertificateUntrustedTitle);
    await app.tap(app.button(strings.testReviewCertificate));
    await app.waitFor(fingerprint(selfSigned));
    await app.tap(find.text(strings.certificateChecked));
    await app.tap(app.button(strings.certificateTrust));
    // Accepting tests again.
    await app.waitFor(find.text(strings.testPassed('Radarr', radarrVersion)));
    await app.closeForm(strings.formAdd);
    await app.goTo(strings.navLibrary);
    await app.waitFor(find.text('Example Movie'));

    // The server comes back with another certificate.
    await server.present(otherSelfSigned);
    final sent = server.requests.length;
    await app.restart();
    await app.openServices();
    await app.waitFor(find.text(strings.testCertificateChangedTitle));

    // Keeping the accepted one leaves it refused.
    await app.tap(app.button(strings.testReviewCertificate));
    await app.testConnection(strings.testCertificateChangedTitle);
    await app.tap(app.button(strings.testReviewCertificate));
    await app.waitFor(fingerprint(otherSelfSigned));
    expect(fingerprint(selfSigned), findsOneWidget);
    await app.tap(app.button(strings.certificateKeep));
    await app.waitFor(find.text(strings.testCertificateChangedTitle));
    expect(server.requests, hasLength(sent));

    // Accepting the new one connects again.
    await app.tap(app.button(strings.testReviewCertificate));
    await app.tap(find.text(strings.certificateChangeChecked));
    await app.tap(app.button(strings.certificateReplace));
    await app.waitFor(find.text(strings.testPassed('Radarr', radarrVersion)));
    await app.closeForm(strings.formSave);
    await app.goTo(strings.navLibrary);
    await app.waitFor(find.text('Example Movie'));
    expect(server.requests.length, greaterThan(sent));
  });

  appTest('keeps each profile apart: copy, switch, rename, delete', (
    app,
  ) async {
    final home = await app.serve(
      fakeRadarr(apiKey: key, movies: ['Home Movie']).call,
    );
    final away = await app.serve(
      fakeRadarr(apiKey: otherKey, movies: ['Away Movie']).call,
    );

    Future<void> expectLibrary(String movie, {required String not}) async {
      await app.goTo(strings.navLibrary);
      await app.waitFor(find.text(movie));
      expect(find.text(not), findsNothing);
    }

    await app.addService(
      'Radarr',
      address: home.address,
      apiKey: key,
      version: radarrVersion,
    );
    await app.openServices();
    await app.tap(find.byTooltip(strings.manageProfiles));

    // The only profile cannot be deleted.
    await app.tap(find.byTooltip(strings.profileOptions('Default')));
    await app.waitFor(find.text(strings.profileCopy));
    expect(find.text(strings.profileDelete), findsNothing);

    // A copy, with the address and the key.
    await app.tap(find.text(strings.profileCopy));
    await app.enterInto(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Away',
    );
    await app.tap(app.button(strings.copyProfile));
    await app.waitFor(find.byTooltip(strings.profileOptions('Away')));
    await app.back();

    // Switching is from Home. The copy works as it is.
    await app.switchProfile('Away');
    await expectLibrary('Home Movie', not: 'Away Movie');

    // Another address and key in the copy.
    await app.openServices();
    await app.editService('Radarr');
    await app.fillForm(address: away.address, apiKey: otherKey);
    await app.testConnection(strings.testPassed('Radarr', radarrVersion));
    await app.closeForm(strings.formSave);
    final sentHome = home.requests.length;
    await expectLibrary('Away Movie', not: 'Home Movie');
    expect(home.requests, hasLength(sentHome));

    // The first profile keeps its own.
    await app.switchProfile('Default');
    await expectLibrary('Home Movie', not: 'Away Movie');
    await app.openServices();
    expect(find.text(home.address), findsOneWidget);
    expect(find.text(away.address), findsNothing);

    // Which profile is active, and what each holds, is kept.
    await app.restart();
    await app.waitFor(app.activeProfile('Default'));
    await app.switchProfile('Away');
    await expectLibrary('Away Movie', not: 'Home Movie');
    await app.switchProfile('Default');

    // Rename.
    await app.openServices();
    await app.tap(find.byTooltip(strings.manageProfiles));
    await app.profileAction('Away', strings.profileRename);
    await app.enterInto(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Travel',
    );
    await app.tap(app.button(strings.save));
    await app.waitFor(find.byTooltip(strings.profileOptions('Travel')));

    // Deleting asks first, naming the profile, and erases its stored key.
    Future<bool> stores(String secret) async =>
        (await app.secrets.values()).any((value) => value.contains(secret));
    expect(await stores(otherKey), isTrue);
    await app.profileAction('Travel', strings.profileDelete);
    await app.waitFor(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Travel'),
      ),
    );
    await app.tap(app.button(lookupUiLocalizations(const Locale('en')).cancel));
    expect(find.byTooltip(strings.profileOptions('Travel')), findsOneWidget);
    await app.profileAction('Travel', strings.profileDelete);
    await app.tap(app.button(strings.deleteProfile));
    await app.waitUntilGone(find.byTooltip(strings.profileOptions('Travel')));
    expect(await stores(otherKey), isFalse);
    expect(await stores(key), isTrue);
  });
}
