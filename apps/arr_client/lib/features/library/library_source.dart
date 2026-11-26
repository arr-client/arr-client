import 'package:core/core.dart';

import 'library_entry.dart';

/// What one instance has given of its library, as far as it is in.
final class LibrarySource {
  const LibrarySource({
    required this.active,
    this.entries,
    this.fetchedAt,
    this.isLoading = false,
    this.failure,
    this.options,
    this.optionsFailed = false,
  });

  /// The instance.
  final ActiveInstance active;

  /// Its items; null while none are known, from the cache or the server.
  final List<LibraryEntry>? entries;

  /// When [entries] were fetched, while they are saved data; null once the
  /// server has just supplied them.
  final DateTime? fetchedAt;

  /// Whether the server is being asked.
  final bool isLoading;

  /// Why the last load failed.
  final ServiceFailure? failure;

  /// Its quality profiles, root folders and tags, as saved or as the server
  /// gave them; null while not known.
  final List<ServerOption>? options;

  /// Whether the last read of [options] failed.
  final bool optionsFailed;

  String get id => active.instance.id;

  String get name => active.instance.name;

  LibrarySource copyWith({
    ActiveInstance? active,
    List<LibraryEntry>? entries,
    DateTime? Function()? fetchedAt,
    bool? isLoading,
    ServiceFailure? Function()? failure,
    List<ServerOption>? options,
    bool? optionsFailed,
  }) => LibrarySource(
    active: active ?? this.active,
    entries: entries ?? this.entries,
    fetchedAt: fetchedAt == null ? this.fetchedAt : fetchedAt(),
    isLoading: isLoading ?? this.isLoading,
    failure: failure == null ? this.failure : failure(),
    options: options ?? this.options,
    optionsFailed: optionsFailed ?? this.optionsFailed,
  );
}
