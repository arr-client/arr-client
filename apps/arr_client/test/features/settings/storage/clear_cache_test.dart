/// Clearing the cached data (spec story 2, scenario 8; FR-061).
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/fake_library.dart';
import '../../../app/navigation_test.dart' show open, usePhone;
import '../../../app/support.dart';

final _library = FakeLibrary();

final _films = FakeModule(
  'movies',
  offers: {CapabilityKind.library},
  library: (context) => _library,
);

/// A directory of the test's own, as clearing deletes what is in it.
Directory _cacheDirectory() {
  final directory = Directory.systemTemp.createTempSync('clear_cache_test_');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}

Future<TestApp> _start(
  WidgetTester tester, {
  required Future<Directory> Function() cacheDirectory,
}) async {
  usePhone(tester);
  _library
    ..items = []
    ..failure = null;
  final app = await TestApp.start(
    tester,
    modules: [_films],
    cacheDirectory: cacheDirectory,
  );
  await app.pump(tester);
  return app;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  await open(tester, 'More');
  await _tap(tester, find.text('Settings'));
}

final _entry = find.widgetWithText(ListTile, 'Clear cached data');

/// Presses the confirm button and waits for [message]. The files are deleted
/// on the real clock, and until then a progress indicator never settles.
Future<void> _confirm(WidgetTester tester, String message) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Clear cached data'));
  await settle(tester, until: () => find.text(message).evaluate().isNotEmpty);
  await tester.pumpAndSettle();
  expect(find.text(message), findsOneWidget);
}

/// Saves one movie as the cache of the instance [id].
Future<void> _save(TestApp app, String id) =>
    app.services.cache.scope(id).replace(MediaKind.movie, [
      CacheEntry(
        instanceId: id,
        kind: MediaKind.movie,
        remoteId: 1,
        sortTitle: 'alpha',
        state: ItemState.downloaded,
        monitored: true,
        tagIds: const [],
        rawJson: '{}',
        fetchedAt: DateTime.utc(2026),
      ),
    ]);

Future<Object?> _saved(TestApp app, String id) =>
    app.services.cache.scope(id).read(MediaKind.movie);

File _artwork(Directory directory) =>
    File('${directory.path}/artwork/seeded/picture');

Movie _movie(String id, String title) => Movie(
  ref: ItemRef(instanceId: id, kind: MediaKind.movie, remoteId: 1),
  title: title,
  sortTitle: title.toLowerCase(),
  monitored: true,
  state: ItemState.downloaded,
);

void main() {
  testWidgets('says what is removed, and cancelling removes nothing', (
    tester,
  ) async {
    final directory = _cacheDirectory();
    final app = await _start(tester, cacheDirectory: () async => directory);
    final id = await app.add(_films, 'Films');
    await _save(app, id);
    _artwork(directory).createSync(recursive: true);
    await _openSettings(tester);

    await _tap(tester, _entry);

    expect(
      find.text('Library data and artwork of all profiles'),
      findsOneWidget,
    );
    expect(find.textContaining('cannot be viewed offline'), findsOneWidget);
    expect(
      find.textContaining(
        'Services, sign-in details, profiles and settings are kept.',
      ),
      findsOneWidget,
    );

    await _tap(tester, find.text('Cancel'));

    expect(await _saved(app, id), isNotNull);
    expect(_artwork(directory).existsSync(), isTrue);
    expect(find.text('Cached data cleared'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('removes the cache of all profiles and keeps everything else', (
    tester,
  ) async {
    final directory = _cacheDirectory();
    final app = await _start(tester, cacheDirectory: () async => directory);
    final here = await app.add(_films, 'Films');
    final away = await app.addProfile('Away');
    final there = await app.add(_films, 'Remote', profileId: away);
    await _save(app, here);
    await _save(app, there);
    _artwork(directory).createSync(recursive: true);
    final services = app.services;
    final profile = await app.activeProfile;
    await services.preferences.setThemeMode(AppThemeMode.dark);
    await services.preferences.saveView(
      profile,
      MediaKind.movie,
      const LibraryView(layout: LibraryLayout.list),
    );
    await tester.pumpAndSettle();
    await _openSettings(tester);

    await _tap(tester, _entry);
    await _confirm(tester, 'Cached data cleared');

    expect(await _saved(app, here), isNull);
    expect(await _saved(app, there), isNull);
    expect(_artwork(directory).existsSync(), isFalse);

    expect(await services.profiles.profiles(), hasLength(2));
    for (final id in [here, there]) {
      final instance = (await services.profiles.instance(id))!;
      final credential = await services.profiles.credential(instance.id);
      expect(credential?.apiKey, 'zq-key-0123456789');
    }
    final preferences = await services.preferences.read();
    expect(preferences.themeMode, AppThemeMode.dark);
    expect(preferences.activeProfileId, profile);
    expect(
      (await services.preferences.view(profile, MediaKind.movie)).layout,
      LibraryLayout.list,
    );
    await app.stop(tester);
  });

  testWidgets('a library already shown is loaded from the server again', (
    tester,
  ) async {
    final directory = _cacheDirectory();
    final app = await _start(tester, cacheDirectory: () async => directory);
    final id = await app.add(_films, 'Films');
    _library.items = [_movie(id, 'Before')];
    await tester.pumpAndSettle();
    await open(tester, 'Library');
    expect(find.text('Before'), findsOneWidget);
    final listed = _library.listed;

    await _openSettings(tester);
    await _tap(tester, _entry);
    _library.items = [_movie(id, 'After')];
    await _confirm(tester, 'Cached data cleared');
    await open(tester, 'Library');

    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
    expect(_library.listed, listed + 1);
    await app.stop(tester);
  });

  testWidgets('what was removed is not shown while the server is away', (
    tester,
  ) async {
    final directory = _cacheDirectory();
    final app = await _start(tester, cacheDirectory: () async => directory);
    final id = await app.add(_films, 'Films');
    _library.items = [_movie(id, 'Before')];
    await tester.pumpAndSettle();
    await open(tester, 'Library');
    expect(find.text('Before'), findsOneWidget);

    await _openSettings(tester);
    await _tap(tester, _entry);
    _library.failure = const Unreachable();
    await _confirm(tester, 'Cached data cleared');
    await open(tester, 'Library');

    expect(find.text('Before'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('what cannot be removed is reported, the rest still goes', (
    tester,
  ) async {
    final app = await _start(
      tester,
      cacheDirectory: () async =>
          throw const FileSystemException('seeded', '/seeded/path'),
    );
    final id = await app.add(_films, 'Films');
    await _save(app, id);
    await _openSettings(tester);

    await _tap(tester, _entry);
    await _confirm(tester, 'Not all cached data could be removed. Try again.');

    expect(await _saved(app, id), isNull);
    expect(
      app.services.log.entries.last.message,
      'The cached artwork could not be removed (FileSystemException)',
    );
    // It can be tried again.
    expect(tester.widget<ListTile>(_entry).enabled, isTrue);
    await app.stop(tester);
  });

  testWidgets('the entry and its confirmation work with large text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final directory = _cacheDirectory();
    final app = await _start(tester, cacheDirectory: () async => directory);
    await _openSettings(tester);

    await _tap(tester, _entry);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await _confirm(tester, 'Cached data cleared');
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await app.stop(tester);
  });
}
