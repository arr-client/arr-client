import 'package:core/core.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/generated/ui_localizations.dart';

/// How an item's state looks: a word and an icon, with colour only helping.
extension ItemStateLook on ItemState {
  /// The word.
  String stateLabel(UiLocalizations strings) => switch (this) {
    ItemState.downloading => strings.stateDownloading,
    ItemState.downloaded => strings.stateDownloaded,
    ItemState.partial => strings.statePartial,
    ItemState.unmonitored => strings.stateUnmonitored,
    ItemState.unreleased => strings.stateUnreleased,
    ItemState.missing => strings.stateMissing,
  };

  /// The icon.
  IconData get stateIcon => switch (this) {
    ItemState.downloading => Icons.downloading,
    ItemState.downloaded => Icons.check_circle,
    ItemState.partial => Icons.incomplete_circle,
    ItemState.unmonitored => Icons.bookmark_border,
    ItemState.unreleased => Icons.schedule,
    ItemState.missing => Icons.error_outline,
  };

  /// The icon's colour.
  Color stateColor(ColorScheme colors) => switch (this) {
    ItemState.downloading => colors.tertiary,
    ItemState.downloaded => colors.primary,
    ItemState.missing => colors.error,
    ItemState.partial ||
    ItemState.unmonitored ||
    ItemState.unreleased => colors.onSurfaceVariant,
  };
}

/// An item's state, as an icon and a word.
class ItemStateLine extends StatelessWidget {
  /// Creates an [ItemStateLine].
  const ItemStateLine(this.state, {super.key});

  /// The state.
  final ItemState state;

  @override
  Widget build(BuildContext context) => _IconLine(
    icon: state.stateIcon,
    color: state.stateColor(Theme.of(context).colorScheme),
    text: state.stateLabel(UiLocalizations.of(context)),
  );
}

/// Whether the server monitors an item. Shown only; it is not changed here.
class MonitoredLine extends StatelessWidget {
  /// Creates a [MonitoredLine].
  const MonitoredLine({required this.monitored, super.key});

  /// Whether it does.
  final bool monitored;

  @override
  Widget build(BuildContext context) {
    final strings = UiLocalizations.of(context);
    return _IconLine(
      icon: monitored ? Icons.bookmark : Icons.bookmark_border,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      text: monitored ? strings.monitored : strings.notMonitored,
    );
  }
}

/// A short text with an icon before it, which is decorative to screen readers:
/// the text says the same.
class _IconLine extends StatelessWidget {
  const _IconLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: MediaQuery.textScalerOf(context).scale(16),
        color: color,
      ),
      const SizedBox(width: 4),
      Flexible(child: Text(text)),
    ],
  );
}
