import 'package:core/core.dart';

import '../json_reading.dart';

/// An entry of `GET qualityprofile`.
ServerOption qualityProfileOption(JsonObject record) => ServerOption(
  kind: ServerOptionKind.qualityProfile,
  id: requireInt(record, 'id'),
  label: requireString(record, 'name'),
);

/// An entry of `GET metadataprofile`.
ServerOption metadataProfileOption(JsonObject record) => ServerOption(
  kind: ServerOptionKind.metadataProfile,
  id: requireInt(record, 'id'),
  label: requireString(record, 'name'),
);

/// An entry of `GET rootfolder`.
ServerOption rootFolderOption(JsonObject record) => ServerOption(
  kind: ServerOptionKind.rootFolder,
  id: requireInt(record, 'id'),
  label: requireString(record, 'path'),
  freeSpace: optionalNumber(record, 'freeSpace')?.toInt(),
);

/// An entry of `GET tag`.
ServerOption tagOption(JsonObject record) => ServerOption(
  kind: ServerOptionKind.tag,
  id: requireInt(record, 'id'),
  label: requireString(record, 'label'),
);
