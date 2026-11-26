import 'dart:async';

import 'package:arr_client/app/navigation/locations.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/support.dart';

/// Releases that a test sets, and a record of what was asked.
class FakeReleases implements ReleaseProvider {
  var found = <Release>[];

  /// Fails every search while set.
  ServiceFailure? failure;

  /// Holds back every search while set.
  Completer<void>? gate;

  /// Fails every grab while set.
  ServiceFailure? grabFailure;

  /// Holds back every grab while set.
  Completer<void>? grabGate;

  final searches = <MediaTarget>[];
  final grabs = <Release>[];

  @override
  ServiceResult<List<Release>> releases(MediaTarget target) async {
    searches.add(target);
    // As things were when asked.
    final failure = this.failure;
    final found = this.found;
    await gate?.future;
    return failure == null ? Ok(found) : Err(failure);
  }

  @override
  ServiceResult<void> grab(Release release) async {
    grabs.add(release);
    final failure = grabFailure;
    await grabGate?.future;
    return failure == null ? const Ok(null) : Err(failure);
  }
}

class ReleaseModule extends FakeModule {
  ReleaseModule() : super('films', offers: {CapabilityKind.release});

  final fake = FakeReleases();

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (ReleaseProvider) => fake,
      _ => null,
    };
    return found as T?;
  }
}

Release release(
  int id, {
  String? title,
  String indexer = 'Alpha',
  int size = 1024,
  double age = 1,
  int score = 0,
  int? seeders,
  DownloadProtocol protocol = DownloadProtocol.torrent,
  String quality = 'HD',
  List<String> rejections = const [],
  bool downloadAllowed = true,
}) => Release(
  guid: 'guid-$id',
  indexerId: 1,
  indexer: indexer,
  title: title ?? 'Release $id',
  protocol: protocol,
  size: size,
  ageHours: age,
  score: score,
  seeders: seeders,
  quality: Quality(id: quality.hashCode, name: quality),
  languages: const [Language(id: 1, name: 'English')],
  rejections: rejections,
  downloadAllowed: downloadAllowed,
  rawJson: const {},
  searchTarget: const {'movieId': 7},
);

