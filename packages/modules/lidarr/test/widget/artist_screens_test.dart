// The artist and album screens (T118): what they show, over the module's own
// adapters and the recorded server.

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../contract/support.dart';
import 'support.dart';

const _artist = 'The Artist';

/// A server whose artist and albums have names to tell them apart.
FakeLidarr named() {
  final server = FakeLidarr();
  byId(server.artists, 1)['artistName'] = _artist;
  for (final (id, title) in [(1, 'First'), (2, 'Second'), (3, 'Third')]) {
    final album = byId(server.albums, id);
    album['title'] = title;
    (album['artist']! as Map<String, Object?>)['artistName'] = _artist;
  }
  for (final track in server.tracks) {
    track['trackNumber'] = '${track['absoluteTrackNumber']}';
    track['title'] = 'Song ${track['id']}';
  }
  return server;
}

ModuleRoute _route(Screens screens, ItemRef ref) =>
    screens.harness.library.detailRoute(ref);

void _tall(WidgetTester tester, [Size size = const Size(400, 4000)]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  late FakeLidarr server;
  late Screens screens;

  setUp(() {
    server = named();
    screens = Screens(server: server);
  });

  testWidgets('an artist shows its facts, albums by type, history and the '
      'download slot', (tester) async {
    _tall(tester);
    byId(server.albums, 2)['albumType'] = 'Single';
    byId(server.albums, 3)['albumType'] = 'EP';
    await screens.open(tester, _route(screens, artistRef(1)));

    expect(find.text(_artist), findsNWidgets(2)); // App bar and header.
    expect(find.text('Monitored'), findsOneWidget);
    expect(screens.slots.map((slot) => (slot.name, slot.item)).toSet(), {
      (DetailSlotName.downloadProgress, artistRef(1)),
    });
    for (final name in ['Quality profile', 'Metadata profile', 'Tags']) {
      expect(find.text(name), findsOneWidget);
    }
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Albums'), lessThan(top('First')));
    expect(top('First'), lessThan(top('EPs')));
    expect(top('EPs'), lessThan(top('Third')));
    expect(top('Third'), lessThan(top('Singles')));
    expect(top('Singles'), lessThan(top('Second')));

    await tester.tap(find.text('Show all history'));
    expect(screens.navigator.histories, [artistRef(1)]);
  });

  testWidgets('albums of one type are listed newest first, and a type the app '
      'does not know by the server\'s word', (tester) async {
    _tall(tester);
    byId(server.albums, 2)['albumType'] = 'Mixtape';
    await screens.open(tester, _route(screens, artistRef(1)));

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    // Third is of 2008, First of 1997.
    expect(top('Third'), lessThan(top('First')));
    expect(top('First'), lessThan(top('Mixtape')));
  });

  testWidgets('an album lists its tracks with their files, and opens from its '
      'artist and back', (tester) async {
    _tall(tester);
    server.queue.clear();
    await screens.open(tester, _route(screens, artistRef(1)));
    screens.slots.clear();

    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();

    expect(find.text('1. Song 1'), findsOneWidget);
    expect(find.text('4:42'), findsOneWidget);
    expect(find.textContaining('MP3-320'), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, '1. Song 1'),
        matching: find.text('/redacted/175.mp3'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Delete the file of Song 1'), findsOneWidget);
    expect(find.byTooltip('Delete the file of Song 4'), findsNothing);
    expect(find.text('Missing'), findsNWidgets(2));
    // The artist screen beneath builds its own again.
    expect(
      {
        for (final slot in screens.slots)
          if (slot.item.kind == MediaKind.album)
            (slot.name, slot.item, slot.parent),
      },
      {(DetailSlotName.downloadProgress, albumRef(1), artistRef(1))},
    );

    await tester.tap(find.widgetWithText(ListTile, _artist));
    await tester.pumpAndSettle();
    expect(find.text('Albums'), findsOneWidget);
  });

  testWidgets('a track without a file shows as downloading while its album is '
      'queued', (tester) async {
    _tall(tester);
    await screens.open(tester, _route(screens, albumRef(1)));

    // The album's header, and its two tracks without a file.
    expect(find.text('Downloading'), findsNWidgets(3));
    expect(find.text('Downloaded'), findsNWidgets(3));
  });

  testWidgets('the tracks of several discs are under a heading for each', (
    tester,
  ) async {
    _tall(tester);
    byId(server.tracks, 5)['mediumNumber'] = 2;
    await screens.open(tester, _route(screens, albumRef(1)));

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Disc 1'), lessThan(top('1. Song 1')));
    expect(top('4. Song 4'), lessThan(top('Disc 2')));
    expect(top('Disc 2'), lessThan(top('5. Song 5')));
  });

  testWidgets('what was saved stays, with its age, while offline, and nothing '
      'can be changed', (tester) async {
    _tall(tester);
    await screens.open(tester, _route(screens, albumRef(1)));
    await screens.back(tester);
    server.goOffline();

    await screens.open(tester, _route(screens, albumRef(1)));

    expect(find.textContaining('Saved data from'), findsOneWidget);
    expect(find.text('1. Song 1'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Delete the file of Song 1'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );

    server.always = null;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saved data from'), findsNothing);
  });

  testWidgets('tracks that cannot be read can be asked for again', (
    tester,
  ) async {
    _tall(tester);
    server.overrides['track'] = FakeLidarr.body('{}', status: 500);
    await screens.open(tester, _route(screens, albumRef(1)));

    expect(find.text('First'), findsNWidgets(2));
    server.overrides.clear();
    await tester.tap(find.text('Retry tracks'));
    await tester.pumpAndSettle();

    expect(find.text('1. Song 1'), findsOneWidget);
  });

  testWidgets('albums that cannot be read can be asked for again', (
    tester,
  ) async {
    _tall(tester);
    server.overrides['album'] = FakeLidarr.body('{}', status: 500);
    await screens.open(tester, _route(screens, artistRef(1)));

    server.overrides.clear();
    await tester.tap(find.text('Retry albums'));
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('an artist without albums says so', (tester) async {
    _tall(tester);
    server.albums.removeWhere((album) => album['artistId'] == 1);
    await screens.open(tester, _route(screens, artistRef(1)));

    expect(find.text('No albums'), findsOneWidget);
  });

  testWidgets('an album found deleted leaves the artist screen below', (
    tester,
  ) async {
    _tall(tester);
    await screens.open(tester, _route(screens, artistRef(1)));
    server.albums.removeWhere((album) => album['id'] == 1);

    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();

    expect(
      find.text('This item no longer exists on the server.'),
      findsOneWidget,
    );
    await screens.back(tester);
    expect(find.text('First'), findsNothing);
    expect(find.text('Third'), findsOneWidget);
  });

  testWidgets('an artist found gone is gone on the album screen too', (
    tester,
  ) async {
    _tall(tester);
    await screens.open(tester, _route(screens, albumRef(1)));

    // As another screen's read does.
    await screens.harness.cache.remove(MediaKind.artist, 1);
    await tester.pumpAndSettle();

    expect(
      find.text('This item no longer exists on the server.'),
      findsOneWidget,
    );
  });

  testWidgets('an address that names no item is said to be gone', (
    tester,
  ) async {
    await screens.open(
      tester,
      const ModuleRoute(instanceId: instanceId, path: 'lidarr/albums/x'),
    );

    expect(
      find.text('This item no longer exists on the server.'),
      findsOneWidget,
    );
    expect(server.requests, isEmpty);
  });

  testWidgets('both screens fit a small phone at twice the text size', (
    tester,
  ) async {
    _tall(tester, const Size(320, 568));
    final handle = tester.ensureSemantics();

    for (final route in [
      _route(screens, artistRef(1)),
      _route(screens, albumRef(1)),
    ]) {
      await screens.open(tester, route, textScale: 2);
      // Everything is laid out on the way down: an overflow fails the test.
      final scrollable = find.byType(Scrollable).last;
      for (var page = 0; page < 30; page++) {
        await tester.drag(scrollable, const Offset(0, -400));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
      await screens.back(tester);
    }
    handle.dispose();
  });
}
