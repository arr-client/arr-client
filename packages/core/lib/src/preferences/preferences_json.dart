/// The JSON of the preference columns. Reading ignores unknown fields and
/// values, and uses the default for what is missing.
library;

import 'dart:convert';

import '../models/add_choices.dart';
import '../models/item_state.dart';
import '../models/minimum_availability.dart';
import '../models/series_type.dart';
import 'instance_option_id.dart';
import 'library_filters.dart';
import 'library_sort.dart';

/// The `sort` column.
String encodeSort(LibrarySort sort) => jsonEncode(sortToJson(sort));

/// [sort] as a JSON object.
Map<String, Object?> sortToJson(LibrarySort sort) => {
  'field': sort.field,
  'ascending': sort.ascending,
};

/// Reads the `sort` column.
LibrarySort decodeSort(String text) => sortFromJson(_object(text));

/// Reads what [sortToJson] writes.
LibrarySort sortFromJson(Map<String, Object?> json) => LibrarySort(
  field: switch (json['field']) {
    final String field => field,
    _ => LibrarySort.title,
  },
  ascending: json['ascending'] != false,
);

/// The `filters` column.
String encodeFilters(LibraryFilters filters) =>
    jsonEncode(filtersToJson(filters));

/// [filters] as a JSON object.
Map<String, Object?> filtersToJson(LibraryFilters filters) {
  List<Object> ids(Set<InstanceOptionId> ids) => [
    for (final id in ids) [id.instanceId, id.optionId],
  ];

  return {
    'text': filters.text,
    'states': [for (final state in filters.states) state.name],
    'monitored': filters.monitored,
    'qualityProfiles': ids(filters.qualityProfiles),
    'tags': ids(filters.tags),
  };
}

/// Reads the `filters` column.
LibraryFilters decodeFilters(String text) => filtersFromJson(_object(text));

/// Reads what [filtersToJson] writes.
LibraryFilters filtersFromJson(Map<String, Object?> json) {
  final states = ItemState.values.asNameMap();

  Set<InstanceOptionId> ids(Object? list) => {
    for (final entry in _list(list))
      if (entry case [final String instanceId, final int optionId])
        InstanceOptionId(instanceId, optionId),
  };

  return LibraryFilters(
    text: switch (json['text']) {
      final String text => text,
      _ => '',
    },
    states: {for (final name in _list(json['states'])) ?states[name]},
    monitored: _boolOrNull(json['monitored']),
    qualityProfiles: ids(json['qualityProfiles']),
    tags: ids(json['tags']),
  );
}

/// The `choices` column.
String encodeAddChoices(AddChoices choices) =>
    jsonEncode(addChoicesToJson(choices));

/// [choices] as a JSON object.
Map<String, Object?> addChoicesToJson(AddChoices choices) => {
  'rootFolderId': choices.rootFolderId,
  'qualityProfileId': choices.qualityProfileId,
  'monitorOptionId': choices.monitorOptionId,
  'searchNow': choices.searchNow,
  'metadataProfileId': choices.metadataProfileId,
  'tagIds': choices.tagIds.toList(),
  'seriesType': choices.seriesType?.name,
  'seasonFolder': choices.seasonFolder,
  'minimumAvailability': choices.minimumAvailability?.name,
};

/// Reads the `choices` column. Null if a required choice is missing.
AddChoices? decodeAddChoices(String text) => addChoicesFromJson(_object(text));

/// Reads what [addChoicesToJson] writes. Null if a required choice is missing.
AddChoices? addChoicesFromJson(Map<String, Object?> json) {
  if (json case {
    'rootFolderId': final int rootFolderId,
    'qualityProfileId': final int qualityProfileId,
    'monitorOptionId': final String monitorOptionId,
    'searchNow': final bool searchNow,
  }) {
    return AddChoices(
      rootFolderId: rootFolderId,
      qualityProfileId: qualityProfileId,
      monitorOptionId: monitorOptionId,
      searchNow: searchNow,
      metadataProfileId: switch (json['metadataProfileId']) {
        final int id => id,
        _ => null,
      },
      tagIds: _list(json['tagIds']).whereType<int>().toSet(),
      seriesType: switch (json['seriesType']) {
        final String name =>
          SeriesType.values.asNameMap()[name] ?? SeriesType.unknown,
        _ => null,
      },
      seasonFolder: _boolOrNull(json['seasonFolder']),
      minimumAvailability: switch (json['minimumAvailability']) {
        final String name =>
          MinimumAvailability.values.asNameMap()[name] ??
              MinimumAvailability.unknown,
        _ => null,
      },
    );
  }
  return null;
}

Map<String, Object?> _object(String text) =>
    switch (jsonDecode(text) as Object?) {
      final Map<String, Object?> object => object,
      _ => const {},
    };

List<Object?> _list(Object? value) => value is List<Object?> ? value : const [];

bool? _boolOrNull(Object? value) => value is bool ? value : null;
