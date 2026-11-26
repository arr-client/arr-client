/// Editing, changing several, searching and deleting (spec story 5; FR-015,
/// FR-017).
library;

import 'dart:async';

import 'package:arr_client/features/library/manage/bulk_edit_sheet.dart';
import 'package:arr_client/features/library/manage/search_tasks.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/fake_library.dart';
import '../../app/navigation_test.dart' show open, usePhone;
import '../../app/support.dart';

class ManagedLibrary extends FakeLibrary {
  ManagedLibrary({super.items, super.itemKind, super.serverOptions});

  /// Why [item] fails.
  ServiceFailure? itemFailure;

  /// Why every change fails.
  ServiceFailure? writeFailure;

  /// While set, a change waits for it.
  Completer<void>? writeGate;

  final edits = <(ItemRef, ItemEdit)>[];
  final bulkEdits = <(List<ItemRef>, BulkEdit)>[];
  final deletes = <(ItemRef, bool, bool)>[];
  final applied = <(ItemRef, String)>[];

  @override
  List<MonitorOption> monitorOptions = const [];

  @override
  ServiceResult<LibraryItem> item(ItemRef ref) async {
    if (itemFailure case final failure?) return Err(failure);
    final found = items.where((item) => item.ref == ref).firstOrNull;
    return found == null ? const Err(NotFound()) : Ok(found);
  }

  Future<Result<void, ServiceFailure>> _write() async {
    await writeGate?.future;
    final failure = writeFailure;
    return failure == null ? const Ok(null) : Err(failure);
  }

  @override
  ServiceResult<void> edit(ItemRef ref, ItemEdit changes) {
    edits.add((ref, changes));
    return _write();
  }

  @override
  ServiceResult<void> bulkEdit(List<ItemRef> refs, BulkEdit changes) {
    bulkEdits.add((refs, changes));
    return _write();
  }

  @override
  ServiceResult<void> delete(
    ItemRef ref, {
    required bool deleteFiles,
    required bool addImportExclusion,
  }) {
    deletes.add((ref, deleteFiles, addImportExclusion));
    return _write();
  }

  @override
  ServiceResult<void> applyMonitorOption(ItemRef ref, String optionId) {
    applied.add((ref, optionId));
    return _write();
  }
}

class FakeCommands implements CommandProvider {
  final searches = <List<MediaTarget>>[];
  var statusReads = 0;

  /// By the searched item's id, why its search is not accepted.
  final refused = <int, ServiceFailure>{};

  /// What a read of a command answers.
  Result<Command, ServiceFailure> Function(int id) status = (id) =>
      Ok(Command(id: id, name: 'search', status: CommandStatus.completed));

  @override
  bool supports(CommandAction action, MediaTarget target) => true;

  @override
  ServiceResult<Command> search(List<MediaTarget> targets) async {
    searches.add(targets);
    final id = targets.single.item.remoteId;
    if (refused[id] case final failure?) return Err(failure);
    return Ok(Command(id: id, name: 'search', status: CommandStatus.queued));
  }

