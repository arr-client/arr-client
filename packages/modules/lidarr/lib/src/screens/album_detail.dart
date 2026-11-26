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
import 'lidarr_actions_controller.dart';
import 'lidarr_controllers.dart';
import 'lidarr_sources.dart';

/// An album, its tracks and their files, and what happened to it.
class AlbumScreen extends ConsumerWidget {
  /// Creates an [AlbumScreen] of the album [albumId].
  const AlbumScreen({required this.sources, required this.albumId, super.key});

  /// The instance's.
  final LidarrSources sources;

  /// The album.
  final int albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = sources.album(albumId);
    final key = (sources, item);
    final state = ref.watch(albumProvider(key));
    final tracks = ref.watch(tracksProvider(key));
    // The tracks and their files come from a read of their own: where that is
    // out of date, the screen says so, with why.
    final shown = switch ((state, tracks)) {
      (
        ViewData(:final value, staleness: final own),
        ViewData(staleness: final ofTracks?),
      )
          when own == null || own.failure == null && ofTracks.failure != null =>
        ViewData(value, staleness: ofTracks),
      _ => state,
    };

    Future<void> refresh() async {
      ref.invalidate(historyProvider(key));
      await Future.wait([
        ref.read(albumProvider(key).notifier).refresh(),
        ref.read(tracksProvider(key).notifier).refresh(),
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
        // Not for an album that is not there.
        menu: switch (shown) {
          ViewData(:final staleness) when staleness?.failure is! NotFound =>
            LidarrMenu(
              sources: sources,
              item: item,
              isStale: staleness != null,
            ),
          _ => null,
        },
        body: StateScaffold<Album>(
          state: shown,
          itemId: item,
          onRetry: () => unawaited(refresh()),
          builder: (context, album, {required isStale}) => _AlbumBody(
            sources: sources,
            album: album,
            tracks: tracks,
            isStale: isStale,
            onRetry: () => unawaited(refresh()),
          ),
        ),
      ),
    );
  }
}

class _AlbumBody extends ConsumerWidget {
  const _AlbumBody({
    required this.sources,
    required this.album,
    required this.tracks,
    required this.isStale,
    required this.onRetry,
  });

  final LidarrSources sources;
  final Album album;
  final ViewState<List<Track>> tracks;
  final bool isStale;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = LidarrLocalizations.of(context);
    final key = (sources, album.ref);
    final history = ref.watch(historyProvider(key));
    final artist = album.parent;
    final overview = album.overview;
    final target = MediaTarget(album.ref);
    final deleting = ref.watch(
      lidarrActionsProvider((sources, target))
          .select((state) => state.deletingFile),
    );
    // The screen's own context, which outlives the rows of the list.
    final screen = context;

