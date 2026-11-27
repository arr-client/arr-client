import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/bazarr_localizations.dart';
import '../subtitles_route.dart';
import 'labels.dart';
import 'read_controllers.dart';
import 'request_note.dart';
import 'requests.dart';
import 'title_actions.dart';

/// The subtitles of a movie or episode: what it lacks, with the searches, and
/// its files, with synchronization and deletion.
class SubtitleTitleScreen extends ConsumerWidget {
  /// Creates the screen of [target], on the instance called [name].
  const SubtitleTitleScreen({
    required this.target,
    required this.name,
    super.key,
  });

  /// The movie or episode.
  final MediaKey target;

  /// The instance's name.
  final String name;

  Future<void> _refresh(WidgetRef ref) {
    ref.read(requestsProvider.notifier).forget(target.source, target.media);
    return ref.read(titleProvider(target).notifier).reload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = BazarrLocalizations.of(context);
    final state = ref.watch(titleProvider(target));
    final request = ref.watch(
      requestsProvider,
    )[(instanceId: target.source.instanceId, media: target.media)];
    final series = switch (target.media) {
      SubtitleMedia(kind: SubtitleKind.episode, :final seriesId?) =>
        ref
            .watch(
              seriesNameProvider((
                source: target.source,
                media: SubtitleMedia.series(seriesId),
              )),
            )
            .value,
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.subtitlesTitle),
        actions: [
          IconButton(
            tooltip: strings.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_refresh(ref)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: StateScaffold<SubtitleTitle>(
            state: state,
            onRetry: () => unawaited(_refresh(ref)),
            itemId: target.media,
            builder: (_, title, {required isStale}) => _body(
              // The screen's context, which outlives the rows.
              context,
              ref,
              title,
              series,
              request,
              // Nothing is changed from what may be out of date, or while
              // another change is under way.
              enabled: !isStale && request != RequestState.sending,
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    SubtitleTitle title,
    String? series,
    RequestState? request, {
    required bool enabled,
  }) {
    final strings = BazarrLocalizations.of(context);
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleMedium),
      ),
    );
    final heads = serverText(title.title) ?? strings.untitled;

    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(screenMargin(constraints.maxWidth)),
        children: [
          if (request != null)
            RequestNote(
              state: request,
              name: name,
              actionLabel: strings.refresh,
              actionIcon: Icons.refresh,
              onAction: () => unawaited(_refresh(ref)),
            ),
          if (serverText(series) case final series?)
            Text(series, style: theme.textTheme.titleMedium),
          Text(switch (title.year) {
            final year? => strings.titleWithYear(heads, '$year'),
            null => heads,
          }, style: theme.textTheme.titleLarge),
          heading(strings.missingHeading),
          if (title.missing.isEmpty) Text(strings.nothingMissing),
          for (final language in title.missing)
            _Action(
              text: languageLabel(strings, language),
              buttons: [
                TextButton.icon(
                  onPressed: enabled
                      ? () => unawaited(
                          searchSubtitle(context, ref, target, name, language),
                        )
                      : null,
                  icon: const Icon(Icons.search),
                  label: Text(
                    strings.automaticSearch,
                    semanticsLabel: strings.automaticSearchFor(
                      languageLabel(strings, language),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: enabled
                  ? () => unawaited(
                      context.push<void>(
                        searchRoute(
                          target.source.instanceId,
                          target.media,
                        ).location,
                      ),
                    )
                  : null,
              icon: const Icon(Icons.manage_search),
              label: Text(strings.manualSearch),
            ),
          ),
          heading(strings.filesHeading),
          if (title.files.isEmpty) Text(strings.noFiles),
          for (final file in title.files)
            _Action(
              text:
                  '${languageLabel(strings, file.language)}\n'
                  '${pathText(file.path)}',
              buttons: [
                TextButton.icon(
                  onPressed: enabled
                      ? () => unawaited(
                          syncSubtitle(context, ref, target, name, file),
                        )
                      : null,
                  icon: const Icon(Icons.sync),
                  label: Text(
                    strings.syncButton,
                    semanticsLabel: strings.syncFile(pathText(file.path)),
                  ),
                ),
                TextButton.icon(
                  onPressed: enabled
                      ? () => unawaited(
                          deleteSubtitle(context, ref, target, name, file),
                        )
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    strings.deleteButton,
                    semanticsLabel: strings.deleteFile(pathText(file.path)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A language or file with what can be done with it.
class _Action extends StatelessWidget {
  const _Action({required this.text, required this.buttons});

  final String text;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text),
        Wrap(spacing: 8, children: buttons),
        const Divider(height: 1),
      ],
    ),
  );
}
