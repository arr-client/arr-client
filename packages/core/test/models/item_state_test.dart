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
