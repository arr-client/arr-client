/// A library whose answers a test sets.
library;

import 'dart:async';

import 'package:core/core.dart';

class FakeLibrary implements LibraryProvider {
  FakeLibrary({
    this.itemKind = MediaKind.movie,
    this.items = const [],
    this.cached,
    this.serverOptions = const [],
  });

  @override
  final MediaKind itemKind;

  /// What the server has.
  List<LibraryItem> items;

  /// What was cached before; null if never fetched.
  Cached<List<LibraryItem>>? cached;

  List<ServerOption> serverOptions;

  /// Why [list] fails; null while it succeeds.
  ServiceFailure? failure;

  /// Why [options] fails.
  ServiceFailure? optionsFailure;

  /// While set, [list] waits for it.
  Completer<void>? gate;

  /// Where an item's screen is; without one the module has none yet.
  ModuleRoute Function(ItemRef ref)? route;

  var listed = 0;

  @override
  ServiceResult<List<LibraryItem>> list() async {
    listed++;
    await gate?.future;
    final failure = this.failure;
    return failure == null ? Ok(items) : Err(failure);
  }

  @override
  ServiceResult<Cached<List<LibraryItem>>?> cachedList() async => Ok(cached);

  @override
  ServiceResult<List<ServerOption>> options() async {
    final failure = optionsFailure;
    return failure == null ? Ok(serverOptions) : Err(failure);
  }

  @override
  ModuleRoute detailRoute(ItemRef ref) =>
      route?.call(ref) ?? (throw UnimplementedError());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
