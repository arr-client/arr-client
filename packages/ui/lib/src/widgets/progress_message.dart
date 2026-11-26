import 'package:material_ui/material_ui.dart';

import '../l10n/generated/ui_localizations.dart';
import 'screen_margin.dart';

/// A wait that can be long, with what is being waited for. It scrolls when it
/// does not fit.
class ProgressMessage extends StatelessWidget {
  /// Creates a [ProgressMessage].
  const ProgressMessage({required this.message, super.key});

  /// The localized text, which screen readers announce.
  final String message;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(screenMargin(constraints.maxWidth)),
        child: Column(
          children: [
            CircularProgressIndicator(
              semanticsLabel: UiLocalizations.of(context).loading,
            ),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(message, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    ),
  );
}
