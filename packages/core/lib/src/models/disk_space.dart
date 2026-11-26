/// Space on one of the server's disks, in bytes.
final class DiskSpace {
  /// Creates a [DiskSpace].
  const DiskSpace({
    required this.path,
    required this.free,
    required this.total,
  });

  /// The disk or folder.
  final String path;

  /// Free bytes.
  final int free;

  /// Size in bytes.
  final int total;
}
