/// Space on one of the server's disks, in bytes.
final class DiskSpace {
  const DiskSpace({
    required this.path,
    required this.free,
    required this.total,
  });

  final String path;

  final int free;

  final int total;
}
