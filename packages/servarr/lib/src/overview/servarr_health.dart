import 'package:core/core.dart';

import '../json_reading.dart';
import '../records/disk_space_record.dart';
import '../servarr_client.dart';

/// The health and disk space of a service of the Servarr family.
final class ServarrHealth implements HealthProvider {
  /// The health of one service. [providesDiskSpace] is false for a service
  /// that reports health only, such as Prowlarr.
  ServarrHealth(this._client, {this.providesDiskSpace = true});

  final ServarrClient _client;

  @override
  final bool providesDiskSpace;

  @override
  ServiceResult<List<HealthIssue>> health() => _client.health();

  @override
  ServiceResult<List<DiskSpace>> diskSpace() async => providesDiskSpace
      ? await _client.read(
          'diskspace',
          (json) => asObjects(json).map(diskSpaceEntry).toList(),
        )
      : const Ok([]);
}
