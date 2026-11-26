import 'package:core/core.dart';

/// `quality.quality` of a queue or history record.
Quality? recordQuality(Object? json) => switch (json) {
  {'quality': {'id': final int id, 'name': final String name}} => Quality(
    id: id,
    name: name,
  ),
  _ => null,
};
