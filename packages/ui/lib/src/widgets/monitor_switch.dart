import 'package:material_ui/material_ui.dart';

import '../l10n/generated/ui_localizations.dart';

/// Whether the server monitors an item, as a switch.
///
/// The caller shows the new [value] at once, keeps [saving] true until the
/// server has answered, and puts the old value back if it refused.
class MonitorSwitch extends StatelessWidget {
  /// Creates a [MonitorSwitch].
  const MonitorSwitch({
    required this.value,
    required this.saving,
    required this.onChanged,
    super.key,
  });

  /// Whether it is monitored.
  final bool value;

  /// Whether a change awaits the server's answer; the switch is then disabled.
  final bool saving;

  /// Null while monitoring cannot be changed.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = UiLocalizations.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(strings.monitored),
      subtitle: saving
          ? LinearProgressIndicator(semanticsLabel: strings.monitorSaving)
          : null,
      value: value,
      onChanged: saving ? null : onChanged,
    );
  }
}
