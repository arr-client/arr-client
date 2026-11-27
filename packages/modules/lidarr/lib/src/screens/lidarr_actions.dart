/// What the user can do on the artist and album screens (spec stories 5 and 8):
/// the controls, and what each says about how it went. Nothing is sent a second
/// time.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/lidarr_localizations.dart';
import 'labels.dart';
import 'lidarr_actions_controller.dart';
import 'lidarr_controllers.dart';
import 'lidarr_sources.dart';

/// Keeps the actions on [target] for as long as the screen is shown, although
/// their controls may scroll away, and says when the screen is covered.
class LidarrActionsScope extends ConsumerWidget {
  /// Creates the scope of a screen.
  const LidarrActionsScope({
    required this.sources,
    required this.target,
    required this.child,
    super.key,
  });

  /// The instance's.
  final LidarrSources sources;

  /// An artist or album.
  final MediaTarget target;

  /// The screen.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = lidarrActionsProvider((sources, target));
    ref.listen(provider, (_, _) {});
    return RouteCurrentListener(
      onChanged: (current) => ref.read(provider.notifier).shown = current,
      child: child,
    );
  }
}

/// The monitoring switch, the searches and how the started tasks are doing.
///
/// They must be below a [LidarrActionsScope] of the same target.
class LidarrActions extends ConsumerWidget {
  /// Creates the actions on [target].
  const LidarrActions({
    required this.sources,
    required this.target,
    required this.monitored,
    required this.isStale,
    super.key,
  });

  /// The instance's.
  final LidarrSources sources;

  /// An artist or album.
  final MediaTarget target;

  /// Whether the server monitors it.
  final bool monitored;

  /// Whether what is shown may be out of date, so that nothing is changed.
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = LidarrLocalizations.of(context);
    final key = (sources, target);
    final state = ref.watch(lidarrActionsProvider(key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
    final strings = LidarrLocalizations.of(context);
    final controller = ref.read(
      lidarrActionsProvider((sources, target)).notifier,
    );
    final (on, off) = target.item.kind == MediaKind.album
        ? (strings.albumMonitorOnAccepted, strings.albumMonitorOffAccepted)
        : (strings.artistMonitorOnAccepted, strings.artistMonitorOffAccepted);
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
  final controller = ref.read(lidarrActionsProvider(key).notifier);
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
  final controller = ref.read(lidarrActionsProvider(key).notifier);
  await open();
  await controller.reload();
}

/// Asks for confirmation naming [file], then deletes it from the instance that
/// listed it as the file of [track].
Future<void> deleteTrackFile(
  BuildContext context,
  WidgetRef ref,
  LidarrSources sources,
  Track track,
  MediaFile file,
) async {
  final strings = LidarrLocalizations.of(context);
  // The album whose tracks list this one.
  final album = track.parent;
  if (album == null) return;
  final confirmed = await showConfirmDialog(
    context,
    title: strings.deleteFileTitle,
    target: file.path,
    consequence: strings.deleteFileConsequence(trackTitle(strings, track)),
    confirmLabel: strings.deleteFile,
  );
  if (!confirmed || !context.mounted) return;

  // The screen may have been read again while the dialog was open.
  final stillListed = switch (ref.read(tracksProvider((sources, album)))) {
    ViewData(:final value, staleness: null) => value.any(
      (now) =>
          now.ref == track.ref &&
          now.file?.id == file.id &&
          now.file?.path == file.path,
    ),
    _ => false,
  };
  if (!stillListed) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(strings.fileChanged)));
    return;
  }
  final controller = ref.read(
    lidarrActionsProvider((sources, MediaTarget(album))).notifier,
  );
  await runAction<void>(
    context,
    action: () => controller.deleteFile(file),
    acceptedMessage: strings.fileDeleted,
    // The controller reads the album again itself, and holds the buttons back
    // until it has.
    onRefresh: () {},
  );
}

/// What the menu of a screen offers.
enum _MenuEntry { edit, refresh, rescan, delete }

/// The less frequent actions on an artist or album, in the app bar.
///
/// An album has no settings of its own beyond monitoring, which its switch
/// changes: its profiles and tags are the artist's.
class LidarrMenu extends ConsumerWidget {
  /// Creates the menu of [item].
  const LidarrMenu({
    required this.sources,
    required this.item,
    required this.isStale,
    super.key,
  });

  /// The instance's.
  final LidarrSources sources;

  /// The artist or album.
  final ItemRef item;

  /// Whether the item may be out of date, so that nothing is changed.
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = LidarrLocalizations.of(context);
    final target = MediaTarget(item);
    final key = (sources, target);
    final commands = ref.watch(
      lidarrActionsProvider(key).select((state) => state.commands),
    );
    final navigator = sources.navigator;
    final isAlbum = item.kind == MediaKind.album;

    PopupMenuItem<_MenuEntry> entry(
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
      onSelected: (chosen) => unawaited(switch (chosen) {
        _MenuEntry.edit => _openFlow(ref, key, () => navigator.openEdit(item)),
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
          () => navigator.openDelete(item),
        ),
      }),
      itemBuilder: (context) => [
        if (!isAlbum) entry(_MenuEntry.edit, strings.editArtist),
        if (sources.commands.supports(CommandAction.refresh, target))
          entry(
            _MenuEntry.refresh,
            strings.refreshMetadata,
            command: CommandAction.refresh,
          ),
        if (sources.commands.supports(CommandAction.rescan, target))
          entry(
            _MenuEntry.rescan,
            strings.rescanFiles,
            command: CommandAction.rescan,
          ),
        entry(
          _MenuEntry.delete,
          isAlbum ? strings.deleteAlbum : strings.deleteArtist,
        ),
      ],
    );
  }
}
