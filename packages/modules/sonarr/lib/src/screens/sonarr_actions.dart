/// What the user can do on the series, season and episode screens (spec story
/// 5): the controls, and what each says about how it went. Nothing is sent a
/// second time.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/sonarr_localizations.dart';
import 'labels.dart';
import 'sonarr_actions_controller.dart';
import 'sonarr_controllers.dart';
import 'sonarr_sources.dart';

/// Keeps the actions on [target] for as long as the screen is shown, although
/// their controls may scroll away, and says when the screen is covered.
class SonarrActionsScope extends ConsumerWidget {
  /// Creates the scope of a screen.
  const SonarrActionsScope({
    required this.sources,
    required this.target,
    required this.child,
    super.key,
  });

  /// The instance's.
  final SonarrSources sources;

  /// A series, one of its seasons or an episode.
  final MediaTarget target;

  /// The screen.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = sonarrActionsProvider((sources, target));
    ref.listen(provider, (_, _) {});
    return RouteCurrentListener(
      onChanged: (current) => ref.read(provider.notifier).shown = current,
      child: child,
    );
  }
}

/// The monitoring switch, the searches and how the started tasks are doing.
///
/// They must be below a [SonarrActionsScope] of the same target.
class SonarrActions extends ConsumerWidget {
  /// Creates the actions on [target].
  const SonarrActions({
    required this.sources,
    required this.target,
    required this.monitored,
    required this.isStale,
    super.key,
  });

  /// The instance's.
  final SonarrSources sources;

  /// A series, one of its seasons or an episode.
  final MediaTarget target;

  /// Whether the server monitors it. Null while that is not known: there is
  /// then no switch.
  final bool? monitored;

  /// Whether what is shown may be out of date, so that nothing is changed.
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = SonarrLocalizations.of(context);
    final key = (sources, target);
    final state = ref.watch(sonarrActionsProvider(key));
    // Sonarr has no interactive search of a whole series.
    final hasReleases =
        target.item.kind == MediaKind.episode || target.seasonNumber != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (monitored case final monitored?)
          MonitorSwitch(
            value: state.monitored ?? monitored,
            saving: state.savingMonitored,
            onChanged: isStale
                ? null
                : (value) => unawaited(_setMonitored(context, ref, value)),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (sources.commands.supports(CommandAction.search, target))
              FilledButton.icon(
                icon: const Icon(Icons.search),
                label: Text(strings.automaticSearch),
                onPressed:
                    isStale ||
                        (state.commands[CommandAction.search]?.busy ?? false)
                    ? null
                    : () => unawaited(
                        _startCommand(context, ref, key, CommandAction.search),
                      ),
              ),
            if (hasReleases)
              OutlinedButton.icon(
                icon: const Icon(Icons.manage_search),
                label: Text(strings.interactiveSearch),
                onPressed: isStale
                    ? null
                    : () => unawaited(
                        _openFlow(
                          ref,
                          key,
                          () => sources.navigator.openReleases(target),
                        ),
                      ),
              ),
          ],
        ),
        for (final action in CommandAction.values)
          if (state.commands[action] case final progress?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CommandProgressView(action: action, progress: progress),
            ),
      ],
    );
  }

  Future<void> _setMonitored(
    BuildContext context,
    WidgetRef ref,
    bool monitored,
  ) {
    final strings = SonarrLocalizations.of(context);
    final controller = ref.read(
      sonarrActionsProvider((sources, target)).notifier,
    );
    final (on, off) = switch ((target.item.kind, target.seasonNumber)) {
      (MediaKind.episode, _) => (
        strings.episodeMonitorOnAccepted,
        strings.episodeMonitorOffAccepted,
      ),
      (_, null) => (
        strings.seriesMonitorOnAccepted,
        strings.seriesMonitorOffAccepted,
      ),
      _ => (strings.seasonMonitorOnAccepted, strings.seasonMonitorOffAccepted),
    };
    return runAction<void>(
      context,
      action: () => controller.setMonitored(monitored),
      acceptedMessage: monitored ? on : off,
      onRefresh: () => unawaited(controller.reload()),
      onGone: () => unawaited(controller.reload()),
    );
  }
}