    return DetailScroll(
      slivers: [
        SliverList.list(
          children: [
            const SizedBox(height: 16),
            if (artist != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(album.parentTitle ?? strings.openArtist),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    unawaited(context.push<void>(itemRoute(artist).location)),
              ),
            _Header(sources: sources, album: album),
            const SizedBox(height: 16),
            LidarrActions(
              sources: sources,
              target: target,
              monitored: album.monitored,
              isStale: isStale,
            ),
            DetailSlot(
              DetailSlotName.downloadProgress,
              item: album.ref,
              parent: artist,
            ),
            if (overview != null && overview.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(overview),
            ],
          ],
        ),
        ..._tracks(
          context,
          strings,
          // Only a file the instance has just listed can be deleted.
          onDelete: isStale || deleting
              ? null
              : (track, file) => unawaited(
                  deleteTrackFile(screen, ref, sources, track, file),
                ),
        ),
        SliverToBoxAdapter(
          child: HistorySection(
            history: history.value,
            isLoading: history.isLoading,
            onRetry: () => ref.invalidate(historyProvider(key)),
            onShowAll: () =>
                unawaited(sources.navigator.openHistory(album.ref)),
          ),
        ),
      ],
    );
  }

  /// The tracks in their order, under a heading for each disc where there are
  /// several.
  List<Widget> _tracks(
    BuildContext context,
    LidarrLocalizations strings, {
    required void Function(Track track, MediaFile file)? onDelete,
  }) {
    Widget part(List<Widget> children) =>
        SliverList.list(children: [SectionTitle(strings.tracks), ...children]);

    switch (tracks) {
      case ViewLoading():
        return [
          part([LinearProgressIndicator(semanticsLabel: strings.tracks)]),
        ];
      case ViewError(:final failure):
        return [
          part([
            Text(failureMessage(context, failure)),
            TextButton(onPressed: onRetry, child: Text(strings.retryTracks)),
          ]),
        ];
      case ViewData(:final value) when value.isEmpty:
        return [
          part([Text(strings.noTracks)]),
        ];
      case ViewData(:final value):
        final sorted = [...value]
          ..sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
        final discs = <int, List<Track>>{};
        for (final track in sorted) {
          discs.putIfAbsent(track.discNumber, () => []).add(track);
        }
        return [
          SliverToBoxAdapter(child: SectionTitle(strings.tracks)),
          for (final MapEntry(key: disc, value: onDisc) in discs.entries) ...[
            if (discs.length > 1)
              SliverToBoxAdapter(child: SectionTitle(strings.disc(disc))),
            _rows(onDisc, onDelete),
          ],
        ];
    }
  }

  // Built as it scrolls into view: a compilation may hold hundreds.
  Widget _rows(
    List<Track> tracks,
    void Function(Track track, MediaFile file)? onDelete,
  ) => SliverList.builder(
    itemCount: tracks.length,
    itemBuilder: (context, index) =>
        _TrackRow(track: tracks[index], onDelete: onDelete),
  );
}

/// The cover, title and where the album stands. Monitoring is shown by its
/// switch.
class _Header extends StatelessWidget {
  const _Header({required this.sources, required this.album});

  final LidarrSources sources;
  final Album album;

  @override
  Widget build(BuildContext context) {
    final strings = LidarrLocalizations.of(context);
    final theme = Theme.of(context);
    final facts = [
      if (album.albumType case final type?) albumTypeLabel(strings, type),
      // A day of the calendar, which no time zone may move.
      if (album.releaseDate case final date?)
        formatDay(context, DateTime(date.year, date.month, date.day)),
    ];
    return CoverBeside(
      cover: Artwork(
        images: album.images,
        types: const [MediaImageType.cover],
        loader: sources.artwork,
        width: coverWidth,
        aspectRatio: 1,
        placeholder: Icons.album_outlined,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(album.title, style: theme.textTheme.headlineSmall),
          ),
          if (facts.isNotEmpty) Text(facts.join(strings.separator)),
          const SizedBox(height: 8),
          ItemStateLine(album.state),
          if (album.sizeOnDisk > 0) ...[
            const SizedBox(height: 4),
            Text(strings.sizeOnDisk(formatBytes(context, album.sizeOnDisk))),
          ],
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.onDelete});

  final Track track;

  /// Null while files cannot be deleted.
  final void Function(Track track, MediaFile file)? onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = LidarrLocalizations.of(context);
    final file = track.file;
    final delete = onDelete;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(numberedTrack(strings, track)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (track.duration case final duration?)
            Text(trackLength(strings, duration)),
          ItemStateLine(track.state),
          if (file != null) ...[
            Text(
              [
                ?file.quality?.name,
                ?file.audio,
                if (file.size > 0) formatBytes(context, file.size),
              ].join(strings.separator),
            ),
            Text(file.path),
          ],
        ],
      ),
      trailing: file == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Theme.of(context).colorScheme.error,
              tooltip: strings.deleteFileOf(trackTitle(strings, track)),
              onPressed: delete == null ? null : () => delete(track, file),
            ),
    );
  }
}
