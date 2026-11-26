/// Importing the certificate of a private certificate authority for one
/// instance (FR-005, research R4).
library;

import 'dart:async';
import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../src/l10n/generated/app_localizations.dart';
import 'certificate_file.dart';
import 'certificate_widgets.dart';

/// Asks for an authority for the instance at [url]. Answers its PEM, or null if
/// the user does not use one. [replacesPin] says that an accepted certificate
/// is no longer used then.
Future<String?> importAuthority(
  BuildContext context, {
  Uri? url,
  bool replacesPin = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<String>(
    builder: (context) =>
        AuthorityImportScreen(url: url, replacesPin: replacesPin),
  ),
);

/// Reads a file or pasted text, shows what it holds, and closes with its PEM
/// once the user says to use it.
class AuthorityImportScreen extends ConsumerStatefulWidget {
  const AuthorityImportScreen({this.url, this.replacesPin = false, super.key});

  final Uri? url;
  final bool replacesPin;

  @override
  ConsumerState<AuthorityImportScreen> createState() =>
      _AuthorityImportScreenState();
}

class _AuthorityImportScreenState extends ConsumerState<AuthorityImportScreen> {
  final _pasted = TextEditingController();

  /// What was read last; null before anything was.
  Result<CertificateAuthority, CertificateAuthorityProblem>? _read;
  var _unreadableFile = false;
  var _choosing = false;

  @override
  void dispose() {
    _pasted.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    setState(() => _choosing = true);
    try {
      final bytes = await ref.read(certificateFileProvider)();
      if (!mounted || bytes == null) return;
      _pasted.clear();
      setState(() {
        _unreadableFile = false;
        _read = readCertificateAuthority(bytes);
      });
    } catch (_) {
      // Said, not logged: the error may name the user's file.
      if (!mounted) return;
      _pasted.clear();
      setState(() {
        _unreadableFile = true;
        _read = null;
      });
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  void _paste(String text) => setState(() {
    _unreadableFile = false;
    _read = text.trim().isEmpty
        ? null
        : readCertificateAuthority(utf8.encode(text));
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final host = widget.url?.authority;
    final problem = switch (_read) {
      Err(error: CertificateAuthorityProblem.notACertificate) =>
        strings.authorityNotACertificate,
      Err(error: CertificateAuthorityProblem.notAnAuthority) =>
        strings.authorityNotAnAuthority,
      Err(error: CertificateAuthorityProblem.privateKey) =>
        strings.authorityPrivateKey,
      Err(error: CertificateAuthorityProblem.tooLarge) =>
        strings.authorityTooLarge,
      _ => _unreadableFile ? strings.authorityFileUnreadable : null,
    };
    final authority = switch (_read) {
      Ok(:final value) => value,
      _ => null,
    };
    return CertificatePage(
      title: strings.authorityTitle,
      children: [
        Text(
          host == null || host.isEmpty
              ? strings.authorityMeaning
              : strings.authorityMeaningFor(host),
          style: theme.textTheme.bodyLarge,
        ),
        if (widget.replacesPin) ...[
          const SizedBox(height: 12),
          CertificateWarning(strings.authorityReplacesPin),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.file_open_outlined),
          label: Text(strings.authorityChooseFile),
          onPressed: _choosing ? null : () => unawaited(_chooseFile()),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('authorityText'),
          controller: _pasted,
          onChanged: _paste,
          minLines: 3,
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          // A private key pasted by mistake must not be learnt.
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: strings.authorityPaste,
            alignLabelWithHint: true,
          ),
        ),
        if (problem != null) ...[
          const SizedBox(height: 12),
          Semantics(
            container: true,
            liveRegion: true,
            child: CertificateWarning(problem, danger: true),
          ),
        ],
        if (authority != null) ...[
          for (final certificate in authority.certificates) ...[
            const SizedBox(height: 24),
            CertificateDetails(certificate),
            const SizedBox(height: 12),
            Fingerprint(
              label: strings.certificateFingerprint,
              sha256: certificate.sha256,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, authority.pem),
            child: Text(strings.authorityUse),
          ),
        ],
      ],
    );
  }
}
