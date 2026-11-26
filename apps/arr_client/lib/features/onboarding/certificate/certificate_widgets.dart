/// What the certificate screens are made of.
library;

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';

/// A scrolling page with the screen margin.
class CertificatePage extends StatelessWidget {
  const CertificatePage({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final margin = constraints.maxWidth < 600 ? 16.0 : 24.0;
          return SingleChildScrollView(
            padding: EdgeInsets.all(margin),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Something to heed, marked by an icon as well as by colour. A [danger] one
/// takes the theme's error colours.
class CertificateWarning extends StatelessWidget {
  const CertificateWarning(this.text, {this.danger = false, super.key});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = danger ? scheme.onErrorContainer : scheme.onSurface;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: danger ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.warning_amber_outlined, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A fingerprint as `openssl x509 -fingerprint` writes it, to compare by eye.
String formatFingerprint(String sha256) => [
  for (var at = 0; at < sha256.length; at += 2)
    sha256.substring(at, at + 2 > sha256.length ? sha256.length : at + 2),
].join(':').toUpperCase();

/// The SHA-256 fingerprint under [label], in groups that wrap, with a button
/// that copies it.
class Fingerprint extends StatelessWidget {
  const Fingerprint({
    required this.label,
    required this.sha256,
    this.copy = true,
    super.key,
  });

  final String label;
  final String sha256;
  final bool copy;

  // Four bytes to a group.
  static const _group = 12;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = formatFingerprint(sha256);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Semantics(
          label: text,
          excludeSemantics: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var at = 0; at < text.length; at += _group)
                Text(
                  text.substring(
                    at,
                    at + _group > text.length ? text.length : at + _group,
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
        ),
        if (copy)
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined),
            label: Text(strings.certificateCopy),
            onPressed: () => unawaited(_copy(context, text)),
          ),
      ],
    );
  }

  static Future<void> _copy(BuildContext context, String text) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = AppLocalizations.of(context).certificateCopied;
    await Clipboard.setData(ClipboardData(text: text));
    if (!messenger.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }
}

// Control, direction and other characters that could disguise a name.
final _unprintable = RegExp(r'[\p{C}\p{Zl}\p{Zp}]', unicode: true);

final _attribute = RegExp(r'/(?=(?:CN|C|L|ST|O|OU)=)');

/// A name of a certificate, one attribute to a line, or null if it has none.
/// Whoever made the certificate chose it, so it is shown as harmless text.
String? certificateName(String? name) {
  final lines = [
    for (final part in (name ?? '').split(_attribute))
      if (part.isNotEmpty) part.replaceAll(_unprintable, '\u{fffd}'),
  ];
  if (lines.isEmpty) return null;
  final text = lines.join('\n');
  return text.runes.length > 300
      ? '${String.fromCharCodes(text.runes.take(300))}…'
      : text;
}

/// Whom a certificate names, who signed it, when it is valid, and a warning if
/// that is not now. What the certificate does not say is left out.
class CertificateDetails extends StatelessWidget {
  const CertificateDetails(this.certificate, {super.key});

  final CertificateInfo certificate;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    String? date(DateTime? value) =>
        value == null ? null : dates.formatMediumDate(value.toLocal());
    final now = DateTime.now();
    final expired = certificate.notAfter?.isBefore(now) ?? false;
    final early = certificate.notBefore?.isAfter(now) ?? false;
    final rows = [
      (strings.certificateSubject, certificateName(certificate.subject)),
      (strings.certificateIssuer, certificateName(certificate.issuer)),
      (strings.certificateNotBefore, date(certificate.notBefore)),
      (strings.certificateNotAfter, date(certificate.notAfter)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows)
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleSmall),
                    Text(value),
                  ],
                ),
              ),
            ),
        if (expired) CertificateWarning(strings.certificateExpired),
        if (early) CertificateWarning(strings.certificateNotYetValid),
      ],
    );
  }
}
