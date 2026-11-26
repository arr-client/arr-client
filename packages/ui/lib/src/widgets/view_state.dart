import 'package:core/core.dart';

/// What a screen has to show, for `StateScaffold`.
///
/// Empty is not a state of its own: it is [ViewData] whose value holds nothing,
/// so that saved data can be both empty and stale.
sealed class ViewState<T> {
  const ViewState();
}

/// Nothing to show yet.
final class ViewLoading<T> extends ViewState<T> {
  /// Creates a [ViewLoading].
  const ViewLoading();
}

/// The load failed and there is nothing saved to show instead.
final class ViewError<T> extends ViewState<T> {
  /// Creates a [ViewError].
  const ViewError(this.failure);

  /// Why the load failed.
  final ServiceFailure failure;
}

/// There is data to show.
final class ViewData<T> extends ViewState<T> {
  /// Creates a [ViewData]. Pass [staleness] unless the server has just
  /// supplied [value].
  const ViewData(this.value, {this.staleness});

  /// The data.
  final T value;

  /// Null when [value] is current.
  final Staleness? staleness;
}

/// Why data on screen may be out of date.
final class Staleness {
  /// Creates a [Staleness].
  const Staleness({required this.fetchedAt, this.failure});

  /// When the server was last asked, by the device's clock.
  final DateTime fetchedAt;

  /// Why newer data could not be loaded. Null while it is still loading.
  final ServiceFailure? failure;
}
