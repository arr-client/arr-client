/// Profiles and the Home switcher (spec story 1, scenarios 4, 5 and 10).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/navigation_test.dart' show bar, open, usePhone;
import '../../app/support.dart';

/// Does not answer for instances whose name starts with `Lan`, until they are
/// [back], nor for those whose name starts with `Locked`.
class _FlakyModule extends FakeModule {
  _FlakyModule() : super('flaky', offers: {CapabilityKind.library});

  var back = false;

  /// While set, probes wait for it.
  Completer<void>? hold;

  /// The names of the instances probed, one for each probe.
  final probed = <String>[];

  @override
  ServiceResult<ProbeResult> probe(InstanceContext context) async {
    final name = context.instance.name;
    probed.add(name);
    await hold?.future;
    if (name.startsWith('Lan') && !back) return const Err(Unreachable());
    if (name.startsWith('Locked')) return const Err(AuthFailed());
    return super.probe(context);
  }
}

/// A new one for each test.
late _FlakyModule _flaky;

Future<List<String>> _names(TestApp app) async => [
  for (final profile in await app.services.profiles.profiles()) profile.name,
];

Future<Profile> _profile(TestApp app, String name) async =>
    (await app.services.profiles.profiles()).singleWhere(
      (profile) => profile.name == name,
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Opens the screen of profiles from the switcher on Home.
Future<void> _manage(WidgetTester tester) async {
  await _tap(tester, find.byTooltip('Switch profile'));
  // The menu scrolls when the text is large.
  await tester.ensureVisible(find.text('Manage profiles'));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('Manage profiles'));
}

Future<void> _options(WidgetTester tester, String name, String entry) async {
  await _tap(tester, find.byTooltip('Options for $name'));
  await _tap(tester, find.text(entry));
}

Future<void> _name(WidgetTester tester, String name, String confirm) async {
  await tester.enterText(find.byType(TextField), name);
  await _tap(tester, find.widgetWithText(FilledButton, confirm));
}

/// The active mark of the list of profiles.
Finder _activeTile(String name) => find.ancestor(
  of: find.text('Active'),
  matching: find.widgetWithText(ListTile, name),
);

