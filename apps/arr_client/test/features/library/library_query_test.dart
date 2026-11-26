/// Ordering and filtering the library (spec story 2, scenario 2).
library;

import 'package:arr_client/features/library/library_entry.dart';
import 'package:arr_client/features/library/library_query.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryEntry entry(
  String title, {
  String instance = 'a',
  int id = 1,
  String? sortTitle,
  int? year,
  DateTime? added,
  int size = 0,
  ItemState state = ItemState.missing,
  bool monitored = true,
  int? profile,
  Set<int> tags = const {},
}) => LibraryEntry(
  Movie(
    ref: ItemRef(instanceId: instance, kind: MediaKind.movie, remoteId: id),
    title: title,
    sortTitle: sortTitle ?? title,
    monitored: monitored,
    state: state,
    year: year,
    addedAt: added,
    sizeOnDisk: size,
    qualityProfileId: profile,
    tagIds: tags,
  ),
);

List<String> titles(List<LibraryEntry> entries) => [
  for (final entry in entries) entry.item.title,
];

void main() {
  group('sorting', () {
    final entries = [
      entry(
        'The Cat',
        sortTitle: 'cat',
        year: 2001,
        added: DateTime.utc(2024),
        size: 5,
      ),
      entry('apple', year: 1999, added: DateTime.utc(2026), size: 0),
      entry('Bee', added: DateTime.utc(2025), size: 9),
      entry('Dog', year: 2010, size: 2),
    ];
    List<String> by(String field, {bool ascending = true}) => titles(
      sortEntries(entries, LibrarySort(field: field, ascending: ascending)),
    );

    test('by title uses the sort title and ignores case', () {
      expect(by('title'), ['apple', 'Bee', 'The Cat', 'Dog']);
      expect(by('title', ascending: false), ['Dog', 'The Cat', 'Bee', 'apple']);
    });

    test('by a value leaves those without it last in both directions', () {
      expect(by('year'), ['apple', 'The Cat', 'Dog', 'Bee']);
      expect(by('year', ascending: false), ['Dog', 'The Cat', 'apple', 'Bee']);
      expect(by('added'), ['The Cat', 'Bee', 'apple', 'Dog']);
      expect(by('added', ascending: false), ['apple', 'Bee', 'The Cat', 'Dog']);
      expect(by('size', ascending: false), ['Bee', 'The Cat', 'Dog', 'apple']);
    });

    test('a field this version does not know is the title', () {
      expect(by('popularity'), by('title'));
    });

    test('the same title keeps the order of the instances', () {
      final twice = [
        for (final instance in ['b', 'a', 'c'])
          entry('Same', instance: instance),
      ];
      for (final ascending in [true, false]) {
        expect(
          [
            for (final sorted in sortEntries(
              twice,
              LibrarySort(ascending: ascending),
            ))
              sorted.instanceId,
          ],
          ['b', 'a', 'c'],
        );
      }
    });
  });

  group('filtering', () {
    final entries = [
      entry('Alien', state: ItemState.downloaded, profile: 1, tags: {1}),
      entry(
        'Aliens',
        instance: 'b',
        state: ItemState.missing,
        monitored: false,
        profile: 1,
        tags: {2},
      ),
      entry('Heat', state: ItemState.unreleased, profile: 2, tags: {1, 2}),
    ];
    List<String> with_(
      LibraryFilters filters, [
      Set<String> shown = const {'a', 'b'},
    ]) => titles(filterEntries(entries, filters, shown));

    test('without filters everything passes', () {
      expect(with_(const LibraryFilters()), ['Alien', 'Aliens', 'Heat']);
    });

    test('by text anywhere in the title, whatever the case', () {
      expect(with_(const LibraryFilters(text: ' LIEN ')), ['Alien', 'Aliens']);
    });

    test('by any of the chosen states', () {
      expect(
        with_(
          const LibraryFilters(
            states: {ItemState.downloaded, ItemState.unreleased},
          ),
        ),
        ['Alien', 'Heat'],
      );
    });

    test('by monitoring', () {
      expect(with_(const LibraryFilters(monitored: false)), ['Aliens']);
      expect(with_(const LibraryFilters(monitored: true)), ['Alien', 'Heat']);
    });

    test('a quality profile belongs to its instance', () {
      expect(
        with_(LibraryFilters(qualityProfiles: {InstanceOptionId('a', 1)})),
        ['Alien'],
      );
    });

    test('by any of the chosen tags, which belong to their instance', () {
      expect(with_(LibraryFilters(tags: {InstanceOptionId('a', 2)})), ['Heat']);
      expect(
        with_(
          LibraryFilters(
            tags: {InstanceOptionId('a', 1), InstanceOptionId('b', 2)},
          ),
        ),
        ['Alien', 'Aliens', 'Heat'],
      );
    });

    test('different filters all have to hold', () {
      expect(
        with_(
          LibraryFilters(
            text: 'a',
            monitored: true,
            tags: {InstanceOptionId('a', 2)},
          ),
        ),
        ['Heat'],
      );
    });

    test('ids of an instance that is not shown are not applied', () {
      expect(
        with_(LibraryFilters(qualityProfiles: {InstanceOptionId('gone', 1)})),
        ['Alien', 'Aliens', 'Heat'],
      );
    });
  });
}
