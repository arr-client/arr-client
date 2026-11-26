import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../l10n/generated/lidarr_localizations.dart';
import '../lidarr_routes.dart';
import 'detail_parts.dart';
import 'labels.dart';
import 'lidarr_actions.dart';
import 'lidarr_controllers.dart';
import 'lidarr_sources.dart';

/// An artist: who it is, its albums by type, and what happened to it.
class ArtistScreen extends ConsumerWidget {
  /// Creates an [ArtistScreen] of the artist [artistId].
  const ArtistScreen({
    required this.sources,
    required this.artistId,
    super.key,
  });

  /// The instance's.
  final LidarrSources sources;

  /// The artist.
  final int artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = sources.artist(artistId);
    final key = (sources, item);
    final state = ref.watch(artistProvider(key));
    final albums = ref.watch(albumsProvider(key));
    // The albums come from a read of their own: where that is out of date, the
    // screen says so, with why.
    final shown = switch ((state, albums)) {
      (
        ViewData(:final value, staleness: final own),
        ViewData(staleness: final ofAlbums?),
      )
          when own == null || own.failure == null && ofAlbums.failure != null =>
        ViewData(value, staleness: ofAlbums),
      _ => state,
    };
    Future<void> refresh() async {
      ref
        ..invalidate(historyProvider(key))
        ..invalidate(optionsProvider(sources));
      await Future.wait([
        ref.read(artistProvider(key).notifier).refresh(),
        ref.read(albumsProvider(key).notifier).refresh(),
      ]);
    }

    return LidarrActionsScope(
      sources: sources,
      target: MediaTarget(item),
      child: DetailPage(
        title: switch (state) {
          ViewData(:final value) => value.title,
          ViewLoading() || ViewError() => '',
        },
        onRefresh: refresh,
        // Not for an artist that is not there.
        menu: switch (shown) {
          ViewData(:final staleness) when staleness?.failure is! NotFound =>
            LidarrMenu(
              sources: sources,
              item: item,
              isStale: staleness != null,
            ),
          _ => null,
        },
        body: StateScaffold<Artist>(
          state: shown,
          itemId: item,
          onRetry: () => unawaited(refresh()),
          builder: (context, artist, {required isStale}) => _ArtistBody(
            sources: sources,
            artist: artist,
            albums: albums,
            isStale: isStale,
            onRetry: () => unawaited(refresh()),
          ),
        ),
      ),
    );
  }
}

class _ArtistBody extends ConsumerWidget {
  const _ArtistBody({
    required this.sources,
    required this.artist,
    required this.albums,
    required this.isStale,
    required this.onRetry,
  });

  final LidarrSources sources;
  final Artist artist;
  final ViewState<List<Album>> albums;
  final bool isStale;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = LidarrLocalizations.of(context);
    final key = (sources, artist.ref);
    final options =
        ref.watch(optionsProvider(sources)).value ?? const <ServerOption>[];
    final history = ref.watch(historyProvider(key));
    final list = switch (albums) {
      ViewData(:final value) => value,
      ViewLoading() || ViewError() => const <Album>[],
    };
    final titles = {for (final album in list) album.ref: album.title};
    final overview = artist.overview;
    final facts = _facts(strings, options);

