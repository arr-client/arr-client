import 'package:material_ui/material_ui.dart';

import '../l10n/generated/ui_localizations.dart';
import 'state_message.dart';

/// Says that the item no longer exists on the server.
///
/// [onGone] is called once for each [itemId], after the first frame in which it
/// is shown, so that the caller can remove the item from its list and cache. A
/// way back is offered where there is a route to return to.
class ItemGoneView extends StatefulWidget {
  /// Creates an [ItemGoneView].
  /// [itemId] is required with [onGone]. It is the widget's key, so that
  /// another item in the same place is reported too.
  ItemGoneView({this.itemId, this.onGone})
    : assert(onGone == null || itemId != null),
      super(key: ValueKey<Object?>(itemId));

  /// Which item is gone, such as its `ItemRef`. Compared with `==`.
  final Object? itemId;

  /// Forgets the item.
  final VoidCallback? onGone;

  @override
  State<ItemGoneView> createState() => _ItemGoneViewState();
}

class _ItemGoneViewState extends State<ItemGoneView> {
  @override
  void initState() {
    super.initState();
    // Not during build: the caller is likely to change state.
    final onGone = widget.onGone;
    if (onGone != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onGone());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UiLocalizations.of(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return StateMessage(
      icon: Icons.delete_outline,
      message: l10n.itemGone,
      announce: true,
      action: canPop
          ? FilledButton(
              onPressed: () => Navigator.maybePop(context),
              child: Text(l10n.goBack),
            )
          : null,
    );
  }
}
