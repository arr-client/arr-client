import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';

/// Takes the toolbar's place while items are selected.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    required this.count,
    required this.onCancel,
    this.instanceName,
    this.note,
    this.onEdit,
    this.onSearch,
    this.showSearch = true,
    super.key,
  });

  final int count;

  /// Whose items are selected, where the library shows several instances.
  final String? instanceName;

  /// Why something cannot be selected or done.
  final String? note;

  final VoidCallback onCancel;

  /// Null while the selection cannot be changed.
  final VoidCallback? onEdit;
  final VoidCallback? onSearch;

  /// Whether the instance offers searches at all.
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: screenMargin(constraints.maxWidth),
          vertical: 4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: strings.selectionCancel,
                  onPressed: onCancel,
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(switch (instanceName) {
                    final name? => strings.selectionCountOn(count, name),
                    null => strings.selectionCount(count),
                  }),
                ),
                if (showSearch)
                  TextButton(
                    onPressed: onSearch,
                    child: Text(strings.selectionSearch),
                  ),
                FilledButton.tonal(
                  onPressed: onEdit,
                  child: Text(strings.selectionEdit),
                ),
              ],
            ),
            if (note case final note?) Text(note),
          ],
        ),
      ),
    );
  }
}
