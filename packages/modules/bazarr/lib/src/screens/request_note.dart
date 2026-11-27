import 'package:material_ui/material_ui.dart';

import '../l10n/generated/bazarr_localizations.dart';
import 'requests.dart';

/// What is known of the change last asked for the title shown, with a way to
/// look again once the server has answered or failed to.
class RequestNote extends StatelessWidget {
  /// Creates a [RequestNote].
  const RequestNote({
    required this.state,
    required this.name,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    super.key,
  });

  /// How the request stands.
  final RequestState state;

  /// The instance's name.
  final String name;

  /// What the button says.
  final String actionLabel;

  /// The button's icon.
  final IconData actionIcon;

  /// Goes to see how things stand.
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final strings = BazarrLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(switch (state) {
              RequestState.sending => strings.sending(name),
              RequestState.sent => strings.sentNote(name),
              RequestState.unknown => strings.unknownNote(name),
            }),
          ),
          const SizedBox(height: 8),
          if (state == RequestState.sending)
            LinearProgressIndicator(semanticsLabel: strings.sending(name))
          else
            OutlinedButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}
