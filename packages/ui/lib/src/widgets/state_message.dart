import 'package:material_ui/material_ui.dart';

/// A centred icon and message with an optional button, which scrolls when it
/// does not fit. The body of the empty, error and item-gone states.
class StateMessage extends StatelessWidget {
  /// Creates a [StateMessage].
  const StateMessage({
    required this.icon,
    required this.message,
    this.action,
    this.announce = false,
    super.key,
  });

  /// Shows the kind of state. Decorative to screen readers.
  final IconData icon;

  /// The localized text.
  final String message;

  /// What the user can do next.
  final Widget? action;

  /// Whether screen readers announce [message] when it appears.
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin = constraints.maxWidth < 600 ? 16.0 : 24.0;
        return SingleChildScrollView(
          // So that a pull to refresh around this works when it all fits.
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              minHeight: constraints.maxHeight,
            ),
            child: Padding(
              padding: EdgeInsets.all(margin),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: announce,
                    child: Text(
                      message,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (action case final action?) ...[
                    const SizedBox(height: 24),
                    action,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
