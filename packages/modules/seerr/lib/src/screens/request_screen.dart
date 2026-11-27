import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../adapters/seasons.dart';
import '../l10n/generated/seerr_localizations.dart';
import 'labels.dart';
import 'request_rules.dart';
import 'request_sends.dart';
import 'seasons_controller.dart';
import 'seerr_source.dart';
import 'title_controller.dart';
import 'title_parts.dart';

/// Requesting one variant of a title, with the seasons of a series.
class RequestScreen extends ConsumerStatefulWidget {
  /// Creates the screen that requests [wanted].
  const RequestScreen({
    required this.source,
    required this.wanted,
    required this.is4k,
    super.key,
  });

  /// The instance's.
  final SeerrSource source;

  /// The title.
  final DiscoveryRef wanted;

  /// Whether the 4K variant is asked for.
  final bool is4k;

  @override
  ConsumerState<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends ConsumerState<RequestScreen> {
  // The seasons ticked.
  final _chosen = <int>{};

  TitleKey get _key => (widget.source, widget.wanted);

  SeasonsKey get _seasonsKey =>
      (source: widget.source, tmdbId: widget.wanted.tmdbId, is4k: widget.is4k);

  SendKey get _sendKey => (
    instanceId: widget.source.instanceId,
    title: widget.wanted,
    is4k: widget.is4k,
  );

  Future<void> _refresh() async {
    ref.invalidate(seasonsProvider(_seasonsKey));
    await ref.read(titleProvider(_key).notifier).refresh();
  }

  Future<void> _send(DiscoveryTitle title, List<int> seasons) async {
    final strings = SeerrLocalizations.of(context);
    final sends = ref.read(requestSendsProvider.notifier);
    if (ref.read(requestSendsProvider)[_sendKey] == SendMark.unknown) {
      final confirmed = await showConfirmDialog(
        context,
        title: strings.sendAgainTitle,
        target: title.title,
        consequence: strings.sendUnknown,
        confirmLabel: strings.sendAgain,
        destructive: false,
      );
      // An edit of the instance takes the screen from under the dialog.
      if (!confirmed || !mounted) return;
    }

    // Null if another one got in first, which then says how it went.
    final sending = sends.send(
      widget.source,
      title,
      is4k: widget.is4k,
      seasons: seasons,
    );
    if (sending == null) return;
    final route = ModalRoute.of(context);
    ServiceFailure? failure;
    final result = await runAction<MediaRequest>(
      context,
      action: () async {
        final result = await sending;
        if (result case Err(:final error)) failure = error;
        return result;
      },
      acceptedMessage: strings.requestSent(title.title),
      describeFailure: (message) => switch (failure) {
        OutcomeUnknown() => strings.requestOutcomeUnknown(title.title),
        Conflict() => strings.requestExists(title.title),
        // The server's own words say why, such as a used up quota.
        Validation(:final messages) => switch (serverText(messages.join(' '))) {
          final reason? => strings.requestRefused(title.title, reason),
          null => strings.requestNotSent(title.title, message),
        },
        _ => strings.requestNotSent(title.title, message),
      },
      // What the screens show is read again whatever the answer.
      onRefresh: () {},
    );
    // Back to where the request shows with its status.
    if (result is Ok && mounted && (route?.isCurrent ?? false)) {
      await Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SeerrLocalizations.of(context);
    final state = ref.watch(titleProvider(_key));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.is4k ? strings.request4k : strings.request),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.refresh,
            onPressed: () => unawaited(_refresh()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: StateScaffold<TitlePage>(
          state: state,
          itemId: widget.wanted,
          onRetry: () => unawaited(_refresh()),
          builder: (context, page, {required isStale}) =>
              _form(context, page, isStale: isStale),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, TitlePage page, {required bool isStale}) {
    final strings = SeerrLocalizations.of(context);
    final theme = Theme.of(context);
    final title = page.title;
    final user = page.user;
    final isSeries = title.mediaType == DiscoveryMediaType.series;
    final block = user == null
        ? null
        : requestBlock(title, user, is4k: widget.is4k);
    final offered = user != null && block == null;
    final mark = ref.watch(requestSendsProvider)[_sendKey];

    // Read only for a series that is on offer.
    final seasons = offered && isSeries
        ? ref.watch(seasonsProvider(_seasonsKey))
        : null;
    final choices = switch (seasons?.value) {
      Ok(:final value) => value,
      _ => null,
    };
    final open = [
      for (final season in choices?.seasons ?? const <SeasonChoice>[])
        if (season.isOpen) season.number,
    ];
    // A season that is no longer open is not sent.
    final selected = choices?.mayChoose ?? true
        ? [
            for (final number in open)
              if (_chosen.contains(number)) number,
          ]
        : open;
    final ready =
        !isSeries || selected.isNotEmpty && !(seasons?.isLoading ?? true);

    final usage = switch (title.mediaType) {
      DiscoveryMediaType.movie => user?.quota?.movies,
      DiscoveryMediaType.series => user?.quota?.series,
    };

    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        padding: EdgeInsets.all(screenMargin(constraints.maxWidth)),
        children: [
          Text(title.title, style: theme.textTheme.titleLarge),
          Text(titleFacts(strings, title)),
          Text(widget.is4k ? strings.variant4k : strings.variantStandard),
          if (page.userFailure case final failure?) ...[
            const SizedBox(height: 16),
            Text(strings.permissionsUnread),
            Text(failureMessage(context, failure)),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => unawaited(_refresh()),
                child: Text(UiLocalizations.of(context).retry),
              ),
            ),
          ],
          if (block case final block?) ...[
            const SizedBox(height: 16),
            Text(switch (block) {
              RequestBlock.notPermitted => strings.blockNotPermitted,
              RequestBlock.blocklisted => strings.blockBlocklisted,
              RequestBlock.available => strings.blockAvailable,
              RequestBlock.requested => strings.blockRequested,
            }),
          ],
          if (offered) ...[
            if (usage != null) ...[
              const SizedBox(height: 16),
              Text(
                isSeries ? strings.quotaSeries : strings.quotaMovies,
                style: theme.textTheme.titleSmall,
              ),
              Text(quotaLabel(strings, usage)),
            ],
            if (seasons != null) ..._seasons(context, seasons, open),
            if (mark == SendMark.unknown) ...[
              const SizedBox(height: 16),
              Semantics(liveRegion: true, child: Text(strings.sendUnknown)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isStale || !ready || mark == SendMark.sending
                  ? null
                  : () =>
                        unawaited(_send(title, isSeries ? selected : const [])),
              child: Text(
                mark == SendMark.sending
                    ? strings.sending
                    : switch (title.mediaType) {
                        DiscoveryMediaType.movie => strings.requestMovie,
                        DiscoveryMediaType.series => strings.requestSeasons(
                          selected.length,
                        ),
                      },
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _seasons(
    BuildContext context,
    AsyncValue<Result<SeasonChoices, ServiceFailure>> seasons,
    List<int> open,
  ) {
    final strings = SeerrLocalizations.of(context);
    final heading = [
      const SizedBox(height: 16),
      Semantics(
        header: true,
        child: Text(
          strings.seasons,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    ];
    switch (seasons.value) {
      case null:
        return [
          ...heading,
          Center(
            child: CircularProgressIndicator(
              semanticsLabel: UiLocalizations.of(context).loading,
            ),
          ),
        ];
      case Err(:final error):
        return [
          ...heading,
          Semantics(
            liveRegion: true,
            child: Text(failureMessage(context, error)),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => ref.invalidate(seasonsProvider(_seasonsKey)),
              child: Text(UiLocalizations.of(context).retry),
            ),
          ),
        ];
      case Ok(value: SeasonChoices(seasons: final all, :final mayChoose)):
        final ticked = open.where(_chosen.contains).length;
        return [
          ...heading,
          if (open.isEmpty)
            Text(strings.noSeasonsOpen)
          else if (!mayChoose)
            Text(strings.allSeasonsOnly)
          else
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              tristate: true,
              value: ticked == 0
                  ? false
                  : ticked == open.length
                  ? true
                  : null,
              onChanged: (_) => setState(() {
                if (ticked == open.length) {
                  _chosen.clear();
                } else {
                  _chosen.addAll(open);
                }
              }),
              title: Text(strings.allSeasons),
            ),
          for (final season in all)
            CheckboxListTile(
              key: ValueKey(season.number),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value:
                  season.isOpen &&
                  (!mayChoose || _chosen.contains(season.number)),
              onChanged: season.isOpen && mayChoose
                  ? (value) => setState(() {
                      if (value ?? false) {
                        _chosen.add(season.number);
                      } else {
                        _chosen.remove(season.number);
                      }
                    })
                  : null,
              title: Text(
                season.number == 0
                    ? strings.specials
                    : strings.seasonNumber(season.number),
              ),
              subtitle: switch ([
                if (season.episodeCount case final count?)
                  strings.episodeCount(count),
                if (season.requested)
                  strings.seasonRequested
                else if (season.availability != Availability.unknown)
                  availabilityLabel(strings, season.availability),
              ]) {
                [] => null,
                final facts => Text(facts.join(' · ')),
              },
            ),
        ];
    }
  }
}