/// Starts [action] on the target of [key] and says whether it was accepted.
Future<void> _startCommand(
  BuildContext context,
  WidgetRef ref,
  TargetKey key,
  CommandAction action,
) {
  final controller = ref.read(sonarrActionsProvider(key).notifier);
  return runAction<Command>(
    context,
    action: () => controller.start(action),
    acceptedMessage: commandAcceptedMessage(
      UiLocalizations.of(context),
      action,
    ),
    onRefresh: () => unawaited(controller.reload()),
    onGone: () => unawaited(controller.reload()),
  );
}

/// Opens a flow of the app and, once it is closed, reads from the server again,
/// as the flow may have changed or deleted what is shown.
Future<void> _openFlow(
  WidgetRef ref,
  TargetKey key,
  Future<void> Function() open,
) async {
  final controller = ref.read(sonarrActionsProvider(key).notifier);
  await open();
  await controller.reload();
}

/// Asks for confirmation naming [file], then deletes it from the instance that
/// listed it as the file of [episode].
Future<void> deleteEpisodeFile(
  BuildContext context,
  WidgetRef ref,
  SonarrSources sources,
  Episode episode,
  MediaFile file,
) async {
  final strings = SonarrLocalizations.of(context);
  final code = episodeCode(strings, episode);
  final confirmed = await showConfirmDialog(
    context,
    title: strings.deleteFileTitle,
    target: file.path,
    consequence: strings.deleteFileConsequence(switch (episode.parentTitle) {
      final series? => strings.fileOfEpisode(series, code),
      null => code,
    }),
    confirmLabel: strings.deleteFile,
  );
  if (!confirmed || !context.mounted) return;

  // The screen may have been read again while the dialog was open.
  final now = ref.read(episodeProvider((sources, episode.ref)));
  final stillListed = switch (now) {
    ViewData(:final value, staleness: null) =>
      value.file?.id == file.id && value.file?.path == file.path,
    _ => false,
  };
  if (!stillListed) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(strings.fileChanged)));
    return;
  }
  final controller = ref.read(
    sonarrActionsProvider((sources, MediaTarget(episode.ref))).notifier,
  );
  await runAction<void>(
    context,
    action: () => controller.deleteFile(file),
    acceptedMessage: strings.fileDeleted,
    // The controller reads the episode again itself, and holds the button back
    // until it has.
    onRefresh: () {},
  );
}

/// What the menu of the series screen offers.
enum _MenuEntry { edit, refresh, rescan, delete }

/// The less frequent actions on a series, in the app bar. The server has none
/// of them for a season or an episode.
class SeriesMenu extends ConsumerWidget {
  /// Creates the menu of [series].
  const SeriesMenu({
    required this.sources,
    required this.series,
    required this.isStale,
    super.key,
  });

  /// The instance's.
  final SonarrSources sources;

  /// The series.
  final ItemRef series;

  /// Whether the series may be out of date, so that nothing is changed.
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = SonarrLocalizations.of(context);
    final target = MediaTarget(series);
    final key = (sources, target);
    final commands = ref.watch(
      sonarrActionsProvider(key).select((state) => state.commands),
    );
    final navigator = sources.navigator;

    PopupMenuItem<_MenuEntry> item(
      _MenuEntry value,
      String label, {
      CommandAction? command,
    }) => PopupMenuItem(
      value: value,
      enabled: !(commands[command]?.busy ?? false),
      child: Text(label),
    );

    return PopupMenuButton<_MenuEntry>(
      tooltip: strings.moreActions,
      enabled: !isStale,
      onSelected: (entry) => unawaited(switch (entry) {
        _MenuEntry.edit => _openFlow(
          ref,
          key,
          () => navigator.openEdit(series),
        ),
        _MenuEntry.refresh => _startCommand(
          context,
          ref,
          key,
          CommandAction.refresh,
        ),
        _MenuEntry.rescan => _startCommand(
          context,
          ref,
          key,
          CommandAction.rescan,
        ),
        _MenuEntry.delete => _openFlow(
          ref,
          key,
          () => navigator.openDelete(series),
        ),
      }),
      itemBuilder: (context) => [
        item(_MenuEntry.edit, strings.editSeries),
        if (sources.commands.supports(CommandAction.refresh, target))
          item(
            _MenuEntry.refresh,
            strings.refreshMetadata,
            command: CommandAction.refresh,
          ),
        if (sources.commands.supports(CommandAction.rescan, target))
          item(
            _MenuEntry.rescan,
            strings.rescanFiles,
            command: CommandAction.rescan,
          ),
        item(_MenuEntry.delete, strings.deleteSeries),
      ],
    );
  }
}
