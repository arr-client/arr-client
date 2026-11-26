import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_labels.dart';
import '../queue/queue_watch.dart';
import 'import_action.dart';
import 'import_file.dart';
import 'import_file_tile.dart';
import 'import_status.dart';
import 'manual_import_controller.dart';

/// The manual import of the download of one queue entry.
class ManualImportScreen extends ConsumerStatefulWidget {
  const ManualImportScreen({
    required this.instance,
    required this.queueId,
    super.key,
  });

  /// The instance whose queue has the entry.
  final ActiveInstance instance;

  /// Null if the route did not name a number, so no entry matches.
  final int? queueId;

  @override
  ConsumerState<ManualImportScreen> createState() => _ManualImportScreenState();
}

class _ManualImportScreenState extends ConsumerState<ManualImportScreen> {
  /// The entry as first seen. The screen stays with its download even when
  /// the entry leaves the queue, as it does once imported.
  QueueItem? _item;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final instance = widget.instance;
    Widget page(Widget body) => Scaffold(
      appBar: AppBar(title: Text(strings.manualImportTitle)),
      body: SafeArea(child: body),
    );

    if (instance.capability(CapabilityKind.queue) == null ||
        importNeedsEpisodes(instance) == null) {
      return page(
        StateMessage(icon: Icons.info_outline, message: strings.notOffered),
      );
    }
    if (_item case final item?) {
      return _Import(
        instance: instance,
        importKey: (
          instanceId: instance.instance.id,
          client: instance.context.http,
          item: item,
        ),
      );
    }
    return page(
      QueueWatch(
        child: Consumer(
          builder: (context, ref, _) {
            final id = widget.queueId;
            final queue = ref.watch(queueProvider).queue(instance.instance.id);
            final found = id == null ? null : queue?.item(id);
            if (found != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _item == null) setState(() => _item = found);
              });
            } else if (queue?.items != null) {
              return StateMessage(
                icon: Icons.inbox_outlined,
                message: strings.queueEntryGone,
                announce: true,
              );
            } else if (queue?.failure case final failure?) {
              return StateScaffold<void>(
                state: ViewError(failure),
                onRetry: () => unawaited(
                  ref.read(queueProvider.notifier).retry(instance.instance.id),
                ),
                builder: (_, _, {required isStale}) => const SizedBox.shrink(),
              );
            }
            return Center(
              child: CircularProgressIndicator(
                semanticsLabel: UiLocalizations.of(context).loading,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Import extends ConsumerWidget {
  const _Import({required this.instance, required this.importKey});

  final ActiveInstance instance;
  final ManualImportKey importKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final provider = manualImportProvider(importKey);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final files = state.files;
    final fetchedAt = state.fetchedAt;
    final failure = state.failure;

    final ViewState<Object> view;
    if (files != null && fetchedAt != null) {
      view = ViewData(
        files,
        // While they are read again after a failure, the notice shows
        // progress.
        staleness: failure == null
            ? null
            : Staleness(
                fetchedAt: fetchedAt,
                failure: state.loading ? null : failure,
              ),
      );
    } else if (failure != null && !state.loading) {
      view = ViewError(failure);
    } else {
      view = const ViewLoading();
    }
    final selected = [
      for (final file in files ?? const <ImportFile>[])
        if (file.selected) file,
    ];
    final importable = state.importable;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.manualImportTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.manualImportRefresh,
            onPressed: state.loading || state.sending
                ? null
                : () => unawaited(controller.reload()),
          ),
        ],
      ),
      body: SafeArea(
        child: StateScaffold<Object>(
          state: view,
          onRetry: () => unawaited(controller.retry()),
          builder: (context, _, {required isStale}) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      queueTitle(strings, importKey.item),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(instance.instance.name),
                  ],
                ),
              ),
              ImportStatus(
                instanceName: instance.instance.name,
                state: state,
                controller: controller,
              ),
              if (state.loading)
                LinearProgressIndicator(
                  semanticsLabel: UiLocalizations.of(context).loading,
                ),
              if (files!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(strings.manualImportEmpty),
                )
              else
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TextButton(
                      onPressed:
                          state.canChange &&
                              (selected.isNotEmpty ||
                                  files.any(
                                    (file) => state.isReady(file.candidate),
                                  ))
                          ? () => controller.selectAll(selected.isEmpty)
                          : null,
                      child: Text(
                        selected.isEmpty
                            ? strings.manualImportSelectAll
                            : strings.manualImportSelectNone,
                      ),
                    ),
                  ),
                ),
              for (final file in files)
                ImportFileTile(
                  key: ValueKey(file.path),
                  file: file,
                  state: state,
                  controller: controller,
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: files == null || files.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: state.sending
                    ? LinearProgressIndicator(
                        semanticsLabel: strings.manualImportSending,
                      )
                    : FilledButton(
                        onPressed: importable.isEmpty
                            ? null
                            : () => unawaited(
                                confirmImport(
                                  context,
                                  instanceName: instance.instance.name,
                                  state: state,
                                  files: importable,
                                  controller: controller,
                                ),
                              ),
                        child: Text(
                          strings.manualImportAction(selected.length),
                        ),
                      ),
              ),
            ),
    );
  }
}
