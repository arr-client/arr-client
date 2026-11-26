import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/generated/ui_localizations.dart';
import 'failure_message.dart';
import 'item_gone_view.dart';
import 'stale_notice.dart';
import 'state_message.dart';
import 'view_state.dart';

/// The body of a screen in each of its states: loading, empty, error, stale
/// and current. A [NotFound] failure shows the item as gone, even when there
/// is saved data for it.
///
/// It fills the space it is given, which must be bounded; put it in the body
/// of a `Scaffold`. It watches one source only, so a screen that combines
/// instances keeps their states apart and a slow one does not hold back the
/// rest.
class StateScaffold<T> extends StatelessWidget {
  /// Creates a [StateScaffold].
  const StateScaffold({
    required this.state,
    required this.builder,
    required this.onRetry,
    this.isEmpty,
    this.emptyMessage,
    this.itemId,
    this.onGone,
    super.key,
  }) : assert(onGone == null || itemId != null);

  /// What there is to show.
  final ViewState<T> state;

  /// Builds the content. When `isStale` is true the data may be out of date,
  /// and actions that change data must be disabled.
  final Widget Function(BuildContext context, T value, {required bool isStale})
  builder;

  /// Loads again, at the user's request.
  final VoidCallback onRetry;

  /// Whether a value holds nothing to show. Never empty when null.
  final bool Function(T value)? isEmpty;

  /// The localized text for the empty state; say what is empty.
  final String? emptyMessage;

  /// Which item [state] is about, such as its `ItemRef`, on a screen about one
  /// item. Compared with `==`. Required with [onGone].
  final Object? itemId;

  /// Called once when the item turns out to be gone, so that the caller can
  /// remove it from its list and cache.
  final VoidCallback? onGone;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      ViewLoading() => Center(
        child: CircularProgressIndicator(
          semanticsLabel: UiLocalizations.of(context).loading,
        ),
      ),
      ViewError(failure: NotFound()) ||
      ViewData(
        staleness: Staleness(failure: NotFound()),
      ) => ItemGoneView(itemId: itemId, onGone: onGone),
      ViewError(:final failure) => StateMessage(
        icon: Icons.error_outline,
        message: failureMessage(context, failure),
        announce: true,
        action: FilledButton(
          onPressed: onRetry,
          child: Text(UiLocalizations.of(context).retry),
        ),
      ),
      ViewData(:final value, :final staleness) => _data(
        context,
        value,
        staleness,
      ),
    };
  }

  Widget _data(BuildContext context, T value, Staleness? staleness) {
    final content = (isEmpty?.call(value) ?? false)
        ? StateMessage(
            icon: Icons.inbox_outlined,
            message: emptyMessage ?? UiLocalizations.of(context).nothingToShow,
          )
        : builder(context, value, isStale: staleness != null);
    // The same tree with and without the notice, so that the content keeps its
    // state, such as the scroll position, when the data turns stale or current.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // At large text sizes the notice scrolls and leaves room for the
          // content.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
            child: staleness == null
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: StaleNotice(staleness: staleness, onRetry: onRetry),
                  ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}
