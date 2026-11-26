import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../src/l10n/generated/app_localizations.dart';
import 'app.dart';
import 'composition.dart';
import 'localization.dart';

/// Shows that the app is starting, then the app, or that it could not start.
class Bootstrap extends StatefulWidget {
  const Bootstrap({required this.start, super.key});

  /// Makes the services; called again if the user retries.
  final Future<AppServices> Function() start;

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  AppServices? _services;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final services = await widget.start();
      if (!mounted) {
        await services.close();
        return;
      }
      setState(() => _services = services);
    } catch (error) {
      // There is no diagnostic log yet. The type only, as in the log.
      debugPrint('arr-client could not start (${error.runtimeType})');
      if (mounted) setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_services?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_services case final services?) {
      return ArrClientApp(services: services);
    }
    return MaterialApp(
      theme: ArrTheme.light(),
      darkTheme: ArrTheme.dark(),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: _failed
                ? StateMessage(
                    icon: Icons.error_outline,
                    message: AppLocalizations.of(context).startFailed,
                    announce: true,
                    action: FilledButton(
                      onPressed: _retry,
                      child: Text(UiLocalizations.of(context).retry),
                    ),
                  )
                : Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: UiLocalizations.of(context).loading,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
