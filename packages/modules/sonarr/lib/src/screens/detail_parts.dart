/// What the module's screens are made of.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/sonarr_localizations.dart';
import 'labels.dart';

/// The frame of a screen: its title, and a refresh by button or pull.
class DetailPage extends StatelessWidget {
  /// Creates a [DetailPage].
  const DetailPage({
    required this.title,
    required this.onRefresh,
    required this.body,
    super.key,
  });

  /// The app bar's title.
  final String title;

  /// Reads from the server again.
  final Future<void> Function() onRefresh;

  /// A `StateScaffold`.
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        // Pulling down does this too, which a screen reader cannot.
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: SonarrLocalizations.of(context).refresh,
          onPressed: () => unawaited(onRefresh()),
        ),
      ],
    ),
    body: RefreshIndicator(onRefresh: onRefresh, child: body),
  );
}

/// A scroll view of [slivers] with the screen's margin.
class DetailScroll extends StatelessWidget {
  /// Creates a [DetailScroll].
  const DetailScroll({required this.slivers, super.key});

  /// What it holds.
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final margin = screenMargin(constraints.maxWidth);
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final sliver in slivers)
            SliverSafeArea(
              top: false,
              bottom: false,
              sliver: SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                sliver: sliver,
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: margin + MediaQuery.paddingOf(context).bottom,
            ),
          ),
        ],
      );
    },
  );
}

/// The heading of a part of a screen.
class SectionTitle extends StatelessWidget {
  /// Creates a [SectionTitle].
  const SectionTitle(this.text, {super.key});

  /// The heading.
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// An item's state, as an icon and a word.
class StateLine extends StatelessWidget {
  /// Creates a [StateLine].
  const StateLine(this.state, {super.key});

  /// The state.
  final ItemState state;

  @override
  Widget build(BuildContext context) => IconLine(
    icon: state.icon,
    color: state.color(Theme.of(context).colorScheme),
    text: state.label(SonarrLocalizations.of(context)),
  );
}

/// Whether the server monitors an item. Shown only; it is not changed here.
class MonitoredLine extends StatelessWidget {
  /// Creates a [MonitoredLine].
  const MonitoredLine({required this.monitored, super.key});

  /// Whether it does.
  final bool monitored;

  @override
  Widget build(BuildContext context) {
    final strings = SonarrLocalizations.of(context);
    return IconLine(
      icon: monitored ? Icons.bookmark : Icons.bookmark_border,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      text: monitored ? strings.monitored : strings.notMonitored,
    );
  }
}

/// A short text with an icon before it.
class IconLine extends StatelessWidget {
  /// Creates an [IconLine].
  const IconLine({
    required this.icon,
    required this.color,
    required this.text,
    super.key,
  });

  /// Decorative to screen readers: [text] says the same.
  final IconData icon;

  /// The icon's colour.
  final Color color;

  /// The words.
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: MediaQuery.textScalerOf(context).scale(16),
        color: color,
      ),
      const SizedBox(width: 4),
      Flexible(child: Text(text)),
    ],
  );
}

/// Named values, one under the other. The caller leaves out missing ones.
class FactList extends StatelessWidget {
  /// Creates a [FactList].
  const FactList(this.facts, {super.key});

  /// Each name and its value.
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (name, value) in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(value),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A picture of the first of [types] that [images] has, decoded at about the
/// size it is shown. [placeholder] stands for one that is missing or does not
/// load; without it a missing picture takes no space.
class Artwork extends StatelessWidget {
  /// Creates an [Artwork].
  const Artwork({
    required this.images,
    required this.types,
    required this.loader,
    required this.width,
    required this.aspectRatio,
    this.placeholder,
    super.key,
  });

  /// The item's artwork.
  final List<MediaImage> images;

  /// What may be shown, best first.
  final List<MediaImageType> types;

  /// Loads the instance's artwork.
  final ArtworkLoader loader;

  /// How wide it is shown, in logical pixels.
  final double width;

  /// Width over height.
  final double aspectRatio;

  /// The icon of the placeholder.
  final IconData? placeholder;

  @override
  Widget build(BuildContext context) {
    final picture = [
      for (final type in types) ...images.where((image) => image.type == type),
    ].firstOrNull;
    final source = picture == null ? null : loader.image(picture);
    final icon = placeholder;
    if (source == null && icon == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final fallback = icon == null
        ? const SizedBox.shrink()
        : ColoredBox(
            color: colors.surfaceContainerHighest,
            child: Center(child: Icon(icon, color: colors.onSurfaceVariant)),
          );
    Widget child = fallback;
    if (source != null) {
      final image = ResizeImage(
        source,
        width: (width * MediaQuery.devicePixelRatioOf(context)).ceil(),
        policy: ResizeImagePolicy.fit,
      );
      child = Image(
        image: image,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            frame == null && !wasSynchronouslyLoaded ? fallback : child,
        errorBuilder: (context, error, stackTrace) {
          // So that it is tried again when next shown.
          unawaited(image.evict());
          return fallback;
        },
      );
    }
    return SizedBox(
      width: width,
      height: width / aspectRatio,
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
    );
  }
}

/// How many events a screen shows before the rest are asked for.
const _shownEvents = 5;

/// The newest events of an item, with a way to all of them.
class HistorySection extends StatelessWidget {
  /// Creates a [HistorySection].
  const HistorySection({
    required this.history,
    required this.isLoading,
    required this.onRetry,
    required this.onShowAll,
    this.episodeOf,
    super.key,
  });

  /// Null before the first answer.
  final Result<ResultPage<HistoryEvent>, ServiceFailure>? history;

  /// Whether the server is being asked.
  final bool isLoading;

  /// Asks again.
  final VoidCallback onRetry;

  /// Opens the whole history.
  final VoidCallback onShowAll;

  /// Where the episode an event is about stands, on a series' screen.
  final String? Function(ItemRef ref)? episodeOf;

  @override
  Widget build(BuildContext context) {
    final strings = SonarrLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(strings.history),
        ...switch (history) {
          Ok(:final value) when value.items.isEmpty => [
            Text(strings.noHistory),
          ],
          Ok(:final value) => [
            for (final event in value.items.take(_shownEvents))
              _event(context, strings, event),
            if (value.items.length > _shownEvents || value.hasMore)
              TextButton(
                onPressed: onShowAll,
                child: Text(strings.showAllHistory),
              ),
          ],
          Err(:final error) when !isLoading => [
            Text(strings.historyFailed),
            Text(failureMessage(context, error)),
            TextButton(onPressed: onRetry, child: Text(strings.retryHistory)),
          ],
          _ => [LinearProgressIndicator(semanticsLabel: strings.history)],
        },
      ],
    );
  }

  Widget _event(
    BuildContext context,
    SonarrLocalizations strings,
    HistoryEvent event,
  ) {
    final look = eventLook(strings, event.eventType);
    final item = event.itemRef;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(look.icon),
      title: Text(
        [
          look.label,
          if (item != null) ?episodeOf?.call(item),
        ].join(strings.separator),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.sourceTitle.isNotEmpty) Text(event.sourceTitle),
          Text(
            strings.dateAndTime(
              formatDay(context, event.date),
              formatTime(context, event.date),
            ),
          ),
        ],
      ),
    );
  }
}
