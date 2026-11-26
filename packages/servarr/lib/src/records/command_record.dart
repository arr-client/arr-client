import 'package:core/core.dart';

import '../json_reading.dart';

/// The answer of `GET command/{id}`.
Command readCommand(JsonObject record) => Command(
  id: requireInt(record, 'id'),
  name: requireString(record, 'name'),
  status:
      CommandStatus.values.asNameMap()[requireString(record, 'status')] ??
      CommandStatus.unknown,
  result: switch (record['result']) {
    null => null,
    final word =>
      CommandResult.values.asNameMap()[word] ?? CommandResult.unknown,
  },
  message: optionalString(record, 'message'),
);
