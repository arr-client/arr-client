/// Active downloads, health and disk space on Home (spec story 6).
library;

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../activity/queue/support.dart' show entry, go, step;
import 'support.dart';

final noon = DateTime(2026, 11, 26, 12);

class _Browser extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final opened = <(String, PreferredLaunchMode)>[];
  var works = true;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add((url, options.mode));
    return works;
  }
}

HealthIssue _issue(HealthLevel level, String message, {String? help}) =>
    HealthIssue(
      source: 'Check',
      level: level,
      message: message,
      helpUrl: help == null ? null : Uri.parse(help),
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await step(tester);
}

void main() {
  testWidgets('lists health problems, worst first, with their help', (
    tester,
  ) async {
    final browser = _Browser();
    final before = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = browser;
    addTearDown(() => UrlLauncherPlatform.instance = before);
    final home = await HomeHarness.start(tester, now: noon);
    home.server('Films').issues = [
      _issue(HealthLevel.notice, 'An update is available'),
      _issue(HealthLevel.warning, 'No indexers', help: 'intent://nowhere'),
    ];
    home.server('Shows').issues = [
      _issue(
        HealthLevel.error,
        'No download client',
        help: 'https://wiki.example/clients',
      ),
    ];

    await home.pump(tester);

    expect(rowsOf(tester, 'Health'), [
      'No download client',
      'No indexers',
      'An update is available',
    ]);
    expect(find.text('Error · Shows'), findsOneWidget);
    expect(find.text('Warning · Films'), findsOneWidget);
    expect(find.text('Notice · Films'), findsOneWidget);
    // Only web pages are opened.
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);

    final help = find.byTooltip('Open help for: No download client');
    await _tap(tester, help);
    expect(browser.opened, [
      ('https://wiki.example/clients', PreferredLaunchMode.externalApplication),
    ]);
    expect(find.byType(SnackBar), findsNothing);

    browser.works = false;
    await _tap(tester, help);
    expect(
      find.text('The link could not be opened: https://wiki.example/clients'),
      findsOneWidget,
    );
    await home.stop(tester);
  });

  testWidgets('says that nothing is wrong only when all have said so', (
    tester,
  ) async {
    final home = await HomeHarness.start(tester, now: noon);
    home.server('Shows').failure = const Unreachable();

    await home.pump(tester);

    expect(find.text('No problems reported.'), findsNothing);
    expect(
      find.text('No problems from the services that answered.'),
      findsOneWidget,
    );

    home.server('Shows').failure = null;
    await _tap(tester, find.byTooltip('Refresh'));
    expect(find.text('No problems reported.'), findsOneWidget);
    await home.stop(tester);
  });

  testWidgets('shows the free space of the disks of each service', (
    tester,
  ) async {
    final home = await HomeHarness.start(
      tester,
      now: noon,
      names: ['Films', 'Shows', 'Indexers'],
    );
    const gib = 1024 * 1024 * 1024;
    home.server('Films').disks = [
      const DiskSpace(path: '/movies', free: 100 * gib, total: 400 * gib),
    ];
    home.server('Shows').disks = [
      const DiskSpace(path: '/tv', free: 5 * gib, total: 0),
    ];
    home.server('Indexers').reportsDisks = false;

    await home.pump(tester);

    expect(rowsOf(tester, 'Disk space'), ['/movies', '/tv']);
    expect(find.text('100.0 GiB free of 400.0 GiB'), findsOneWidget);
    expect(find.text('5.0 GiB free'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('/movies')),
      isSemantics(
        label: '/movies\n100.0 GiB free of 400.0 GiB\nDisk space used',
        value: '75%',
      ),
    );
    // A service without disk space has nothing to say about it.
    expect(find.text('Indexers · '), findsNothing);
    expect(find.text('No disks reported.'), findsNothing);
    await home.stop(tester);
  });

  testWidgets('lists downloads, problems first, and links to the rest', (
    tester,
  ) async {
    final home = await HomeHarness.start(tester, now: noon);
    home.server('Films').queue.items = [
      for (var i = 1; i <= 6; i++) entry(i, 'Download $i'),
    ];
    home.server('Shows').queue.items = [
      entry(1, 'Broken', severity: QueueSeverity.error),
    ];

    await home.pump(tester);

    expect(rowsOf(tester, 'Active downloads'), [
      'Broken',
      'Download 1',
      'Download 2',
      'Download 3',
      'Download 4',
      'Download 5',
    ]);
    expect(find.text('1 more not shown'), findsOneWidget);

    await _tap(tester, find.text('Download 1'));
    expect(find.text('Queue entry'), findsOneWidget);
    await _tap(tester, find.byType(BackButton));

    await _tap(tester, find.text('See all 7 queue entries'));
    expect(find.widgetWithText(AppBar, 'Activity'), findsOneWidget);
    await home.stop(tester);
  });

  testWidgets('reads the queues only while Home is on screen', (tester) async {
    final home = await HomeHarness.start(
      tester,
      now: noon,
      size: const Size(400, 800),
    );
    final queue = home.server('Films').queue;
    await home.pump(tester);
    var reads = queue.reads;
    await tester.pump(const Duration(seconds: 4));
    expect(queue.reads, greaterThan(reads));

    await go(tester, 'More');
    reads = queue.reads;
    await tester.pump(const Duration(seconds: 20));
    expect(queue.reads, reads);

    await go(tester, 'Home');
    expect(queue.reads, reads + 1);
    await home.stop(tester);
  });

  testWidgets('a queue that fails keeps the others, and is retried', (
    tester,
  ) async {
    final home = await HomeHarness.start(tester, now: noon);
    home.server('Films').queue.items = [entry(1, 'A film')];
    final broken = home.server('Shows').queue..failure = const Unreachable();

    await home.pump(tester);

    expect(rowsOf(tester, 'Active downloads'), ['A film']);
    broken
      ..failure = null
      ..items = [entry(2, 'An episode')];
    await _tap(tester, find.widgetWithText(TextButton, 'Retry'));
    expect(rowsOf(tester, 'Active downloads'), ['A film', 'An episode']);
    await home.stop(tester);
  });

  testWidgets('has only the sections that some service provides', (
    tester,
  ) async {
    final home = await HomeHarness.start(
      tester,
      now: noon,
      offers: {CapabilityKind.health},
    );

    await home.pump(tester);

    for (final shown in ['Health', 'Disk space', 'Services']) {
      expect(find.text(shown), findsOneWidget);
    }
    for (final absent in [
      'Coming up',
      'Downloaded today',
      'Recently added',
      'Active downloads',
    ]) {
      expect(find.text(absent), findsNothing);
    }
    await home.stop(tester);
  });

  testWidgets('has headings, and fits large text on a small phone', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final home = await HomeHarness.start(
      tester,
      now: noon,
      size: const Size(320, 568),
    );
    const long = 'A rather long title that goes on and on past one line';
    home
      ..release('Films', long, DateTime(2026, 11, 27))
      ..imported('Films', long, DateTime(2026, 11, 26, 9));
    home.server('Films')
      ..issues = [
        _issue(HealthLevel.error, long, help: 'https://wiki.example/a'),
      ]
      ..disks = [
        const DiskSpace(path: '/a/very/long/path/to/media', free: 1, total: 2),
      ]
      ..queue.items = [entry(1, long)];
    home.server('Shows').failure = const Unreachable();

    await home.pump(tester, textScale: 2);

    expect(
      tester.getSemantics(find.text('Coming up')),
      isSemantics(label: 'Coming up', isHeader: true),
    );
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    // To the end, over everything.
    for (var i = 0; i < 40 && find.text('Go to').evaluate().isEmpty; i++) {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.drag(scrollable, const Offset(0, -300));
      await step(tester);
    }
    expect(find.text('Go to'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
    await home.stop(tester);
  });
}
