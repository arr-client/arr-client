import 'package:core/core.dart';

/// What a manual import record is matched to.
///
/// `item` is the movie, series, artist or author, and null where the server
/// cannot match the file. `episodeIds` is empty but for a series.
typedef ServarrMatch = ({ItemRef? item, List<int> episodeIds});

/// What is a service's own in a manual import.
///
/// `match` reads the match of a record the server sent. `ids` gives the fields
/// that name the match of a candidate in what is sent back.
typedef ServarrImportMapping = ({
  ServarrMatch Function(JsonObject record) match,
  JsonObject Function(ManualImportCandidate candidate) ids,
});
