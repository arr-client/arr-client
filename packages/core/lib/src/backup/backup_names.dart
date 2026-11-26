/// The numbered suffixes of names in use (contracts/backup-format.md).
library;

/// A record to be named: the name the file gives it and, if it replaces one,
/// the name that one has now.
typedef NamedRecord = ({String name, String? current});

/// The names the [records] will be saved with, in their order, none the same,
/// ignoring case, as another or as one of [taken].
///
/// A record that keeps its name has the first claim to it, then one that
/// replaces another, then a new one.
List<String> uniqueNames(List<NamedRecord> records, Iterable<String> taken) {
  final used = {for (final name in taken) name.toLowerCase()};
  // The next number to try for a name, so that a file full of one name does
  // not take quadratic time.
  final next = <String, int>{};

  String claim(String name) {
    final key = name.toLowerCase();
    if (used.add(key)) return name;
    for (var number = next[key] ?? 2; ; number++) {
      final suffix = ' ($number)';
      // A name has at most 40 characters, counted in code points.
      final base = String.fromCharCodes(name.runes.take(40 - suffix.length));
      final candidate = '${base.trimRight()}$suffix';
      if (used.add(candidate.toLowerCase())) {
        next[key] = number + 1;
        return candidate;
      }
    }
  }

  int rank(NamedRecord record) => switch (record.current) {
    null => 2,
    final current when current.toLowerCase() == record.name.toLowerCase() => 0,
    _ => 1,
  };

  final names = List.filled(records.length, '');
  for (var pass = 0; pass <= 2; pass++) {
    for (final (index, record) in records.indexed) {
      if (rank(record) == pass) names[index] = claim(record.name);
    }
  }
  return names;
}