  @override
  ServiceResult<Command> commandStatus(int commandId) async {
    statusReads++;
    return status(commandId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final libraries = <String, ManagedLibrary>{};
final commandsOf = <String, FakeCommands>{};

class ManagedModule extends FakeModule {
  ManagedModule()
    : super(
        'movies',
        offers: {CapabilityKind.library, CapabilityKind.command},
        library: (context) => libraries[context.instance.name]!,
      );

  @override
  T? capability<T extends Capability>(InstanceContext context) =>
      T == CommandProvider
      ? commandsOf[context.instance.name] as T?
      : super.capability<T>(context);
}

final module = ManagedModule();

const options = [
  ServerOption(kind: ServerOptionKind.qualityProfile, id: 1, label: 'SD'),
  ServerOption(kind: ServerOptionKind.qualityProfile, id: 2, label: 'HD'),
  ServerOption(kind: ServerOptionKind.tag, id: 5, label: 'kids'),
  ServerOption(kind: ServerOptionKind.tag, id: 6, label: 'classic'),
];

Movie movie(
  String instance,
  String title,
  int id, {
  bool monitored = true,
  int? year,
}) => Movie(
  ref: ItemRef(instanceId: instance, kind: MediaKind.movie, remoteId: id),
  title: title,
  sortTitle: title.toLowerCase(),
  monitored: monitored,
  state: ItemState.downloaded,
  year: year,
  qualityProfileId: 1,
  tagIds: const {5},
  minimumAvailability: MinimumAvailability.released,
  sizeOnDisk: 1 << 30,
);

late TestApp app;

Future<void> start(WidgetTester tester, [Size? size]) async {
  usePhone(tester, size ?? const Size(400, 800));
  libraries.clear();
  commandsOf.clear();
  app = await TestApp.start(tester, modules: [module]);
}

/// An instance called [name] with [titles], numbered from [first].
Future<String> addServer(
  String name,
  List<String> titles, {
  int first = 1,
}) async {
  final library = libraries[name] = ManagedLibrary(serverOptions: options);
  commandsOf[name] = FakeCommands();
  final id = await app.add(module, name);
  library.items = [
    for (final (i, title) in titles.indexed)
      movie(id, title, first + i, year: 2000 + i),
  ];
  return id;
}

ItemRef refOf(String instanceId, [int id = 1]) =>
    ItemRef(instanceId: instanceId, kind: MediaKind.movie, remoteId: id);

AppNavigator navigatorOf(String instanceId) =>
    app.services.registry.scope!.instance(instanceId)!.context.navigator;

/// Pumps without waiting for animations, which never end while something is
/// under way.
Future<void> pumpSome(WidgetTester tester) async {
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<ButtonStyleButton>(),
);

bool enabled(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(button(label)).enabled;

Future<void> choose(WidgetTester tester, String field, String value) async {
  await tap(
    tester,
    find.descendant(
      of: find.widgetWithText(InputDecorator, field),
      matching: find.byType(InkWell),
    ),
  );
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

/// Opens the edit sheet of the first movie of Films, and says when it closed.
Future<(String, bool Function())> openEdit(WidgetTester tester) async {
  final id = await addServer('Films', ['Alpha']);
  await app.pump(tester);
  var closed = false;
  navigatorOf(id).openEdit(refOf(id)).then((_) => closed = true).ignore();
  await tester.pumpAndSettle();
  return (id, () => closed);
}

Future<(String, bool Function())> openDelete(WidgetTester tester) async {
  final id = await addServer('Films', ['Alpha']);
  await app.pump(tester);
  var closed = false;
  navigatorOf(id).openDelete(refOf(id)).then((_) => closed = true).ignore();
  await tester.pumpAndSettle();
  return (id, () => closed);
}

bool ticked(WidgetTester tester, String label) => tester
    .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, label))
    .value!;

Future<void> openSelection(WidgetTester tester) async {
  await app.pump(tester);
  await open(tester, 'Library');
}

void main() {
  group('editing', () {
    testWidgets('sends only what was changed, once, and closes', (
      tester,
    ) async {
      await start(tester);
      final (id, closed) = await openEdit(tester);
      final library = libraries['Films']!;

      expect(find.text('Edit Alpha (2000)'), findsOneWidget);
      expect(find.text('On Films'), findsOneWidget);
      expect(enabled(tester, 'Save changes'), isFalse);

      await choose(tester, 'Quality profile', 'HD');
      await tap(tester, find.widgetWithText(FilterChip, 'classic'));
      await tap(tester, button('Save changes'));

      final (ref, changes) = library.edits.single;
      expect(ref, refOf(id));
      expect(changes.qualityProfileId, 2);
      expect(changes.tagIds, {5, 6});
      expect(changes.monitored, isNull);
      expect(changes.minimumAvailability, isNull);
      expect(changes.seriesType, isNull);
      expect(changes.seasonFolder, isNull);
      expect(closed(), isTrue);
      expect(
        find.text('Films accepted the changes to Alpha (2000).'),
        findsOneWidget,
      );
      await app.stop(tester);
    });

    testWidgets('has nothing to send once a change is undone', (tester) async {
      await start(tester);
      await openEdit(tester);

      await tap(tester, find.widgetWithText(SwitchListTile, 'Monitored'));
      expect(enabled(tester, 'Save changes'), isTrue);
      await tap(tester, find.widgetWithText(SwitchListTile, 'Monitored'));
      expect(enabled(tester, 'Save changes'), isFalse);

      await tap(tester, find.byTooltip('Close'));
      expect(libraries['Films']!.edits, isEmpty);
      await app.stop(tester);
    });

    testWidgets('stays open and says why a change was refused', (tester) async {
      await start(tester);
      final (_, closed) = await openEdit(tester);
      final library = libraries['Films']!
        ..writeFailure = const Validation(['Profile is gone']);

      await choose(tester, 'Minimum availability', 'In cinemas');
      await tap(tester, button('Save changes'));

      expect(find.textContaining('Profile is gone'), findsOneWidget);
      expect(
        library.edits.single.$2.minimumAvailability,
        MinimumAvailability.inCinemas,
      );
      expect(closed(), isFalse);
      await app.stop(tester);
    });

    testWidgets('reports an unknown outcome and shows what the server has', (
      tester,
    ) async {
      await start(tester);
      await openEdit(tester);
      final library = libraries['Films']!
        ..writeFailure = const OutcomeUnknown();

      await tap(tester, find.widgetWithText(SwitchListTile, 'Monitored'));
      // The change did arrive.
      library.writeGate = Completer();
      await tester.tap(button('Save changes'));
      await tester.pump();
      final old = library.items.single;
      library.items = [
        movie(old.ref.instanceId, 'Alpha', 1, monitored: false, year: 2000),
      ];
      library.writeGate!.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('may or may not'), findsOneWidget);
      expect(library.edits, hasLength(1));
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(enabled(tester, 'Save changes'), isFalse);
      await app.stop(tester);
    });

    testWidgets('cannot be closed while a change is being sent', (
      tester,
    ) async {
      await start(tester);
      final (_, closed) = await openEdit(tester);
      final library = libraries['Films']!..writeGate = Completer();

      await tap(tester, find.widgetWithText(SwitchListTile, 'Monitored'));
      await tester.tap(button('Save changes'));
      await tester.pump();

      expect(enabled(tester, 'Save changes'), isFalse);
      await tester.binding.handlePopRoute();
      await tester.tapAt(const Offset(5, 5));
      await pumpSome(tester);
      expect(closed(), isFalse);

      library.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(closed(), isTrue);
      expect(library.edits, hasLength(1));
      await app.stop(tester);
    });

    testWidgets('offers nothing to change until the item is read', (
      tester,
    ) async {
      await start(tester);
      final id = await addServer('Films', ['Alpha']);
      libraries['Films']!.itemFailure = const Unreachable();
      await app.pump(tester);
      navigatorOf(id).openEdit(refOf(id)).ignore();
      await tester.pumpAndSettle();

      expect(find.textContaining('did not answer'), findsOneWidget);
      expect(find.text('Save changes'), findsNothing);

      libraries['Films']!.itemFailure = null;
      await tap(tester, button('Retry'));
      expect(find.text('Save changes'), findsOneWidget);
      await app.stop(tester);
    });

    testWidgets('says that the item is gone', (tester) async {
      await start(tester);
      final id = await addServer('Films', ['Alpha']);
      await app.pump(tester);
      navigatorOf(id).openEdit(refOf(id, 99)).ignore();
      await tester.pumpAndSettle();

      expect(
        find.text('This item no longer exists on the server.'),
        findsOneWidget,
      );
      expect(find.text('Save changes'), findsNothing);
      await app.stop(tester);
    });

    testWidgets('applies a monitoring option on its own', (tester) async {
      await start(tester);
      final id = await addServer('Films', ['Alpha']);
      final library = libraries['Films']!
        ..monitorOptions = [MonitorOption(id: 'none', label: (_) => 'None')];
      await app.pump(tester);
      navigatorOf(id).openEdit(refOf(id)).ignore();
      await tester.pumpAndSettle();

      expect(enabled(tester, 'Apply monitoring option'), isFalse);
      await choose(tester, 'Monitoring option', 'None');
      await tap(tester, button('Apply monitoring option'));

      expect(library.applied, [(refOf(id), 'none')]);
      expect(library.edits, isEmpty);
      expect(
        find.text('Films accepted the monitoring option.'),
        findsOneWidget,
      );
      await app.stop(tester);
    });

    testWidgets('does not offer what is not an item of the library', (
      tester,
    ) async {
      await start(tester);
      final id = await addServer('Films', ['Alpha']);
      await app.pump(tester);
      final episode = ItemRef(
        instanceId: id,
        kind: MediaKind.episode,
        remoteId: 1,
      );

      for (final flow in [
        navigatorOf(id).openEdit,
        navigatorOf(id).openDelete,
      ]) {
        var closed = false;
        flow(episode).then((_) => closed = true).ignore();
        await tester.pumpAndSettle();
        expect(
          find.text('No service in this profile offers this.'),
          findsOneWidget,
        );
        await tap(tester, find.text('Close'));
        expect(closed, isTrue);
      }
      await app.stop(tester);
    });
  });

  group('deleting', () {
    testWidgets('names the item, with both choices off', (tester) async {
      await start(tester);
      final (_, closed) = await openDelete(tester);

      expect(find.text('Delete movie?'), findsOneWidget);
      expect(find.text('Alpha (2000)'), findsOneWidget);
      expect(find.text('On Films'), findsOneWidget);
      expect(find.text('1.0 GiB on disk'), findsOneWidget);
      expect(ticked(tester, 'Delete files'), isFalse);
      expect(ticked(tester, 'Add import list exclusion'), isFalse);
      expect(find.text("Files stay on the server's disk."), findsOneWidget);

      await tap(tester, button('Cancel'));
      expect(closed(), isTrue);
      expect(libraries['Films']!.deletes, isEmpty);
      await app.stop(tester);
    });

    testWidgets('keeps files and exclusion off unless chosen', (tester) async {
      await start(tester);
      final (id, closed) = await openDelete(tester);

      await tap(tester, button('Delete movie'));

      expect(libraries['Films']!.deletes, [(refOf(id), false, false)]);
      expect(closed(), isTrue);
      expect(
        find.text('Films accepted the deletion of Alpha (2000).'),
        findsOneWidget,
      );
      await app.stop(tester);
    });

    testWidgets('sends the choices made', (tester) async {
      await start(tester);
      final (id, _) = await openDelete(tester);

      await tap(tester, find.text('Delete files'));
      expect(find.textContaining('permanently deleted'), findsOneWidget);
      await tap(tester, find.text('Add import list exclusion'));
      await tap(tester, button('Delete movie'));

      expect(libraries['Films']!.deletes, [(refOf(id), true, true)]);
      await app.stop(tester);
    });

    testWidgets('is sent once and stays until answered', (tester) async {
      await start(tester);
      final (_, closed) = await openDelete(tester);
      final library = libraries['Films']!..writeGate = Completer();

      await tester.tap(button('Delete movie'));
      await tester.pump();
      await tester.tap(button('Delete movie'), warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await tester.tapAt(const Offset(5, 5));
      await pumpSome(tester);

      expect(closed(), isFalse);
      expect(enabled(tester, 'Cancel'), isFalse);
      library.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(library.deletes, hasLength(1));
      expect(closed(), isTrue);
      await app.stop(tester);
    });

    for (final (failure, said) in const <(ServiceFailure, String)>[
      (OutcomeUnknown(), 'may or may not'),
      (Forbidden(), 'does not allow'),
      (NotFound(), 'no longer exists'),
    ]) {
      testWidgets(
        'reports ${failure.runtimeType} and does not offer it again',
        (tester) async {
          await start(tester);
          final (_, closed) = await openDelete(tester);
          libraries['Films']!.writeFailure = failure;

          await tap(tester, button('Delete movie'));

          expect(find.textContaining(said), findsOneWidget);
          expect(find.textContaining('accepted'), findsNothing);
          expect(find.text('Delete movie'), findsNothing);
          expect(libraries['Films']!.deletes, hasLength(1));
          await tap(tester, button('Close'));
          expect(closed(), isTrue);
          await app.stop(tester);
        },
      );
    }

    testWidgets('is not offered for an item that could not be read', (
      tester,
    ) async {
      await start(tester);
      final id = await addServer('Films', ['Alpha']);
      libraries['Films']!.itemFailure = const Unreachable();
      await app.pump(tester);
      navigatorOf(id).openDelete(refOf(id)).ignore();
      await tester.pumpAndSettle();

      expect(find.textContaining('did not answer'), findsOneWidget);
      expect(find.text('Delete movie'), findsNothing);

      libraries['Films']!.itemFailure = null;
      await tap(tester, button('Retry'));
      expect(find.text('Delete movie'), findsOneWidget);
      await app.stop(tester);
    });
  });

  group('several at once', () {
    testWidgets('changes those selected after naming them', (tester) async {
      await start(tester);
      final id = await addServer('Films', ['Alpha', 'Beta', 'Gamma']);
      await openSelection(tester);
      final library = libraries['Films']!;

      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Gamma'));
      expect(find.text('2 selected'), findsOneWidget);

      await tap(tester, button('Edit'));
      expect(find.text('Edit 2 titles on Films'), findsOneWidget);
      expect(enabled(tester, 'Review changes'), isFalse);
      await choose(tester, 'Monitoring', 'Do not monitor');
      await choose(tester, 'Tags', 'Remove tags');
      await tap(tester, find.widgetWithText(FilterChip, 'kids'));
      await tap(tester, button('Review changes'));

      expect(find.text('Change 2 titles?'), findsOneWidget);
      expect(find.text('2 titles on Films'), findsOneWidget);
      expect(find.text('Alpha (2000)\nGamma (2002)'), findsOneWidget);
      expect(
        find.text('Monitoring is turned off.\nTags removed: kids'),
        findsOneWidget,
      );
      expect(library.bulkEdits, isEmpty);
      final listed = library.listed;
      await tap(tester, button('Change 2 titles'));

      final (refs, changes) = library.bulkEdits.single;
      expect(refs, [refOf(id, 1), refOf(id, 3)]);
      expect(changes.monitored, isFalse);
      expect(changes.qualityProfileId, isNull);
      expect(changes.tagIds, {5});
      expect(changes.tagChange, TagChange.remove);
      expect(
        find.text('Films accepted the change to 2 titles.'),
        findsOneWidget,
      );
      expect(find.textContaining('selected'), findsNothing);
      expect(library.listed, listed + 1);
      await app.stop(tester);
    });

    testWidgets('sends nothing when the confirmation is refused', (
      tester,
    ) async {
      await start(tester);
      await addServer('Films', ['Alpha']);
      await openSelection(tester);

      await tap(tester, find.byTooltip('Select titles'));
      await tap(tester, find.text('Alpha'));
      await tap(tester, button('Edit'));
      await choose(tester, 'Quality profile', 'HD');
      await tap(tester, button('Review changes'));
      await tap(tester, button('Cancel').last);

      expect(libraries['Films']!.bulkEdits, isEmpty);
      await app.stop(tester);
    });

    testWidgets('lists the titles that were not changed', (tester) async {
      await start(tester);
      await addServer('Films', ['Alpha', 'Beta']);
      libraries['Films']!.writeFailure = const Forbidden();
      await openSelection(tester);

      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Beta'));
      await tap(tester, button('Edit'));
      await choose(tester, 'Monitoring', 'Monitor');
      await tap(tester, button('Review changes'));
      await tap(tester, button('Change 2 titles'));

      expect(find.text('2 titles were not changed'), findsOneWidget);
      expect(find.text('Alpha (2000)\nBeta (2001)'), findsOneWidget);
      expect(find.textContaining('does not allow'), findsOneWidget);
      expect(libraries['Films']!.bulkEdits, hasLength(1));
      await tap(tester, button('Close'));
      expect(find.text('2 selected'), findsOneWidget);
      await app.stop(tester);
    });

    testWidgets('takes titles of one service only', (tester) async {
      await start(tester);
      await addServer('Attic', ['Alpha']);
      await addServer('Lounge', ['Beta'], first: 2);
      await openSelection(tester);
      final semantics = tester.ensureSemantics();

      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beta'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('1 selected on Attic'), findsOneWidget);
      expect(
        find.text('Only titles of one service can be changed together.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Beta'))),
        isSemantics(hasCheckedState: true, isEnabled: false),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Alpha'))),
        isSemantics(isChecked: true),
      );
      semantics.dispose();
      await app.stop(tester);
    });

    testWidgets('is left by back, and offers no change of saved data', (
      tester,
    ) async {
      await start(tester);
      await addServer('Films', ['Alpha']);
      await openSelection(tester);
      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();

      libraries['Films']!.failure = const Unreachable();
      await tap(tester, find.byTooltip('Refresh'));

      expect(
        find.text(
          'Changes are unavailable while saved data of Films is shown.',
        ),
        findsOneWidget,
      );
      expect(enabled(tester, 'Edit'), isFalse);
      expect(enabled(tester, 'Search'), isFalse);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
      expect(find.byTooltip('Select titles'), findsOneWidget);
      await app.stop(tester);
    });
  });

  group('searching', () {
    Future<FakeCommands> searchBoth(WidgetTester tester) async {
      await start(tester);
      await addServer('Films', ['Alpha', 'Beta']);
      await openSelection(tester);
      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Beta'));
      await tap(tester, button('Search'));
      expect(find.text('Search 2 titles?'), findsOneWidget);
      expect(find.text('Alpha (2000)\nBeta (2001)'), findsOneWidget);
      expect(commandsOf['Films']!.searches, isEmpty);
      return commandsOf['Films']!;
    }

    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(button('Search 2 titles'));
      await pumpSome(tester);
    }

    Future<void> poll(WidgetTester tester) async {
      await tester.pump(commandPollInterval);
      await pumpSome(tester);
    }

    testWidgets('sends each once and follows it to the end', (tester) async {
      final commands = await searchBoth(tester);
      commands.status = (id) =>
          Ok(Command(id: id, name: 'search', status: CommandStatus.started));
      await confirm(tester);

      expect(commands.searches, hasLength(2));
      expect(find.text('Search for 2 titles on Films'), findsOneWidget);
      expect(
        find.text('Waiting for the server. 0 of 2 finished.'),
        findsOneWidget,
      );

      await poll(tester);
      commands.status = (id) => Ok(
        Command(
          id: id,
          name: 'search',
          status: id == 1 ? CommandStatus.completed : CommandStatus.failed,
          message: id == 1 ? null : 'No indexer',
        ),
      );
      await poll(tester);
      await tester.pumpAndSettle();

      expect(find.text('Finished. 1 of 2 searches succeeded.'), findsOneWidget);
      expect(find.text('Beta (2001): No indexer'), findsOneWidget);
      expect(commands.searches, hasLength(2));
      final reads = commands.statusReads;
      await poll(tester);
      expect(commands.statusReads, reads);

      await tap(tester, button('Dismiss'));
      expect(find.text('Search for 2 titles on Films'), findsNothing);
      await app.stop(tester);
    });

    testWidgets('reports a refusal and an unknown outcome by title', (
      tester,
    ) async {
      final commands = await searchBoth(tester);
      commands.refused[1] = const OutcomeUnknown();
      commands.refused[2] = const Forbidden();
      await confirm(tester);
      await tester.pumpAndSettle();

      expect(find.text('Finished. 0 of 2 searches succeeded.'), findsOneWidget);
      expect(
        find.textContaining('Alpha (2000): The change may or may not'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Beta (2001): The server does not allow'),
        findsOneWidget,
      );
      expect(commands.searches, hasLength(2));
      await app.stop(tester);
    });

    testWidgets('gives up following a command that cannot be read', (
      tester,
    ) async {
      final commands = await searchBoth(tester);
      commands.status = (_) => const Err(Unreachable());
      await confirm(tester);

      for (var i = 0; i < 3; i++) {
        await poll(tester);
      }
      await tester.pumpAndSettle();

      expect(commands.statusReads, 6);
      expect(commands.searches, hasLength(2));
      expect(
        find.text('Alpha (2000): The outcome of the search is not known.'),
        findsOneWidget,
      );
      await app.stop(tester);
    });

    testWidgets('shows how it goes above a library that is scrolled down', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await start(tester, const Size(360, 740));
      await addServer('Films', [for (var i = 10; i < 50; i++) 'Title $i']);
      commandsOf['Films']!.refused[40] = const Forbidden();
      await openSelection(tester);
      await tester.scrollUntilVisible(
        find.text('Title 49'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Title 49'));
      await tester.pumpAndSettle();
      await tap(tester, button('Search'));
      await tap(tester, button('Search 1 title'));

      expect(
        find.text('Search for 1 title on Films').hitTestable(),
        findsOneWidget,
      );
      expect(
        find.text('Finished. 0 of 1 searches succeeded.').hitTestable(),
        findsOneWidget,
      );
      // The reason is there too, at most a short scroll of the notice away.
      expect(
        find.textContaining('Title 49 (2039): The server does not allow'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await app.stop(tester);
    });

    testWidgets('names forty titles under what will change', (tester) async {
      // The test font is about twice as wide as a device's, so this is much
      // like 200% text there.
      await start(tester, const Size(360, 640));
      await addServer('Films', ['Alpha']);
      await app.pump(tester);
      unawaited(
        showBulkEditSheet(
          tester.element(find.byType(NavigationBar)),
          instanceName: 'Films',
          titles: [for (var i = 1; i <= 40; i++) 'Title $i'],
          options: options,
        ),
      );
      await tester.pumpAndSettle();
      await choose(tester, 'Tags', 'Replace all tags');
      await tap(tester, button('Review changes'));

      expect(find.text('40 titles on Films').hitTestable(), findsOneWidget);
      expect(find.text('All tags are removed.').hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining('Title 1\nTitle 2')).dy,
        greaterThan(
          tester.getBottomLeft(find.text('All tags are removed.')).dy,
        ),
      );
      expect(button('Change 40 titles').hitTestable(), findsOneWidget);
      expect(libraries['Films']!.bulkEdits, isEmpty);
      await tap(tester, button('Cancel').last);
      await app.stop(tester);
    });

    testWidgets('does not overflow in landscape with the keyboard up', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      final commands = await searchBoth(tester);
      commands.refused[1] = const Forbidden();
      await confirm(tester);
      await tester.pumpAndSettle();

      tester.view
        ..physicalSize = const Size(800, 360)
        ..viewInsets = const FakeViewPadding(bottom: 140);
      await tester.pumpAndSettle();
      for (var inset = 100.0; inset <= 160; inset += 5) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$inset');
      }
      await app.stop(tester);
    });

    testWidgets('asks nothing while the library is out of sight', (
      tester,
    ) async {
      final commands = await searchBoth(tester);
      commands.status = (id) =>
          Ok(Command(id: id, name: 'search', status: CommandStatus.started));
      await confirm(tester);
      await tester.tap(find.text('More'));
      await pumpSome(tester);

      await poll(tester);
      expect(commands.statusReads, 0);

      await tester.tap(find.text('Library'));
      await pumpSome(tester);
      await poll(tester);
      expect(commands.statusReads, 2);
      await app.stop(tester);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('fits large text and is labelled, $brightness', (tester) async {
      tester.platformDispatcher
        ..textScaleFactorTestValue = 2
        ..platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await start(tester, const Size(320, 640));
      final id = await addServer('Films', ['Alpha', 'Beta']);
      libraries['Films']!.monitorOptions = [
        MonitorOption(id: 'none', label: (_) => 'None'),
      ];
      await app.pump(tester);
      final semantics = tester.ensureSemantics();

      Future<void> check() async {
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }

      navigatorOf(id).openEdit(refOf(id)).ignore();
      await tester.pumpAndSettle();
      await check();
      await tap(tester, find.byTooltip('Close'));

      navigatorOf(id).openDelete(refOf(id)).ignore();
      await tester.pumpAndSettle();
      await check();
      await tap(tester, button('Cancel'));

      await open(tester, 'Library');
      await check();
      await tap(tester, find.byTooltip('Select titles'));
      await tap(tester, find.text('Alpha'));
      await check();
      await tap(tester, button('Edit'));
      await check();
      semantics.dispose();
      await app.stop(tester);
    });
  }
}
