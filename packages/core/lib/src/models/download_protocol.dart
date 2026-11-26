/// How something is downloaded.
enum DownloadProtocol {
  /// BitTorrent.
  torrent,

  /// Usenet.
  usenet,

  /// A protocol the app does not know.
  unknown,
}
