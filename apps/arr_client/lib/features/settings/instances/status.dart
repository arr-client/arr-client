/// What the list of services says about one of them (spec story 1): how it was
/// last reached, a rejected sign-in, a server version that is blocked or newer
/// than tested, and what the user can do about it.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui/ui.dart';

import '../../../app/navigation/locations.dart';
import '../../../app/providers.dart';
import '../../../src/l10n/generated/app_localizations.dart';
import '../../onboarding/failure_text.dart';

/// The status of [instance], an enabled one of the active profile with the
/// module [module].
class InstanceStatus extends ConsumerStatefulWidget {
  const InstanceStatus({
    required this.instance,
    required this.module,
    super.key,
  });

  final Instance instance;
  final ServiceModule module;

  @override
  ConsumerState<InstanceStatus> createState() => _InstanceStatusState();
}

class _InstanceStatusState extends ConsumerState<InstanceStatus> {
  /// The latch is being lifted.
  var _retrying = false;

  Instance get _instance => widget.instance;

  bool get _signsIn =>
      widget.module.sessionHandler != null &&
      (_instance.authKind == AuthKind.userPassword ||
          _instance.authKind == AuthKind.mediaServerAccount);

  /// Has a latched instance try once more; the prober does so when it sees the
  /// latch gone.
  Future<void> _retryAuth() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    // Taken now: the row may be gone by the time this fails.
    final services = ref.read(appServicesProvider);
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).changeFailed;
    try {
      await services.profiles.retryAuth(_instance.id);
    } catch (error) {
      // The type only: the text of an error may quote an address or a secret.
      services.log.log(
        LogLevel.warning,
        'A sign-in could not be retried (${error.runtimeType})',
      );
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failed)));
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  void _probe() => ref.read(appServicesProvider).prober.probe(_instance.id);

  @override
  Widget build(BuildContext context) {
    // Null until the registry has the instance.
    final connection = ref.watch(
      scopeProvider.select(
        (scope) => scope?.instance(_instance.id)?.connection,
      ),
    );
    final newer = _instance.lastProbe?.newerThanTested ?? false;
    // Not of a version that the address has since been changed from, nor of one
    // that has since been found too old.
    final version = _instance.unsupportedVersion == null
        ? _instance.detectedVersion
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_instance.authFailed)
          _latched(context)
        else
          ..._connection(context, connection),
        if (newer && version != null)
          _Line(
            icon: Icons.info_outline,
            title: AppLocalizations.of(context).statusNewerVersion(version),
          ),
      ],
    );
  }

  Widget _latched(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final apiKey = _instance.authKind == AuthKind.apiKey;
    return _Line(
      icon: Icons.lock_outline,
      isProblem: true,
      title: apiKey
          ? strings.testApiKeyRejectedTitle
          : strings.testSignInRejectedTitle,
      message: apiKey
          ? strings.statusApiKeyStopped
          : strings.statusSignInStopped,
      actions: [
        TextButton(
          onPressed: _retrying ? null : () => unawaited(_retryAuth()),
          child: Text(UiLocalizations.of(context).retry),
        ),
      ],
    );
  }

  List<Widget> _connection(
    BuildContext context,
    InstanceConnection? connection,
  ) {
    final strings = AppLocalizations.of(context);
    final unsupported = _instance.unsupportedVersion;
    Widget button(String label) =>
        TextButton(onPressed: _probe, child: Text(label));
    final retry = button(UiLocalizations.of(context).retry);

    final blocked = unsupported == null
        ? null
        : _Line(
            icon: Icons.block,
            isProblem: true,
            title: strings.testVersionTitle,
            message: failureMessage(
              context,
              UnsupportedVersion(
                version: unsupported.isEmpty ? null : unsupported,
              ),
            ),
            actions: [
              if (connection != null && connection is! ConnectionProbing) retry,
            ],
          );

    final line = switch (connection) {
      ConnectionProbing() => _Line(
        icon: Icons.sync,
        title: strings.testRunning,
      ),
      // The block says it all.
      ConnectionOnline() ||
      ConnectionUnknown() ||
      null when blocked != null => null,
      ConnectionOffline(failure: UnsupportedVersion()) when blocked != null =>
        null,
      ConnectionOnline() => _Line(
        icon: Icons.check_circle_outline,
        title: switch ((_instance.lastProbe, _instance.detectedVersion)) {
          (final probe?, final version?) => strings.testPassed(
            probe.product,
            version,
          ),
          _ => strings.statusConnected,
        },
      ),
      ConnectionOffline(:final failure) => _offline(
        context,
        failure,
        // The block has the button already.
        retry: blocked == null ? retry : null,
      ),
      ConnectionUnknown() || null => _Line(
        icon: Icons.help_outline,
        title: strings.statusNotChecked,
        actions: [if (connection != null) button(strings.statusCheckNow)],
      ),
    };
    return [?blocked, ?line];
  }

  Widget _offline(
    BuildContext context,
    ServiceFailure failure, {
    required Widget? retry,
  }) {
    final strings = AppLocalizations.of(context);
    final text = testFailureText(
      context,
      failure,
      service: widget.module.descriptor.displayName,
      authKind: _instance.authKind,
    );
    final isCertificate =
        failure is CertificateUntrusted || failure is CertificateChanged;
    // Where a sign-in may have been sent, the next one waits.
    final held =
        _signsIn &&
        !isCertificate &&
        failure is! DnsFailure &&
        failure is! PermissionDenied &&
        failure is! UnsupportedVersion;
    return _Line(
      icon: Icons.error_outline,
      isProblem: true,
      title: text.title,
      message: [text.message, if (held) strings.statusSignInWait].join('\n'),
      actions: [
        // The form reviews the certificate once it has tested the address.
        if (isCertificate)
          TextButton(
            onPressed: () =>
                unawaited(context.push(editInstanceLocation(_instance.id))),
            child: Text(strings.testReviewCertificate),
          ),
        ?retry,
      ],
    );
  }
}

/// One thing to say: an icon, so that it does not rest on colour, text and what
/// can be done.
class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.title,
    this.message,
    this.isProblem = false,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String? message;
  final bool isProblem;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 16,
              color: isProblem ? colors.error : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (message case final message?)
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
