/// How the manage flows call a module: once for each request of the user, and
/// without letting a module that throws hold up the flow.
library;

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/composition.dart';
import '../library_controller.dart';

/// What [read] returns. A module that throws has answered what cannot be
/// understood.
Future<Result<T, ServiceFailure>> readOf<T>(
  AppServices services,
  ServiceResult<T> Function() read,
) => _call(services, read, const MalformedResponse(), 'read');

/// Sends one change of [instance], once.
///
/// Nothing is sent, and it fails with [Unreachable], once the instance has been
/// edited, disabled, removed or switched away from. A module that throws may or
/// may not have sent it, which is [OutcomeUnknown].
Future<Result<T, ServiceFailure>> sendOnce<T>(
  AppServices services,
  ActiveInstance instance,
  ServiceResult<T> Function() send,
) async => instance.isCurrent
    ? await _call(services, send, const OutcomeUnknown(), 'change')
    : const Err(Unreachable());

Future<Result<T, ServiceFailure>> _call<T>(
  AppServices services,
  ServiceResult<T> Function() call,
  ServiceFailure thrown,
  String what,
) async {
  try {
    return await call();
  } catch (error) {
    // The type only: the text of an error may quote an address or a secret.
    services.log.log(LogLevel.error, 'A $what failed (${error.runtimeType})');
    return Err(thrown);
  }
}

/// Has the library of [kind], if it has been shown, ask [instanceId] again, so
/// that it shows what a change has led to.
void reloadLibrary(
  ProviderContainer container,
  MediaKind kind,
  String instanceId,
) {
  final provider = libraryProvider(kind);
  // The replacement that the deprecation names is not in this version.
  // ignore: deprecated_member_use
  if (container.exists(provider)) {
    container.read(provider.notifier).reload(instanceId).ignore();
  }
}
