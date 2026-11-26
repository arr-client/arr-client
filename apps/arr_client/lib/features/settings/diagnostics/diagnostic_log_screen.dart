/// The diagnostic log, as the user reads and shares it (FR-065).
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';

/// Shows the entries, which the log has already redacted. What it shows is
/// what it shares: both come from one reading of the log, renewed only when
/// the user asks.
class DiagnosticLogScreen extends ConsumerStatefulWidget {
  const DiagnosticLogScreen({super.key});

  /// The most that is shared, in UTF-16 code units. Android passes shared text
  /// between apps in a transaction of limited size, which a full log can
  /// exceed. One entry is always smaller than this.
  static const shareLimit = 100000;

  @override
  ConsumerState<DiagnosticLogScreen> createState() =>
      _DiagnosticLogScreenState();
}

class _DiagnosticLogScreenState extends ConsumerState<DiagnosticLogScreen> {
  /// The newest entries that fit [DiagnosticLogScreen.shareLimit], oldest
  /// first, as texts.
  var _entries = const <String>[];

  /// Whether older entries did not fit.
  var _cut = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  void _read() {
    final all = ref.read(appServicesProvider).log.entries;
    final newest = <String>[];
    var length = 0;
    for (final entry in all.reversed) {
      final text = entry.toString();
      length += text.length + 1;
      if (length > DiagnosticLogScreen.shareLimit) break;
      newest.add(text);
    }
    _entries = newest.reversed.toList();
    _cut = newest.length < all.length;
  }

  Future<void> _share() async {
    final strings = AppLocalizations.of(context);
    final services = ref.read(appServicesProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await services.sharer.share(_entries.join('\n'));
    } catch (error) {
      services.log.log(
        LogLevel.warning,
        'The log could not be shared (${error.runtimeType})',
      );
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(strings.shareLogFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.diagnosticLog),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: strings.diagnosticLogRefresh,
            onPressed: () => setState(_read),
          ),
        ],
      ),
      floatingActionButton: _entries.isEmpty
          ? null
          : FloatingActionButton.extended(
              // The shell keeps other pages alive, whose buttons would share a
              // tag.
              heroTag: null,
              onPressed: () => unawaited(_share()),
              icon: const Icon(Icons.share),
              label: Text(strings.shareLog),
            ),
      body: _entries.isEmpty
          ? StateMessage(
              icon: Icons.article_outlined,
              message: strings.diagnosticLogEmpty,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final margin = screenMargin(constraints.maxWidth);
                return ListView.builder(
                  // So that the last entry can be scrolled above the button.
                  padding: EdgeInsets.fromLTRB(margin, 16, margin, 88),
                  itemCount: _entries.length + 1,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: index == 0
                        ? Text(
                            [
                              strings.diagnosticLogNotice,
                              if (_cut) strings.diagnosticLogCut,
                            ].join('\n\n'),
                            style: theme.textTheme.bodyLarge,
                          )
                        : Text(
                            _entries[index - 1],
                            style: theme.textTheme.bodySmall,
                          ),
                  ),
                );
              },
            ),
    );
  }
}
