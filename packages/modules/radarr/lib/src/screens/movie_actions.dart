/// What the user can do on the movie screen (spec story 5): the controls, and
/// what each says about how it went. Nothing is sent a second time.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/radarr_localizations.dart';
import 'movie_actions_controller.dart';
import 'movie_detail_controller.dart';

/// The monitoring switch, the searches and how the started tasks are doing.
class MovieActions extends ConsumerWidget {
  /// Creates the actions on [movie].
  const MovieActions({
    required this.source,
    required this.movie,
    required this.isStale,
    super.key,
  });

  /// Whose movie.
  final MovieDetailSource source;

  /// The movie as shown.
  final Movie movie;

  /// Whether the movie may be out of date, so that nothing is changed.
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = RadarrLocalizations.of(context);
    final provider = movieActionsProvider(source);
    final state = ref.watch(provider);
    final target = MediaTarget(movie.ref);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonitorSwitch(
          value: state.monitored ?? movie.monitored,
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
            if (source.commands.supports(CommandAction.search, target))
              FilledButton.icon(
                icon: const Icon(Icons.search),
                label: Text(strings.movieAutomaticSearch),
                onPressed:
                    isStale ||
                        (state.commands[CommandAction.search]?.busy ?? false)
                    ? null
                    : () => unawaited(
                        startMovieCommand(
                          context,
                          ref,
                          source,
                          CommandAction.search,
                        ),
                      ),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.manage_search),
              label: Text(strings.movieInteractiveSearch),
              onPressed: isStale
                  ? null
                  : () => unawaited(
                      openMovieFlow(
                        ref,
                        source,
                        () => source.instance.navigator.openReleases(target),
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
    final strings = RadarrLocalizations.of(context);
    final controller = ref.read(movieActionsProvider(source).notifier);
    return runAction<void>(
      context,
      action: () => controller.setMonitored(monitored),
      acceptedMessage: monitored
          ? strings.movieMonitorOnAccepted
          : strings.movieMonitorOffAccepted,
      onRefresh: () => unawaited(controller.reload()),
      onGone: () => unawaited(controller.reload()),
    );
  }
}

/// Starts [action] on the movie of [source] and says whether it was accepted.
Future<void> startMovieCommand(
  BuildContext context,
  WidgetRef ref,
  MovieDetailSource source,
  CommandAction action,
) {
  final controller = ref.read(movieActionsProvider(source).notifier);
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

/// Opens a flow of the app and, once it is closed, reads the movie again, as
/// the flow may have changed or deleted it.
Future<void> openMovieFlow(
  WidgetRef ref,
  MovieDetailSource source,
  Future<void> Function() open,
) async {
  final controller = ref.read(movieActionsProvider(source).notifier);
  await open();
  await controller.reload();
}

/// Asks for confirmation naming [file], then deletes it from the instance that
/// listed it.
Future<void> deleteMovieFile(
  BuildContext context,
  WidgetRef ref,
  MovieDetailSource source,
  Movie movie,
  MediaFile file,
) async {
  final strings = RadarrLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context,
    title: strings.movieDeleteFileTitle,
    target: file.path,
    consequence: strings.movieDeleteFileConsequence(movie.title),
    confirmLabel: strings.movieDeleteFile,
  );
  if (!confirmed || !context.mounted) return;

  // The screen may have been read again while the dialog was open.
  final detail = ref.read(movieDetailProvider(source));
  final stillListed = switch ((detail.movie, detail.files)) {
    (ViewData(staleness: null), ViewData(:final value, staleness: null)) =>
      value.any((now) => now.id == file.id && now.path == file.path),
    _ => false,
  };
  if (!stillListed) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(strings.movieFileChanged)));
    return;
  }
  final controller = ref.read(movieActionsProvider(source).notifier);
  await runAction<void>(
    context,
    action: () => controller.deleteFile(file),
    acceptedMessage: strings.movieFileDeleted,
    // The controller reads the movie again itself, and holds the button back
    // until it has.
    onRefresh: () {},
  );
}

/// What the menu of the movie screen offers.
enum _MenuEntry { edit, refresh, rescan, delete }

/// The less frequent actions on a movie, in the app bar.
class MovieMenu extends ConsumerWidget {
  /// Creates the menu of [movie].
  const MovieMenu({
    required this.source,
    required this.movie,
    required this.isStale,
    super.key,
  });

  /// Whose movie.
  final MovieDetailSource source;

  /// The movie as shown.
  final Movie movie;

  /// Whether the movie may be out of date, so that nothing is changed.
  final bool isStale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = RadarrLocalizations.of(context);
    final commands = ref.watch(
      movieActionsProvider(source).select((state) => state.commands),
    );
    final target = MediaTarget(movie.ref);
    final navigator = source.instance.navigator;

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
      tooltip: strings.movieMoreActions,
      enabled: !isStale,
      onSelected: (entry) => unawaited(switch (entry) {
        _MenuEntry.edit => openMovieFlow(
          ref,
          source,
          () => navigator.openEdit(movie.ref),
        ),
        _MenuEntry.refresh => startMovieCommand(
          context,
          ref,
          source,
          CommandAction.refresh,
        ),
        _MenuEntry.rescan => startMovieCommand(
          context,
          ref,
          source,
          CommandAction.rescan,
        ),
        _MenuEntry.delete => openMovieFlow(
          ref,
          source,
          () => navigator.openDelete(movie.ref),
        ),
      }),
      itemBuilder: (context) => [
        item(_MenuEntry.edit, strings.movieEdit),
        if (source.commands.supports(CommandAction.refresh, target))
          item(
            _MenuEntry.refresh,
            strings.movieRefreshMetadata,
            command: CommandAction.refresh,
          ),
        if (source.commands.supports(CommandAction.rescan, target))
          item(
            _MenuEntry.rescan,
            strings.movieRescanFiles,
            command: CommandAction.rescan,
          ),
        item(_MenuEntry.delete, strings.movieDelete),
      ],
    );
  }
}
