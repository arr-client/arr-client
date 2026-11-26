import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every combination of [count] facts.
Iterable<List<bool>> _combinations(int count) sync* {
  for (var bits = 0; bits < 1 << count; bits++) {
    yield [for (var i = 0; i < count; i++) bits & (1 << i) != 0];
  }
}

void main() {
  test('states are declared in order of precedence', () {
    expect(ItemState.values, [
      ItemState.downloading,
      ItemState.downloaded,
      ItemState.partial,
      ItemState.unmonitored,
      ItemState.unreleased,
      ItemState.missing,
    ]);
  });

  group('an item with its own file', () {
    ItemState movie({
      required bool hasFile,
      required bool monitored,
      bool released = true,
    }) => ItemState.resolve(
      downloading: false,
      allWantedPresent: hasFile,
      anyPresent: hasFile,
      monitored: monitored,
      released: released,
    );

    test('is downloaded with its file, monitored or not', () {
      for (final monitored in [true, false]) {
        expect(
          movie(hasFile: true, monitored: monitored),
          ItemState.downloaded,
        );
      }
    });

    test('without its file depends on its flag and release', () {
      expect(movie(hasFile: false, monitored: false), ItemState.unmonitored);
      expect(
        movie(hasFile: false, monitored: true, released: false),
        ItemState.unreleased,
      );
      expect(movie(hasFile: false, monitored: true), ItemState.missing);
    });
  });

  group('a container', () {
    // [wanted] is the server's count; [files] is how many of those have one.
    ItemState series({
      required int wanted,
      required int files,
      bool monitored = true,
    }) => ItemState.resolve(
      downloading: false,
      allWantedPresent: wanted > 0 && files == wanted,
      anyPresent: files > 0,
      monitored: monitored,
      released: wanted > 0,
    );

    test('is judged by what the server counts, whatever its flag', () {
      for (final monitored in [true, false]) {
        expect(
          series(wanted: 3, files: 3, monitored: monitored),
          ItemState.downloaded,
        );
        expect(
          series(wanted: 10, files: 3, monitored: monitored),
          ItemState.partial,
        );
      }
    });

    test('with wanted parts and no files depends on its flag', () {
      expect(series(wanted: 10, files: 0), ItemState.missing);
      expect(
        series(wanted: 10, files: 0, monitored: false),
        ItemState.unmonitored,
      );
    });

    test('that wants nothing is unreleased, or unmonitored', () {
      expect(series(wanted: 0, files: 0), ItemState.unreleased);
      expect(
        series(wanted: 0, files: 0, monitored: false),
        ItemState.unmonitored,
      );
    });
  });

  test('the highest state that applies wins, whatever else is true', () {
    for (final facts in _combinations(5)) {
      final [downloading, allWanted, any, monitored, released] = facts;
      final applying = {
        if (downloading) ItemState.downloading,
        if (allWanted) ItemState.downloaded,
        if (any) ItemState.partial,
        if (!monitored) ItemState.unmonitored,
        if (!released) ItemState.unreleased,
        ItemState.missing,
      };

      expect(
        ItemState.resolve(
          downloading: downloading,
          allWantedPresent: allWanted,
          anyPresent: any,
          monitored: monitored,
          released: released,
        ),
        ItemState.values.firstWhere(applying.contains),
        reason: '$facts',
      );
    }
  });
}
