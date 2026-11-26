/// What a search result is, before it is added (spec story 3).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import '../add_request.dart';
import 'add_controller.dart';
import 'add_sheet.dart';
import 'add_state.dart';
import 'open_item.dart';

/// The title's details, the instances that have it and the way to add it.
class AddScreen extends ConsumerWidget {
  const AddScreen({required this.request, super.key});

  final AddRequest request;

  static const _posterSize = Size(120, 180);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final candidate = request.candidate;
    final scope = ref.watch(scopeProvider);
    // Watched here, so that what the sheet learns lasts as long as the screen.
    final state = ref.watch(addProvider(request));
    // The loader reads the preference when it makes the image: made again when
    // it changes.
    ref.watch(
      preferencesProvider.select((value) => value.loadThirdPartyArtwork),
    );
    final artwork = switch (request.artworkInstanceId) {
      final id? => scope?.instance(id)?.context.artwork,
      null => null,
    };
    final targets = addTargets(scope, candidate.kind);

    // What has the title, as the search found it and as asked since.
    final held = <(ActiveInstance, ItemRef)>[
      for (final active in scope?.instances ?? const <ActiveInstance>[])
        if (switch (state.targets[active.instance.id]) {
              TargetHeld(:final ref) => ref,
              // Asked since, and not there.
              TargetReady() => null,
              _ => heldRef(candidate, active.instance.id),
            }
            case final item?)
          (active, item),
    ];
    final holding = {for (final (active, _) in held) active.instance.id};
    final canTake = targets.any(
      (target) => !holding.contains(target.$1.instance.id),
    );

    final quiet = theme.textTheme.bodyLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: Text(strings.addItem)),
      body: scope == null
          ? Center(
              child: CircularProgressIndicator(
                semanticsLabel: UiLocalizations.of(context).loading,
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: EdgeInsets.all(screenMargin(constraints.maxWidth)),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox.fromSize(
                        size: _posterSize,
                        child: ArtworkPoster(
                          kind: candidate.kind,
                          images: candidate.images,
                          artwork: artwork,
                          width: _posterSize.width,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                candidate.title,
                                style: theme.textTheme.headlineSmall,
                              ),
                            ),
                            if (candidate.parentTitle case final parent?)
                              Text(parent, style: quiet),
                            // A year is a name, not a quantity: no grouping.
                            if (candidate.year case final year?)
                              Text('$year', style: quiet),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (candidate.overview case final overview?) ...[
                    const SizedBox(height: 16),
                    Text(overview, style: theme.textTheme.bodyLarge),
                  ],
                  if (held.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Semantics(
                      header: true,
                      child: Text(
                        strings.addAlreadyIn,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    for (final (active, item) in held)
                      _Holder(
                        name: active.instance.name,
                        location: itemLocation(active, item, candidate.title),
                      ),
                  ],
                  if (targets.isEmpty || !canTake) ...[
                    const SizedBox(height: 24),
                    Text(
                      targets.isEmpty
                          ? strings.addNoService
                          : strings.addNowhereLeft,
                      style: quiet,
                    ),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: !canTake
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(strings.addItem),
                  onPressed: () => unawaited(showAddSheet(context, request)),
                ),
              ),
            ),
    );
  }
}

/// One instance that has the title, with the way to it.
class _Holder extends StatelessWidget {
  const _Holder({required this.name, required this.location});

  final String name;

  /// Null where there is nowhere to go.
  final String? location;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: switch (location) {
          final location? => OutlinedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: Text(strings.addOpenIn(name)),
            onPressed: () => unawaited(context.push<void>(location)),
          ),
          null => Text(name),
        },
      ),
    );
  }
}