    return DetailScroll(
      slivers: [
        SliverList.list(
          children: [
            _Header(sources: sources, artist: artist),
            const SizedBox(height: 16),
            LidarrActions(
              sources: sources,
              target: MediaTarget(artist.ref),
              monitored: artist.monitored,
              isStale: isStale,
            ),
            DetailSlot(DetailSlotName.downloadProgress, item: artist.ref),
            if (overview != null && overview.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(overview),
            ],
            if (facts.isNotEmpty) ...[
              SectionTitle(strings.details),
              FactList(facts),
            ],
          ],
        ),
        ..._albums(context, strings),
        SliverToBoxAdapter(
          child: HistorySection(
            history: history.value,
            isLoading: history.isLoading,
            onRetry: () => ref.invalidate(historyProvider(key)),
            onShowAll: () =>
                unawaited(sources.navigator.openHistory(artist.ref)),
            albumOf: (item) => titles[item],
          ),
        ),
      ],
    );
  }

  /// The albums under a heading for each type, newest first.
  List<Widget> _albums(BuildContext context, LidarrLocalizations strings) {
    Widget part(List<Widget> children) =>
        SliverList.list(children: [SectionTitle(strings.albums), ...children]);

    switch (albums) {
      case ViewLoading():
        return [
          part([LinearProgressIndicator(semanticsLabel: strings.albums)]),
        ];
      case ViewError(:final failure):
        return [
          part([
            Text(failureMessage(context, failure)),
            TextButton(onPressed: onRetry, child: Text(strings.retryAlbums)),
          ]),
        ];
      case ViewData(:final value) when value.isEmpty:
        return [
          part([Text(strings.noAlbums)]),
        ];
      case ViewData(:final value):
        final byType = <String, List<Album>>{};
        for (final album in value) {
          byType.putIfAbsent(albumTypeOf(album), () => []).add(album);
        }
        return [
          for (final type in byType.keys.toList()..sort(compareAlbumTypes)) ...[
            SliverToBoxAdapter(
              child: SectionTitle(albumTypeLabel(strings, type)),
            ),
            _rows(byType[type]!..sort(_newestFirst)),
          ],
        ];
    }
  }

  // Built as it scrolls into view: an artist may have hundreds.
  Widget _rows(List<Album> albums) => SliverList.builder(
    itemCount: albums.length,
    itemBuilder: (context, index) =>
        _AlbumRow(sources: sources, album: albums[index]),
  );

  static int _newestFirst(Album a, Album b) {
    final byDate = switch ((a.releaseDate, b.releaseDate)) {
      (final first?, final second?) => second.compareTo(first),
      (null, null) => 0,
      // Without a date it is usually not released yet.
      (null, _) => -1,
      (_, null) => 1,
    };
    return byDate != 0 ? byDate : a.sortTitle.compareTo(b.sortTitle);
  }

  /// What the server gives; the rest is left out.
  List<(String, String)> _facts(
    LidarrLocalizations strings,
    List<ServerOption> options,
  ) {
    String? option(ServerOptionKind kind, int? id) => options
        .where((option) => option.kind == kind && option.id == id)
        .firstOrNull
        ?.label;
    final quality = option(
      ServerOptionKind.qualityProfile,
      artist.qualityProfileId,
    );
    final metadata = option(
      ServerOptionKind.metadataProfile,
      artist.metadataProfileId,
    );
    final tags = [
      for (final id in artist.tagIds) ?option(ServerOptionKind.tag, id),
    ]..sort();

    return [
      if (quality != null) (strings.qualityProfile, quality),
      if (metadata != null) (strings.metadataProfile, metadata),
      if (tags.isNotEmpty) (strings.tags, tags.join(strings.listSeparator)),
      if (artist.path case final path?) (strings.path, path),
    ];
  }
}

/// The artwork, name and where the artist stands. Monitoring is shown by its
/// switch.
class _Header extends StatelessWidget {
  const _Header({required this.sources, required this.artist});

  final LidarrSources sources;
  final Artist artist;

  @override
  Widget build(BuildContext context) {
    final strings = LidarrLocalizations.of(context);
    final theme = Theme.of(context);
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(artist.title, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 8),
        ItemStateLine(artist.state),
        if (artist.sizeOnDisk > 0) ...[
          const SizedBox(height: 4),
          Text(strings.sizeOnDisk(formatBytes(context, artist.sizeOnDisk))),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Center(
              child: Artwork(
                images: artist.images,
                types: const [MediaImageType.fanart, MediaImageType.banner],
                loader: sources.artwork,
                width: width < 480 ? width : 480,
                aspectRatio: 16 / 9,
              ),
            ),
            const SizedBox(height: 16),
            CoverBeside(
              cover: Artwork(
                images: artist.images,
                types: const [MediaImageType.poster, MediaImageType.cover],
                loader: sources.artwork,
                width: coverWidth,
                aspectRatio: 1,
                placeholder: Icons.person_outline,
              ),
              child: title,
            ),
          ],
        );
      },
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.sources, required this.album});

  final LidarrSources sources;
  final Album album;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Artwork(
      images: album.images,
      types: const [MediaImageType.cover],
      loader: sources.artwork,
      width: 48,
      aspectRatio: 1,
      placeholder: Icons.album_outlined,
    ),
    title: Text(album.title),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A year is a name, not a quantity: no grouping.
        if (album.year case final year?) Text('$year'),
        ItemStateLine(album.state),
        if (!album.monitored && album.state != ItemState.unmonitored)
          const MonitoredLine(monitored: false),
      ],
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => unawaited(context.push<void>(itemRoute(album.ref).location)),
  );
}
