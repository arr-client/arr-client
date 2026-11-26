/// Services with a history and a blocklist that the test answers for.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/support.dart';
import '../queue/support.dart';

/// A history and a blocklist that answer by page and record what they were
/// asked.
class FakeActivity implements HistoryProvider {
  /// The events of each page, from 1.
  var pages = <List<HistoryEvent>>[[]];

  /// The blocked releases of each page, from 1.
  var blocked = <List<BlocklistEntry>>[[]];

  /// Fails every read while set.
  ServiceFailure? failure;

  /// Holds back every read while set.
  Completer<void>? readGate;

  /// Holds back every change while set.
  Completer<void>? writeGate;

  /// What every change answers.
  Result<void, ServiceFailure> answer = const Ok(null);

  /// The pages of the history that were asked for.
  final reads = <int>[];

  /// The pages of the blocklist that were asked for.
  final blocklistReads = <int>[];

  /// What was sent, in order.
  final writes = <String>[];

  @override
  ServiceResult<ResultPage<HistoryEvent>> history({
    MediaTarget? target,
    int page = 1,
  }) {
    reads.add(page);
    return _page(pages, page);
  }

  @override
  ServiceResult<ResultPage<BlocklistEntry>> blocklist({int page = 1}) {
    blocklistReads.add(page);
    return _page(blocked, page);
  }

  @override
  ServiceResult<void> markFailed(int eventId) => _write('markFailed $eventId');

  @override
  ServiceResult<void> unblock(List<int> entryIds) =>
      _write('unblock $entryIds');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  ServiceResult<ResultPage<T>> _page<T>(List<List<T>> pages, int page) async {
    // As things were when asked.
    final failure = this.failure;
    await readGate?.future;
    if (failure != null) return Err(failure);
    return Ok(
      ResultPage(
        items: pages[page - 1],
        page: page,
        hasMore: page < pages.length,
      ),
    );
  }

  ServiceResult<void> _write(String what) async {
    writes.add(what);
    await writeGate?.future;
    return answer;
  }
}

/// A service with a history for each of its instances.
class ActivityModule extends FakeModule {
  ActivityModule()
    : super('films', offers: {CapabilityKind.queue, CapabilityKind.history});

  /// By the instance's name.
  final activities = <String, FakeActivity>{};

  FakeActivity of(String name) =>
      activities.putIfAbsent(name, FakeActivity.new);

  @override
  T? capability<T extends Capability>(InstanceContext context) {
    final Capability? found = switch (T) {
      const (HistoryProvider) => of(context.instance.name),
      const (QueueProvider) => FakeQueue(),
      _ => null,
    };
    return found as T?;
  }
}

HistoryEvent grab(
  int id, {
  String? title,
  int day = 1,
  HistoryEventType type = HistoryEventType.grabbed,
  String? downloadId,
}) => HistoryEvent(
  id: id,
  eventType: type,
  date: DateTime.utc(2026, 3, day, 12),
  sourceTitle: title ?? 'Release $id',
  downloadId: downloadId,
);

BlocklistEntry blocked(int id, {String? title, int day = 1, String? reason}) =>
    BlocklistEntry(
      id: id,
      sourceTitle: title ?? 'Release $id',
      date: DateTime.utc(2026, 3, day, 12),
      quality: const Quality(id: 3, name: 'WEBDL-1080p'),
      reason: reason,
    );

/// A running app with an instance for each of [names].
Future<(TestApp, List<String>)> startWith(
  WidgetTester tester,
  ActivityModule module,
  List<String> names,
) async {
  final app = await TestApp.start(tester, modules: [module]);
  final ids = [for (final name in names) await app.add(module, name)];
  await app.pump(tester);
  return (app, ids);
}

Future<void> openHistoryTab(WidgetTester tester) async {
  await go(tester, 'Activity');
  await tester.tap(find.widgetWithText(Tab, 'History'));
  await step(tester);
}

Future<void> openBlocklist(WidgetTester tester) async {
  await go(tester, 'More');
  await tester.tap(find.text('Blocklist'));
  await step(tester);
}

/// Presses the button labelled [text] of the dialog on screen.
Future<void> confirm(WidgetTester tester, String text) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, text),
    ),
  );
  await step(tester);
}

/// Whether each of the buttons labelled [text] can be pressed, from the top.
List<bool> enabled(WidgetTester tester, String text) => [
  for (final button in tester.widgetList<TextButton>(
    find.widgetWithText(TextButton, text),
  ))
    button.onPressed != null,
];