Future<void> _resume(WidgetTester tester) async {
  tester.binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  late TestApp app;

  setUp(() => _flaky = _FlakyModule());

  /// An unreachable instance in the active profile and another profile.
  Future<String> startUnreachable(WidgetTester tester) async {
    usePhone(tester);
    app = await TestApp.start(tester, modules: [movies, _flaky]);
    final id = await app.add(_flaky, 'Lan films');
    await app.addProfile('Away');
    await app.pump(tester);
    expect(find.textContaining('Cannot reach'), findsOneWidget);
    _flaky.probed.clear();
    return id;
  }

  Future<void> start(WidgetTester tester) async {
    usePhone(tester);
    app = await TestApp.start(tester, modules: [movies, series, _flaky]);
  }

  testWidgets('a new empty profile does not become active', (tester) async {
    await start(tester);
    await app.add(movies, 'Films');
    await app.pump(tester);
    await _manage(tester);

    await _tap(tester, find.text('New profile'));
    await _name(tester, '  Away  ', 'Create profile');

    expect(await _names(app), ['Default', 'Away']);
    expect(_activeTile('Default'), findsOneWidget);
    final away = await _profile(app, 'Away');
    expect(await app.services.profiles.instances(away.id), isEmpty);
    await app.stop(tester);
  });

  testWidgets('a name must be 1 to 40 characters and not taken', (
    tester,
  ) async {
    await start(tester);
    await app.pump(tester);
    await _manage(tester);
    await _tap(tester, find.text('New profile'));

    await _name(tester, '   ', 'Create profile');
    expect(find.text('Enter 1 to 40 characters.'), findsOneWidget);
    await _name(tester, 'x' * 41, 'Create profile');
    expect(find.text('Enter 1 to 40 characters.'), findsOneWidget);
    await _name(tester, 'DEFAULT', 'Create profile');
    expect(find.text('Another profile has this name.'), findsOneWidget);
    await _tap(tester, find.text('Cancel'));

    expect(await _names(app), ['Default']);
    await app.stop(tester);
  });

  testWidgets('a copy has the services and sign-ins under new ids', (
    tester,
  ) async {
    await start(tester);
    final films = await app.add(movies, 'Films');
    await app.pump(tester);
    await _manage(tester);

    await _options(tester, 'Default', 'Copy');
    expect(find.text('Copy of Default'), findsOneWidget);
    expect(find.textContaining('sign-in details'), findsOneWidget);
    await _name(tester, 'Away', 'Copy profile');

    final away = await _profile(app, 'Away');
    final copy = (await app.services.profiles.instances(away.id)).single;
    expect(copy.name, 'Films');
    expect(copy.id, isNot(films));
    expect(
      (await app.services.profiles.credential(copy.id))?.apiKey,
      'zq-key-0123456789',
    );
    expect(await app.activeProfile, isNot(away.id));
    await app.stop(tester);
  });

  testWidgets('a new profile can start as a copy', (tester) async {
    await start(tester);
    await app.add(movies, 'Films');
    await app.pump(tester);
    await _manage(tester);
    await _tap(tester, find.text('New profile'));

    await _tap(tester, find.text('No services'));
    await _tap(tester, find.text('Copy of Default').last);
    await _name(tester, 'Away', 'Create profile');

    final away = await _profile(app, 'Away');
    expect(await app.services.profiles.instances(away.id), hasLength(1));
    await app.stop(tester);
  });

  testWidgets('renaming shows on Home, and a taken name is refused', (
    tester,
  ) async {
    await start(tester);
    await app.addProfile('Away');
    await app.pump(tester);
    await _manage(tester);

    await _options(tester, 'Default', 'Rename');
    await _name(tester, 'away', 'Save');
    expect(find.text('Another profile has this name.'), findsOneWidget);
    await _name(tester, 'At home', 'Save');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'At home'), findsOneWidget);
    expect(await _names(app), ['At home', 'Away']);
    await app.stop(tester);
  });

  testWidgets('deleting asks by name and removes the sign-ins', (tester) async {
    await start(tester);
    final away = await app.addProfile('Away');
    final cabin = await app.add(movies, 'Cabin', profileId: away);
    await app.pump(tester);
    await _manage(tester);

    await _options(tester, 'Away', 'Delete');
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Away'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('becomes the active'), findsNothing);
    await _tap(tester, find.text('Cancel'));
    expect(await _names(app), ['Default', 'Away']);

    await _options(tester, 'Away', 'Delete');
    await _tap(tester, find.text('Delete profile'));

    expect(await _names(app), ['Default']);
    expect(await app.services.profiles.credential(cabin), isNull);
    // The last one cannot be deleted.
    await _tap(tester, find.byTooltip('Options for Default'));
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('deleting the active profile says which takes over', (
    tester,
  ) async {
    await start(tester);
    final away = await app.addProfile('Away');
    await app.pump(tester);
    await _manage(tester);

    await _options(tester, 'Default', 'Delete');
    expect(find.textContaining('Away becomes the active'), findsOneWidget);
    await _tap(tester, find.text('Delete profile'));

    expect(await app.activeProfile, away);
    expect(_activeTile('Away'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('the Home switcher switches what the app shows', (tester) async {
    await start(tester);
    await app.add(movies, 'Films');
    final away = await app.addProfile('Away');
    await app.add(series, 'Shows', profileId: away);
    await app.pump(tester);
    await open(tester, 'Library');
    expect(find.widgetWithText(Tab, 'Movies'), findsOneWidget);
    await open(tester, 'Home');

    await _tap(tester, find.byTooltip('Switch profile'));
    final checked = {
      for (final item in tester.widgetList<CheckedPopupMenuItem<Object?>>(
        find.byWidgetPredicate((widget) => widget is CheckedPopupMenuItem),
      ))
        (item.child! as Text).data: item.checked,
    };
    expect(checked, {'Default': true, 'Away': false});
    await _tap(
      tester,
      find.ancestor(
        of: find.text('Away'),
        matching: find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem,
        ),
      ),
    );

    expect(await app.activeProfile, away);
    expect(find.widgetWithText(AppBar, 'Away'), findsOneWidget);
    expect(bar(tester), ['Home', 'Library', 'More']);
    await open(tester, 'Library');
    expect(find.widgetWithText(Tab, 'Series'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Movies'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('a profile can be chosen from the list', (tester) async {
    await start(tester);
    final away = await app.addProfile('Away');
    await app.pump(tester);
    await _manage(tester);

    await _tap(tester, find.text('Away'));

    expect(await app.activeProfile, away);
    expect(_activeTile('Away'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('Services leads to the profiles', (tester) async {
    await start(tester);
    await app.pump(tester);
    await open(tester, 'More');
    await _tap(tester, find.text('Services'));

    await _tap(tester, find.byTooltip('Manage profiles'));

    expect(find.widgetWithText(AppBar, 'Profiles'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('unreachable services offer another profile, never switching', (
    tester,
  ) async {
    await start(tester);
    final home = await app.activeProfile;
    await app.add(_flaky, 'Lan films');
    final away = await app.addProfile('Away');
    await app.add(_flaky, 'Films', profileId: away);
    await app.pump(tester);

    expect(find.textContaining('Cannot reach Lan films.'), findsOneWidget);
    expect(await app.activeProfile, home);

    await app.add(_flaky, 'Lan shows');
    await tester.pumpAndSettle();
    expect(find.textContaining('Cannot reach 2 services.'), findsOneWidget);

    await _tap(tester, find.text('Switch to Away'));

    expect(await app.activeProfile, away);
    expect(find.textContaining('Cannot reach'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('no offer without another profile or for another failure', (
    tester,
  ) async {
    await start(tester);
    await app.add(_flaky, 'Lan films');
    await app.pump(tester);
    expect(find.textContaining('Cannot reach'), findsNothing);

    // A rejected key is not mended by another address.
    final away = await app.addProfile('Away');
    await app.add(_flaky, 'Locked', profileId: away);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cannot reach'), findsOneWidget);
    await _tap(tester, find.text('Switch to Away'));

    expect(find.textContaining('Cannot reach'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('trying again finds that a service is back', (tester) async {
    await startUnreachable(tester);

    await _tap(tester, find.text('Try again'));
    // Still gone: one probe, and the offer stays.
    expect(_flaky.probed, ['Lan films']);
    expect(find.textContaining('Cannot reach'), findsOneWidget);

    _flaky.back = true;
    await _tap(tester, find.text('Try again'));

    expect(_flaky.probed, ['Lan films', 'Lan films']);
    expect(find.textContaining('Cannot reach'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('the offer stays while a service is checked again', (
    tester,
  ) async {
    await startUnreachable(tester);
    final hold = _flaky.hold = Completer<void>();

    await _tap(tester, find.text('Try again'));

    expect(find.textContaining('Cannot reach'), findsOneWidget);
    expect(find.text('Switch to Away'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Checking'))
          .onPressed,
      isNull,
    );

    _flaky.back = true;
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Cannot reach'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('resuming checks once more only what failed', (tester) async {
    await startUnreachable(tester);
    await app.add(_flaky, 'Films');
    await tester.pumpAndSettle();
    _flaky.probed.clear();

    await _resume(tester);
    expect(_flaky.probed, ['Lan films']);
    expect(find.textContaining('Cannot reach'), findsOneWidget);

    _flaky.back = true;
    await _resume(tester);

    expect(_flaky.probed, ['Lan films', 'Lan films']);
    expect(find.textContaining('Cannot reach'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('resuming sends nothing for a latched service', (tester) async {
    final films = await startUnreachable(tester);
    await app.services.profiles.markAuthFailed(films);
    await tester.pumpAndSettle();

    await _resume(tester);

    expect(_flaky.probed, isEmpty);
    await app.stop(tester);
  });

  testWidgets('targets are large and labelled, and large text fits', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    usePhone(tester, const Size(320, 640));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    app = await TestApp.start(tester, modules: [_flaky]);
    const long = 'A profile with a very long name';
    await app.add(_flaky, 'Lan films with quite a long name');
    for (final name in [long, 'Away', 'Cabin', 'Office']) {
      await app.addProfile(name);
    }
    await app.pump(tester);

    Future<void> check() async {
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    }

    await check();
    await _manage(tester);
    await check();
    await _tap(tester, find.text('New profile'));
    await _tap(tester, find.text('No services'));
    await _tap(tester, find.text('Copy of Default').last);
    expect(tester.takeException(), isNull);
    await app.stop(tester);
    semantics.dispose();
  });
}
