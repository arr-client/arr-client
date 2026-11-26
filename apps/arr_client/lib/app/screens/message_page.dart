import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../src/l10n/generated/app_localizations.dart';

/// A page that only says something. Opened by a link, with nothing to go back
/// to, it offers Home.
class MessagePage extends StatelessWidget {
  const MessagePage({
    required this.message,
    this.icon = Icons.info_outline,
    this.title,
    this.action,
    super.key,
  });

  final String message;
  final IconData icon;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final goHome = Navigator.of(context).canPop()
        ? null
        : TextButton(
            onPressed: () => context.go('/'),
            child: Text(AppLocalizations.of(context).goHome),
          );
    final actions = [?action, ?goHome];
    return Scaffold(
      appBar: AppBar(title: title == null ? null : Text(title!)),
      body: SafeArea(
        child: StateMessage(
          icon: icon,
          message: message,
          action: actions.isEmpty
              ? null
              : Column(mainAxisSize: MainAxisSize.min, children: actions),
        ),
      ),
    );
  }
}

/// Stands for a screen that a later version builds.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) => MessagePage(
    title: title,
    icon: Icons.construction_outlined,
    message: AppLocalizations.of(context).notBuilt,
  );
}

/// Shown while it is read what a route leads to.
class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: CircularProgressIndicator(
        semanticsLabel: UiLocalizations.of(context).loading,
      ),
    ),
  );
}
