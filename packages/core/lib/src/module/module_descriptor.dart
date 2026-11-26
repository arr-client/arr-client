import 'package:flutter/widgets.dart';

import '../instances/auth_kind.dart';
import 'api_key_header.dart';
import 'auth_note.dart';
import 'module_category.dart';

/// What is known about a service before connecting to one.
final class ModuleDescriptor {
  /// Creates a [ModuleDescriptor].
  const ModuleDescriptor({
    required this.displayName,
    required this.icon,
    required this.category,
    required this.authKinds,
    required this.defaultPort,
    required this.minimumVersion,
    required this.testedVersion,
    this.apiKeyHeader,
    this.authNotes = const [],
  });

  /// The product's name, which is not translated.
  final String displayName;

  /// Shown wherever the service is listed.
  final IconData icon;

  /// What kind of service it is.
  final ModuleCategory category;

  /// The ways to authenticate, the preferred one first.
  final List<AuthKind> authKinds;

  /// Required when [authKinds] contains [AuthKind.apiKey].
  final ApiKeyHeader? apiKeyHeader;

  /// The port the service listens on unless configured otherwise.
  final int defaultPort;

  /// The oldest supported version.
  final String minimumVersion;

  /// The newest tested version.
  final String testedVersion;

  /// Warnings the add and edit form shows.
  final List<AuthNote> authNotes;
}