/// Lets transitions and answers finish, also while a progress bar moves.
Future<void> step(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  late TestApp app;
  late ReleaseModule module;
  late String instance;

  MediaTarget target() => MediaTarget(
    ItemRef(instanceId: instance, kind: MediaKind.movie, remoteId: 7),
  );

  Future<void> search(WidgetTester tester) async {
    app.services.registry.scope!
        .instance(instance)!
        .context
        .navigator
        .openReleases(target())
        .ignore();
    // Not pumpAndSettle, which would not end while a progress bar moves.
    await step(tester);
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 2400),
    void Function(FakeReleases fake)? arrange,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    module = ReleaseModule();
    arrange?.call(module.fake);
    app = await TestApp.start(tester, modules: [module]);
    instance = await app.add(module, 'Cellar');
    await app.pump(tester);
    await search(tester);
  }

  Finder grabButton(String title) => find.ancestor(
    of: find.bySemanticsLabel('Grab: $title'),
    matching: find.byType(TextButton),
  );

  Future<void> grab(WidgetTester tester, String title) async {
    await tester.tap(grabButton(title));
    await step(tester);
  }

  List<String> shownTitles(WidgetTester tester, List<String> titles) {
    final shown = [
      for (final title in titles)
        if (find.text(title).evaluate().isNotEmpty) title,
    ];
    return shown..sort(
      (a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy),
    );
  }

  test('a location keeps the season, and a bad one names nothing', () {
    const season = MediaTarget(
      ItemRef(instanceId: 'a', kind: MediaKind.series, remoteId: 3),
      seasonNumber: 0,
    );
    final query = Uri.parse(releasesLocation(season)).queryParameters;

    expect(releaseTarget('a', query), season);
    expect(releaseTarget('a', {...query, 'season': 'x'}), isNull);
    expect(releaseTarget('a', const {}), isNull);
  });

  testWidgets('shows progress while searching, and can be left', (
    tester,
  ) async {
    final gate = Completer<void>();
    await open(
      tester,
      arrange: (fake) => fake
        ..gate = gate
        ..found = [release(1)],
    );

    expect(find.textContaining('up to 2 minutes'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(module.fake.searches, [target()]);
    await tester.pageBack();
    await step(tester);
    expect(find.widgetWithText(AppBar, 'Releases'), findsNothing);

    // The answer to the search that was left is dropped.
    gate.complete();
    await step(tester);
    expect(find.text('Release 1'), findsNothing);
    await app.stop(tester);
  });

  testWidgets('lists what is known of a release, as harmless text', (
    tester,
  ) async {
    await open(
      tester,
      arrange: (fake) => fake.found = [
        release(
          1,
          title: 'Film\u202Egpj.exe\nsecond',
          indexer: 'In\u200Fdex',
          size: 2048,
          age: 49,
          score: 25,
          seeders: 12,
          rejections: ['Too\u2066 small', ''],
        ),
        release(2, protocol: DownloadProtocol.usenet, size: 0),
      ],
    );

    expect(find.text('Film\u{fffd}gpj.exe second'), findsOneWidget);
    expect(find.text('Indexer: In\u{fffd}dex'), findsOneWidget);
    expect(find.text('Torrent'), findsOneWidget);
    expect(find.text('Usenet'), findsOneWidget);
    expect(find.text('Size: 2.0 KiB'), findsOneWidget);
    expect(find.textContaining('Size:'), findsOneWidget);
    expect(find.text('Age: 2 d 1 h'), findsOneWidget);
    expect(find.text('Quality: HD'), findsNWidgets(2));
    expect(find.text('Languages: English'), findsNWidgets(2));
    expect(find.text('Seeders: 12'), findsOneWidget);
    expect(find.text('Score: 25'), findsOneWidget);
    expect(find.text('Rejected:'), findsOneWidget);
    expect(find.text('Too\u{fffd} small'), findsOneWidget);
    expect(find.text('No reason given'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('grabs an accepted release at once, with the same object', (
    tester,
  ) async {
    final gate = Completer<void>();
    final wanted = release(1);
    await open(
      tester,
      arrange: (fake) => fake
        ..found = [wanted]
        ..grabGate = gate,
    );

    await grab(tester, 'Release 1');

    expect(find.byType(AlertDialog), findsNothing);
    expect(module.fake.grabs.single, same(wanted));
    expect(find.text('Sending the grab'), findsOneWidget);
    expect(grabButton('Release 1'), findsNothing);
    // Nothing is claimed before the server answers.
    expect(find.textContaining('accepted'), findsNothing);

    gate.complete();
    await step(tester);

    expect(find.text('Grab accepted'), findsOneWidget);
    expect(find.text('Cellar accepted the grab of Release 1.'), findsOneWidget);
    expect(grabButton('Release 1'), findsNothing);
    expect(module.fake.grabs, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('a grab under way is not sent again after leaving', (
    tester,
  ) async {
    final gate = Completer<void>();
    await open(
      tester,
      arrange: (fake) => fake
        ..found = [release(1)]
        ..grabGate = gate,
    );
    await grab(tester, 'Release 1');
    await tester.pageBack();
    await step(tester);

    await search(tester);

    expect(find.text('Sending the grab'), findsOneWidget);
    expect(grabButton('Release 1'), findsNothing);
    await tester.pageBack();
    await step(tester);
    gate.complete();
    await step(tester);
    // Said although the screen was left.
    expect(find.text('Cellar accepted the grab of Release 1.'), findsOneWidget);
    expect(module.fake.grabs, hasLength(1));

    // A new search offers it again.
    await search(tester);
    expect(grabButton('Release 1'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('confirms a rejected release, repeating the reasons', (
    tester,
  ) async {
    final rejected = release(1, rejections: ['Too small', 'Wrong language']);
    await open(tester, arrange: (fake) => fake.found = [rejected]);

    await grab(tester, 'Release 1');

    final dialog = find.byType(AlertDialog);
    Finder inDialog(String text) =>
        find.descendant(of: dialog, matching: find.textContaining(text));
    expect(inDialog('Grab rejected release?'), findsOneWidget);
    expect(inDialog('Release 1'), findsOneWidget);
    expect(inDialog('Too small\nWrong language'), findsOneWidget);
    expect(inDialog('could not match'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await step(tester);
    expect(module.fake.grabs, isEmpty);

    await grab(tester, 'Release 1');
    await tester.tap(find.text('Grab anyway'));
    await step(tester);

    expect(module.fake.grabs.single, same(rejected));
    await app.stop(tester);
  });

  testWidgets('confirms a release the server could not match', (tester) async {
    final unmatched = release(1, downloadAllowed: false);
    await open(tester, arrange: (fake) => fake.found = [unmatched]);

    await grab(tester, 'Release 1');

    expect(find.text('Grab unmatched release?'), findsOneWidget);
    expect(
      find.textContaining('takes it to be what you searched for'),
      findsOneWidget,
    );
    expect(module.fake.grabs, isEmpty);
    await tester.tap(find.text('Grab anyway'));
    await step(tester);

    expect(module.fake.grabs.single, same(unmatched));
    await app.stop(tester);
  });

  testWidgets('an unknown outcome is said, and asked about before another '
      'grab', (tester) async {
    await open(
      tester,
      arrange: (fake) => fake
        ..found = [release(1)]
        ..grabFailure = const OutcomeUnknown(),
    );

    await grab(tester, 'Release 1');

    expect(
      find.textContaining('may or may not have reached Cellar'),
      findsOneWidget,
    );
    expect(find.textContaining('An earlier grab'), findsOneWidget);
    expect(module.fake.grabs, hasLength(1));
    expect(module.fake.searches, hasLength(1));

    // Still known after another search.
    await tester.tap(find.byTooltip('Search again'));
    await step(tester);
    await grab(tester, 'Release 1');
    expect(find.text('Grab this release again?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await step(tester);
    expect(module.fake.grabs, hasLength(1));

    // A definite failure leaves the earlier outcome unknown.
    module.fake.grabFailure = const Unreachable();
    await grab(tester, 'Release 1');
    await tester.tap(find.text('Grab anyway'));
    await step(tester);
    expect(module.fake.grabs, hasLength(2));
    expect(find.textContaining('An earlier grab'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('says that the server forgot a release', (tester) async {
    await open(
      tester,
      arrange: (fake) => fake
        ..found = [release(1)]
        ..grabFailure = const NotFound(),
    );

    await grab(tester, 'Release 1');

    expect(
      find.text(
        'Release 1: The server could not find this release. Search again.',
      ),
      findsOneWidget,
    );
    expect(grabButton('Release 1'), findsOneWidget);
    expect(module.fake.grabs, hasLength(1));
    await app.stop(tester);
  });

  testWidgets('sorts, keeping the server order for equal ones', (tester) async {
    const titles = ['Bravo', 'Charlie', 'Alpha'];
    await open(
      tester,
      arrange: (fake) => fake.found = [
        release(1, title: 'Bravo', score: 5, age: 3),
        release(2, title: 'Charlie', score: 10, age: 1, seeders: 2),
        release(3, title: 'Alpha', score: 5, age: 2, seeders: 9),
      ],
    );
    expect(shownTitles(tester, titles), titles);

    Future<void> choose(String item) async {
      await tester.tap(find.byTooltip('Sort'));
      await step(tester);
      await tester.tap(
        find.ancestor(
          of: find.text(item),
          matching: find.byWidgetPredicate(
            (widget) => widget is CheckedPopupMenuItem,
          ),
        ),
      );
      await step(tester);
    }

    await choose('Score');
    expect(shownTitles(tester, titles), ['Charlie', 'Bravo', 'Alpha']);
    await choose('Ascending');
    expect(shownTitles(tester, titles), ['Bravo', 'Alpha', 'Charlie']);
    // Without a value last, whichever the direction.
    await choose('Seeders');
    expect(shownTitles(tester, titles), ['Alpha', 'Charlie', 'Bravo']);
    await choose('Ascending');
    expect(shownTitles(tester, titles), ['Charlie', 'Alpha', 'Bravo']);
    await choose('Age');
    expect(shownTitles(tester, titles), ['Charlie', 'Alpha', 'Bravo']);
    await choose('Title');
    expect(shownTitles(tester, titles), ['Alpha', 'Bravo', 'Charlie']);
    await choose('Server ranking');
    expect(shownTitles(tester, titles), titles);
    await app.stop(tester);
  });

  testWidgets('filters by text and by what the releases have', (tester) async {
    await open(
      tester,
      arrange: (fake) => fake.found = [
        release(1, title: 'Bravo'),
        release(2, title: 'Charlie', indexer: 'Beta'),
        release(3, title: 'Delta', rejections: ['Too small']),
      ],
    );
    expect(find.text('3 of 3 releases'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'beta');
    await step(tester);
    expect(find.text('1 of 3 releases'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear filter text'));
    await step(tester);

    await tester.tap(find.byTooltip('Filters'));
    await step(tester);
    await tester.tap(find.text('Hide releases that need confirmation'));
    await step(tester);
    await tester.tap(find.text('Show 2 releases'));
    await step(tester);
    expect(find.text('2 of 3 releases'), findsOneWidget);
    expect(find.text('Delta'), findsNothing);

    await tester.tap(find.byTooltip('Filters, 1 on'));
    await step(tester);
    await tester.tap(find.widgetWithText(FilterChip, 'Beta'));
    await step(tester);
    await tester.tap(find.text('Show 1 release'));
    await step(tester);
    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('Bravo'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing');
    await step(tester);
    expect(find.text('No releases match the filters.'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await step(tester);
    expect(find.text('3 of 3 releases'), findsOneWidget);
    await app.stop(tester);
  });

  testWidgets('shows empty and failed searches, and searches again', (
    tester,
  ) async {
    await open(tester, arrange: (fake) => fake.failure = const Unreachable());
    expect(find.textContaining('did not answer'), findsOneWidget);
    expect(module.fake.searches, hasLength(1));

    module.fake.failure = null;
    await tester.tap(find.text('Retry'));
    await step(tester);

    expect(find.text('No releases were found.'), findsOneWidget);
    expect(module.fake.searches, hasLength(2));
    await app.stop(tester);
  });

  testWidgets('grabs nothing from results that are being replaced or are old', (
    tester,
  ) async {
    await open(tester, arrange: (fake) => fake.found = [release(1)]);
    final gate = Completer<void>();
    module.fake
      ..gate = gate
      ..failure = const Unreachable();

    await tester.tap(find.byTooltip('Search again'));
    await step(tester);

    expect(find.text('Release 1'), findsOneWidget);
    expect(
      tester.widget<TextButton>(grabButton('Release 1')).onPressed,
      isNull,
    );
    // One search at a time.
    final again = find.widgetWithIcon(IconButton, Icons.refresh);
    expect(tester.widget<IconButton>(again).onPressed, isNull);

    gate.complete();
    await step(tester);

    expect(find.textContaining('Saved data'), findsOneWidget);
    expect(
      tester.widget<TextButton>(grabButton('Release 1')).onPressed,
      isNull,
    );
    expect(module.fake.grabs, isEmpty);
    await app.stop(tester);
  });

  testWidgets('fits a small phone at 200% text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(
      tester,
      size: const Size(320, 640),
      arrange: (fake) => fake.found = [
        release(
          1,
          title: 'A.Very.Long.Release.Name.2026.2160p.WEB-DL.DDP5.1.H.265-GRP',
          rejections: ['A reason that is long enough to need several lines'],
          downloadAllowed: false,
        ),
      ],
    );
    expect(tester.takeException(), isNull);

    final button = grabButton(
      'A.Very.Long.Release.Name.2026.2160p.WEB-DL.DDP5.1.H.265-GRP',
    );
    await tester.ensureVisible(button);
    await step(tester);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    await step(tester);
    expect(find.text('Grab anyway'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await step(tester);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 3000));
    await step(tester);
    await tester.tap(find.byTooltip('Filters'));
    await step(tester);
    expect(tester.takeException(), isNull);
    await app.stop(tester);
  });
}
