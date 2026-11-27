import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/seerr_localizations.dart';
import 'labels.dart';
import 'request_rules.dart';
import 'seerr_source.dart';
import 'title_controller.dart';
import 'title_parts.dart';

/// One title: whether it is there, how its requests stand and, where the user
/// may, the way to request it.
class TitleScreen extends ConsumerWidget {
  /// Creates the screen of the title [wanted].
  const TitleScreen({required this.source, required this.wanted, super.key});

  /// The instance's.
  final SeerrSource source;

  /// The title.
  final DiscoveryRef wanted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (source, wanted);
    final state = ref.watch(titleProvider(key));
    Future<void> refresh() => ref.read(titleProvider(key).notifier).refresh();
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (state) {
          ViewData(:final value) => value.title.title,
          ViewLoading() || ViewError() => '',
        }),
        actions: [
          // Pulling down does this too, which a screen reader cannot.
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: SeerrLocalizations.of(context).refresh,
            onPressed: () => unawaited(refresh()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: StateScaffold<TitlePage>(
            state: state,
            itemId: wanted,
            onRetry: () => unawaited(refresh()),
            builder: (context, page, {required isStale}) => _Title(
              source: source,
              page: page,
              isStale: isStale,
              onRetry: () => unawaited(refresh()),
            ),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.source,
    required this.page,
    required this.isStale,
    required this.onRetry,
  });

  final SeerrSource source;
  final TitlePage page;
  final bool isStale;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = SeerrLocalizations.of(context);
    final theme = Theme.of(context);
    final title = page.title;
    final user = page.user;
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(screenMargin(constraints.maxWidth)),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TitlePoster(title: title, artwork: source.artwork, width: 112),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(titleFacts(strings, title)),
                  ],
                ),
              ),
            ],
          ),
          if (page.userFailure case final failure?) ...[
            const SizedBox(height: 16),
            Text(strings.permissionsUnread),
            Text(failureMessage(context, failure)),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: onRetry,
                child: Text(UiLocalizations.of(context).retry),
              ),
            ),
          ],
          ..._variant(context, is4k: false),
          if (shows4k(title, user)) ..._variant(context, is4k: true),
        ],
      ),
    );
  }

  List<Widget> _variant(BuildContext context, {required bool is4k}) {
    final strings = SeerrLocalizations.of(context);
    final title = page.title;
    final availability = is4k ? title.availability4k : title.availability;
    final status = is4k ? title.requestStatus4k : title.requestStatus;
    final offered = switch (page.user) {
      final user? => requestBlock(title, user, is4k: is4k) == null,
      null => false,
    };
    final VoidCallback? request = isStale
        ? null
        : () => unawaited(
            context.push<void>(
              source.requests.requestRoute(title, is4k: is4k).location,
            ),
          );
    final label = Text(is4k ? strings.request4k : strings.request);

    return [
      const SizedBox(height: 24),
      Semantics(
        header: true,
        child: Text(
          is4k ? strings.variant4k : strings.variantStandard,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconLine(
        availabilityIcon(availability),
        availabilityLabel(strings, availability),
      ),
      if (requestStatusLabel(strings, status) case final text?)
        IconLine(Icons.assignment_outlined, text),
      if (offered) ...[
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          // One primary action: the standard variant, where there is a choice.
          child: is4k
              ? OutlinedButton(onPressed: request, child: label)
              : FilledButton(onPressed: request, child: label),
        ),
      ],
    ];
  }
}
