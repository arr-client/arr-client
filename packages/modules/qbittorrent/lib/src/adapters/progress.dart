/// The torrent list as [DownloadProgress] records (data-model.md).
library;

import 'dart:convert';

import 'package:core/core.dart';

import '../api/qbittorrent_api.dart';

// What qBittorrent reports where it has no estimate: 100 days.
const _noEstimate = 8640000;

/// Reads every torrent; matching them is the core's work.
final class QbittorrentProgressAdapter implements DownloadProgressProvider {
  QbittorrentProgressAdapter(InstanceContext context)
    : _api = QbittorrentApi(context),
      _instanceId = context.instance.id;

  final QbittorrentApi _api;
  final String _instanceId;

  @override
  ServiceResult<List<DownloadProgress>> progress() async =>
      switch (await _api.torrents()) {
        Ok(:final value) => _parse(value),
        Err(:final error) => Err(error),
      };

  Result<List<DownloadProgress>, ServiceFailure> _parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return const Err(MalformedResponse());
    }
    if (json is! List<Object?>) return const Err(MalformedResponse());

    final torrents = <DownloadProgress>[];
    for (final entry in json) {
      final torrent = _torrent(entry);
      if (torrent == null) return const Err(MalformedResponse());
      torrents.add(torrent);
    }
    return Ok(torrents);
  }

  /// Null if [entry] is not a torrent.
  DownloadProgress? _torrent(Object? entry) {
    if (entry case {'hash': final String hash, 'progress': final num progress}
        when hash.isNotEmpty) {
      final v1 = entry['infohash_v1'];
      final speed = entry['dlspeed'];
      final eta = entry['eta'];
      final done = DownloadProgress.progressFrom(progress);
      return DownloadProgress(
        instanceId: _instanceId,
        hash: hash,
        // Empty for a version 2 torrent, and the hash itself for version 1.
        infohashV1:
            v1 is String &&
                v1.isNotEmpty &&
                v1.toLowerCase() != hash.toLowerCase()
            ? v1
            : null,
        progress: done,
        downSpeed: speed is int && speed > 0 ? speed : 0,
        // Once finished, qBittorrent's figure is the time until the seeding
        // limit, not until the download completes.
        eta: done < 1 && eta is int && eta >= 0 && eta < _noEstimate
            ? Duration(seconds: eta)
            : null,
        state: _state(entry['state']),
      );
    }
    return null;
  }
}

// 5.0 renamed the "paused" states to "stopped".
DownloadState _state(Object? state) => switch (state) {
  'downloading' ||
  'forcedDL' ||
  'metaDL' ||
  'forcedMetaDL' => DownloadState.downloading,
  'stalledDL' => DownloadState.stalled,
  'queuedDL' => DownloadState.queued,
  'pausedDL' || 'stoppedDL' => DownloadState.paused,
  // The download is complete, whether or not it may upload.
  'queuedUP' || 'pausedUP' || 'stoppedUP' => DownloadState.completed,
  'uploading' || 'forcedUP' || 'stalledUP' => DownloadState.seeding,
  'checkingDL' ||
  'checkingUP' ||
  'checkingResumeData' => DownloadState.checking,
  'allocating' || 'moving' => DownloadState.processing,
  'error' || 'missingFiles' => DownloadState.error,
  _ => DownloadState.unknown,
};
