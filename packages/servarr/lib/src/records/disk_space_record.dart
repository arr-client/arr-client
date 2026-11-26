import 'package:core/core.dart';

import '../json_reading.dart';

/// An entry of `GET diskspace`.
DiskSpace diskSpaceEntry(JsonObject record) => DiskSpace(
  path: requireString(record, 'path'),
  free: requireInt(record, 'freeSpace'),
  total: requireInt(record, 'totalSpace'),
);
