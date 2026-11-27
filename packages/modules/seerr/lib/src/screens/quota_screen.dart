import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/seerr_localizations.dart';
import 'labels.dart';
import 'quota_controller.dart';
import 'seerr_source.dart';

/// What the user may still request.
class QuotaScreen extends ConsumerWidget {
  /// Creates the screen of [source].
  const QuotaScreen({required this.source, super.key});

  /// The instance's.
  final SeerrSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = SeerrLocalizations.of(context);
    final quota = ref.watch(quotaProvider(source));
    Future<void> refresh() => ref.refresh(quotaProvider(source).future);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.quotaTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.refresh,
            onPressed: () => unawaited(refresh()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: StateScaffold<Quota>(
            state: switch (quota.value) {
              null => const ViewLoading(),
              _ when quota.isLoading => const ViewLoading(),
              Ok(:final value) => ViewData(value),
              Err(:final error) => ViewError(error),
            },
            onRetry: () => unawaited(refresh()),
            isEmpty: (quota) => quota.movies == null && quota.series == null,
            emptyMessage: strings.quotaNone,
            builder: (context, quota, {required isStale}) => LayoutBuilder(
              builder: (context, constraints) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(screenMargin(constraints.maxWidth)),
                children: [
                  FactList([
                    if (quota.movies case final usage?)
                      (strings.quotaMovies, quotaLabel(strings, usage)),
                    if (quota.series case final usage?)
                      (strings.quotaSeries, quotaLabel(strings, usage)),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
