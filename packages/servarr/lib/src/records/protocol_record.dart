import 'package:core/core.dart';

/// `protocol` of a queue or release record. The services for music and books
/// name its class instead.
DownloadProtocol recordProtocol(Object? word) => switch (word) {
  'torrent' || 'TorrentDownloadProtocol' => DownloadProtocol.torrent,
  'usenet' || 'UsenetDownloadProtocol' => DownloadProtocol.usenet,
  _ => DownloadProtocol.unknown,
};
