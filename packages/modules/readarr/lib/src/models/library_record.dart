/// Records of authors, books and editions.
library;

import 'package:core/core.dart';

import 'json_fields.dart';
import 'media_record.dart';

/// The state of an author (data-model.md LibraryItem.state). What it wants is
/// what the server counts in `bookCount`.
ItemState authorState(JsonObject record, {required bool downloading}) {
  final statistics = objectIn(record, 'statistics');
  final wanted = optionalNumber(statistics, 'bookCount') ?? 0;
  final present = optionalNumber(statistics, 'bookFileCount') ?? 0;
  return ItemState.resolve(
    downloading: downloading,
    allWantedPresent: wanted > 0 && present >= wanted,
    anyPresent: present > 0,
    monitored: record['monitored'] == true,
    released: wanted > 0,
  );
}

/// The state of a book at [now], which holds its own files: any of them is the
/// book. Without a release date it is released if the server counts it as
/// wanted.
ItemState bookState(
  JsonObject record, {
  required bool downloading,
  required DateTime now,
}) {
  final statistics = objectIn(record, 'statistics');
  final hasFile = (optionalNumber(statistics, 'bookFileCount') ?? 0) > 0;
  final released = optionalTime(record, 'releaseDate');
  return ItemState.resolve(
    downloading: downloading,
    allWantedPresent: hasFile,
    anyPresent: hasFile,
    monitored: record['monitored'] == true,
    released: released == null
        ? (optionalNumber(statistics, 'bookCount') ?? 0) > 0
        : !released.isAfter(now),
  );
}

/// The name of the author a record of a book embeds.
String? embeddedAuthorName(JsonObject book) =>
    optionalText(objectIn(book, 'author'), 'authorName');

/// A record of `GET author`.
Author readAuthor(JsonObject record, ItemRef ref, ItemState state) {
  final title = requireText(record, 'authorName');
  return Author(
    ref: ref,
    title: title,
    sortTitle: optionalText(record, 'sortName') ?? title.toLowerCase(),
    monitored: record['monitored'] == true,
    state: state,
    overview: optionalText(record, 'overview'),
    images: readImages(record['images']),
    qualityProfileId: optionalPositive(record, 'qualityProfileId'),
    metadataProfileId: optionalPositive(record, 'metadataProfileId'),
    tagIds: {
      if (record['tags'] case final List<Object?> tags)
        ...tags.whereType<int>(),
    },
    path: optionalText(record, 'path'),
    sizeOnDisk: _sizeOnDisk(record),
    addedAt: optionalTime(record, 'added'),
  );
}

/// A record of `GET book`, which has editions only where they were put in it.
/// Books have no sort title of their own.
Book readBook(
  JsonObject record, {
  required ItemRef ref,
  required ItemRef author,
  required String? authorName,
  required ItemState state,
}) {
  final title = requireText(record, 'title');
  return Book(
    ref: ref,
    title: title,
    sortTitle: title.toLowerCase(),
    monitored: record['monitored'] == true,
    state: state,
    year: optionalTime(record, 'releaseDate')?.year,
    overview: optionalText(record, 'overview'),
    images: readImages(record['images']),
    sizeOnDisk: _sizeOnDisk(record),
    addedAt: optionalTime(record, 'added'),
    parent: author,
    parentTitle: authorName,
    seriesTitle: optionalText(record, 'seriesTitle'),
    editions: [
      if (record['editions'] case final List<Object?> editions)
        for (final edition in editions.whereType<JsonObject>())
          _edition(edition),
    ],
  );
}

/// A record of `GET edition`.
Edition _edition(JsonObject record) => Edition(
  title: optionalText(record, 'title') ?? '',
  monitored: record['monitored'] == true,
  format: optionalText(record, 'format'),
  isbn: optionalText(record, 'isbn13'),
  pageCount: optionalPositive(record, 'pageCount'),
  releaseDate: optionalTime(record, 'releaseDate'),
);

int _sizeOnDisk(JsonObject record) =>
    optionalNumber(objectIn(record, 'statistics'), 'sizeOnDisk')?.toInt() ?? 0;
