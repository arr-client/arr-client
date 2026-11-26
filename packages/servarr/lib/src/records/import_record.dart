import 'package:core/core.dart';

import '../json_reading.dart';
import 'quality_record.dart';

/// An import from a download folder, as `eventType` of both history reads
/// takes it.
const importEventNumber = '3';

/// The word the records of such an import carry.
const _importEventWord = 'downloadFolderImported';

/// The imports among [records], of `GET history` or `GET history/since`, newest
/// first and each item once with its latest import. Records the server cannot
/// match to an item are all kept.
///
/// [within] says whether an import of that instant counts at all.
List<ImportedItem> importedItems(
  List<JsonObject> records, {
  required ItemRef? Function(JsonObject record) itemRef,
  required String Function(JsonObject record) title,
  bool Function(DateTime importedAt)? within,
}) {
  final imports = <({int id, ImportedItem item})>[];
  for (final record in records) {
    if (record['eventType'] != _importEventWord) continue;
    final id = requireInt(record, 'id');
    final importedAt = DateTime.parse(requireString(record, 'date')).toUtc();
    if (within != null && !within(importedAt)) continue;
    imports.add((
      id: id,
      item: ImportedItem(
        itemRef: itemRef(record),
        title: title(record),
        importedAt: importedAt,
        quality: recordQuality(record['quality']),
      ),
    ));
  }
  // The servers answer with whole seconds; the id orders imports of one.
  imports.sort((a, b) {
    final byDate = b.item.importedAt.compareTo(a.item.importedAt);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  });
  final seen = <ItemRef>{};
  return [
    for (final (id: _, :item) in imports)
      if (switch (item.itemRef) {
        null => true,
        final ref => seen.add(ref),
      })
        item,
  ];
}
