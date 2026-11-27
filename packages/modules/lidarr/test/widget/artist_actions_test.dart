// What the user can do on the artist and album screens (spec stories 5 and 8),
// over the module's own adapters and the recorded server.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../contract/support.dart';
import 'artist_screens_test.dart' show named;
import 'support.dart';

const _artistScreen = ModuleRoute(
  instanceId: instanceId,
  path: 'lidarr/artists/1',
);

const _albumScreen = ModuleRoute(
  instanceId: instanceId,
  path: 'lidarr/albums/1',
);

const _delete = 'Delete the file of Song 1';

void main() {
  late FakeLidarr server;
  late Screens screens;

  setUp(() {
    server = named();
    screens = Screens(server: server);
  });

  Future<void> open(WidgetTester tester, ModuleRoute route) async {
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await screens.open(tester, route);
  }

  // Progress indicators never settle.
  Future<void> step(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<void> choose(WidgetTester tester, String entry) async {
    await tester.tap(find.byTooltip('More actions'));
    await step(tester);
    await tester.tap(find.text(entry));
    await step(tester);
  }

  String name(ServiceRequest request) =>
      '${request.method.name} ${request.path.replaceFirst('api/v1/', '')}';

  List<String> written() => [
    for (final request in server.writes) name(request),
  ];

  int count(String request) =>
      server.requests.where((sent) => name(sent) == request).length;

  SwitchListTile toggle(WidgetTester tester) =>
      tester.widget(find.byType(SwitchListTile));

  group('monitoring', () {
    testWidgets('an artist is written whole, and read again', (tester) async {
      await open(tester, _artistScreen);
      final reads = count('get album');

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(written(), ['put artist/1']);
      expect(
        (sentBody(server.writes.single)! as Map<String, Object?>)['monitored'],
        isFalse,
      );
      expect(find.text('The artist is no longer monitored'), findsOneWidget);
      expect(count('get album'), reads + 1);
    });

    testWidgets('an album is written on its own, and the artist screen below '
        'is read again', (tester) async {
      await open(tester, _artistScreen);
      await screens.open(tester, _albumScreen);
      final reads = count('get artist/1');

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(written(), ['put album/monitor']);
      expect(sentBody(server.writes.single), {
        'albumIds': [1],
        'monitored': false,
      });
      expect(find.text('The album is no longer monitored'), findsOneWidget);
      expect(count('get artist/1'), greaterThan(reads));
    });

    testWidgets('a refused change is taken back', (tester) async {
      await open(tester, _albumScreen);
      server.writeAnswer = FakeLidarr.body('', status: 403, write: true);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(toggle(tester).value, isTrue);
      expect(written(), ['put album/monitor']);
    });
  });

  for (final (screen, route, command, ids) in [
    ('artist', _artistScreen, 'ArtistSearch', {'artistId': 1}),
    (
      'album',
      _albumScreen,
      'AlbumSearch',
      {
        'albumIds': [1],
      },
    ),
  ]) {
    testWidgets('the $screen screen searches automatically', (tester) async {
      server.command = record(commandFixtures[command]!);
      await open(tester, route);

      await tester.tap(find.text('Search automatically'));
      await step(tester);

      expect(sentBody(server.writes.single), {'name': command, ...ids});
      await screens.back(tester);
    });
  }

  testWidgets('both screens open an interactive search of what they show', (
    tester,
  ) async {
    await open(tester, _artistScreen);
    await tester.tap(find.text('Interactive search'));
    await screens.open(tester, _albumScreen);
    await tester.tap(find.text('Interactive search'));

    expect(screens.navigator.opened, [
      ('releases', MediaTarget(artistRef(1))),
      ('releases', MediaTarget(albumRef(1))),
    ]);
  });

  testWidgets('an artist is edited and deleted by the app, and read again '
      'after', (tester) async {
    await open(tester, _artistScreen);
    await choose(tester, 'Edit artist');
    await choose(tester, 'Delete artist');
    final reads = count('get artist/1');

    screens.navigator.closed.complete();
    await tester.pumpAndSettle();

    expect(screens.navigator.opened, [
      ('edit', artistRef(1)),
      ('delete', artistRef(1)),
    ]);
    expect(count('get artist/1'), greaterThan(reads));
    expect(server.writes, isEmpty);
  });

  testWidgets('an album is deleted by the app; it has no settings of its own '
      'to edit, nor files to rescan', (tester) async {
    await open(tester, _albumScreen);
    await tester.tap(find.byTooltip('More actions'));
    await step(tester);
    expect(find.text('Edit artist'), findsNothing);
    expect(find.text('Rescan files'), findsNothing);

    await tester.tap(find.text('Delete album'));
    await step(tester);

    expect(screens.navigator.opened, [('delete', albumRef(1))]);
  });

  for (final (screen, route, entry, command) in [
    ('artist', _artistScreen, 'Refresh metadata', 'RefreshArtist'),
    ('artist', _artistScreen, 'Rescan files', 'RescanFolders'),
    ('album', _albumScreen, 'Refresh metadata', 'RefreshAlbum'),
  ]) {
    testWidgets('$entry on the $screen screen starts $command', (tester) async {
      server.command = record(commandFixtures[command]!);
      await open(tester, route);

      await choose(tester, entry);

      expect(
        (sentBody(server.writes.single)! as Map<String, Object?>)['name'],
        command,
      );
      await screens.back(tester);
    });
  }

  group('deleting a file', () {
    Future<void> ask(WidgetTester tester) async {
      await open(tester, _albumScreen);
      await tester.tap(find.byTooltip(_delete));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Delete file'));
      await tester.pumpAndSettle();
    }

    testWidgets('names the file, and cancelling sends nothing', (tester) async {
      await ask(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('/redacted/175.mp3'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('this file of Song 1'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(server.writes, isEmpty);
    });

    testWidgets('sends it once, and reads the tracks again', (tester) async {
      await ask(tester);
      final reads = count('get track');
      server.trackFiles.removeWhere((file) => file['id'] == 13);
      byId(server.tracks, 1)
        ..['hasFile'] = false
        ..['trackFileId'] = 0;

      await confirm(tester);

      expect(written(), ['delete trackfile/13']);
      expect(find.text('The file was deleted'), findsOneWidget);
      expect(count('get track'), reads + 1);
      expect(find.byTooltip(_delete), findsNothing);
    });

    testWidgets('sends nothing if the file is no longer the one listed', (
      tester,
    ) async {
      await ask(tester);
      byId(server.trackFiles, 13)['path'] = '/redacted/other.flac';
      // As pulling down does, while the dialog is open.
      await tester
          .widget<RefreshIndicator>(
            find.byType(RefreshIndicator, skipOffstage: false),
          )
          .onRefresh();
      await tester.pumpAndSettle();

      await confirm(tester);

      expect(server.writes, isEmpty);
      expect(find.textContaining('Nothing was deleted'), findsOneWidget);
    });

    testWidgets('that fails says why, and can be asked for again', (
      tester,
    ) async {
      await ask(tester);
      server.writeAnswer = FakeLidarr.body('', status: 403, write: true);

      await confirm(tester);

      final context = tester.element(find.byType(Scaffold).last);
      expect(
        find.text(failureMessage(context, const Forbidden())),
        findsOneWidget,
      );
      expect(written(), ['delete trackfile/13']);
      expect(find.byTooltip(_delete), findsOneWidget);
    });
  });
}
