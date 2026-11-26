/// Enforces the dependency rule of specs/001-arr-companion-app/plan.md:
///
///     app -> modules, core, ui, platform_local_network
///     module -> core, ui, servarr (Servarr family only)
///     servarr -> core
///     ui -> core
///     core, platform_local_network, workspace root -> none of ours
///
/// Both what each pubspec.yaml declares and what its Dart files import are
/// checked: a pub workspace shares one package configuration, so an undeclared
/// import of another workspace package still compiles. What could hide such an
/// import from the check is rejected too: a symlink under apps/ or packages/,
/// an import of a file the check does not read, and a file that does not parse.
///
/// Run from the repository root: `dart run tool/check_dependencies.dart`
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:yaml/yaml.dart';

const _servarrFamily = {'sonarr', 'radarr', 'lidarr', 'readarr', 'prowlarr'};

const _dependencySections = [
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
];

enum _Role { workspace, app, core, ui, servarr, platform, module }

class _Package {
  _Package(this.path, this.name, this.role, this.pubspec);

  /// Relative to the repository root, empty for the root itself.
  final String path;
  final String name;
  final _Role role;
  final YamlMap pubspec;

  bool mayUse(_Package other) {
    if (other.name == name) return true;
    return switch (role) {
      _Role.app => const {
        _Role.module,
        _Role.core,
        _Role.ui,
        _Role.platform,
      }.contains(other.role),
      _Role.module =>
        other.role == _Role.core ||
            other.role == _Role.ui ||
            (other.role == _Role.servarr &&
                _servarrFamily.contains(path.split('/').last)),
      _Role.servarr || _Role.ui => other.role == _Role.core,
      _Role.core || _Role.platform || _Role.workspace => false,
    };
  }
}

_Role? _roleOf(String path) {
  return switch (path.split('/')) {
    ['apps', _] => _Role.app,
    ['packages', 'core'] => _Role.core,
    ['packages', 'ui'] => _Role.ui,
    ['packages', 'servarr'] => _Role.servarr,
    ['packages', 'platform_local_network'] => _Role.platform,
    ['packages', 'modules', _] => _Role.module,
    _ => null,
  };
}

/// Returns one message per violation found in the repository at [root].
List<String> checkDependencies(Directory root) {
  final errors = <String>[];
  final rootUri = root.absolute.uri.normalizePath();
  final rootPubspec = _readPubspec(rootUri.resolve('pubspec.yaml'));
  if (rootPubspec == null) return ['pubspec.yaml: missing or not a map'];

  final members = <String>[
    if (rootPubspec['workspace'] case final YamlList list)
      for (final entry in list) '$entry',
  ];
  if (members.isEmpty) return ['pubspec.yaml: no workspace members'];

  final packages = [
    _Package('', '${rootPubspec['name']}', _Role.workspace, rootPubspec),
  ];
  for (final member in members) {
    final role = _roleOf(member);
    final pubspec = _readPubspec(rootUri.resolve('$member/pubspec.yaml'));
    if (role == null) {
      errors.add('$member: no dependency rule for a package at this path');
    } else if (pubspec == null) {
      errors.add('$member/pubspec.yaml: missing or not a map');
    } else {
      packages.add(_Package(member, '${pubspec['name']}', role, pubspec));
    }
  }

  // A package left out of the workspace list would otherwise go unchecked, and
  // a link can bring another package's files in under an allowed path.
  for (final top in ['apps', 'packages']) {
    final directory = Directory.fromUri(rootUri.resolve('$top/'));
    for (final entity in _entries(directory)) {
      if (entity is Link) {
        final path = _relative(rootUri, entity.uri);
        errors.add('$path: symlinks are not allowed');
      } else if (entity.uri.pathSegments.last == 'pubspec.yaml') {
        final path = _relative(rootUri, entity.uri.resolve('.'));
        if (!members.contains(path)) {
          errors.add('$path: has a pubspec.yaml but is not a workspace member');
        }
      }
    }
  }

  final byName = <String, _Package>{};
  for (final package in packages) {
    if (byName.containsKey(package.name)) {
      errors.add('${package.path}: duplicate package name ${package.name}');
    }
    byName[package.name] = package;
  }

  Uri baseOf(_Package package) => package.role == _Role.workspace
      ? rootUri
      : rootUri.resolve('${package.path}/');

  for (final package in packages) {
    final base = baseOf(package);
    final pubspecName = _relative(rootUri, base.resolve('pubspec.yaml'));

    for (final section in _dependencySections) {
      final declared = package.pubspec[section];
      if (declared is! YamlMap) continue;
      for (final key in declared.keys) {
        final other = byName['$key'];
        if (other != null && !package.mayUse(other)) {
          errors.add(
            '$pubspecName: ${package.name} must not depend on '
            '${other.name} ($section)',
          );
        }
      }
    }

    // The root package owns only what lies outside the member directories.
    final outside = package.role == _Role.workspace
        ? [base.resolve('apps/'), base.resolve('packages/')]
        : const <Uri>[];
    final dartFiles = _entries(
      Directory.fromUri(base),
      skip: {for (final directory in outside) directory.toFilePath()},
    ).whereType<File>().where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final name = _relative(rootUri, file.uri);
      final directives = readDirectives(file.readAsStringSync());
      if (!directives.parsed) errors.add('$name: does not parse');

      for (final target in directives.uris) {
        final uri = Uri.tryParse(target);
        if (uri == null) {
          errors.add('$name: unreadable import $target');
          continue;
        }
        if (uri.scheme == 'dart') continue;

        // The file the directive names, and the package that must hold it.
        final Uri owner;
        final Uri imported;
        if (uri.scheme == 'package') {
          final other = byName[uri.pathSegments.firstOrNull];
          if (other == null) continue;
          if (!package.mayUse(other)) {
            errors.add('$name: ${package.name} must not import $target');
            continue;
          }
          owner = baseOf(other);
          imported = owner.replace(
            pathSegments: [
              ...owner.pathSegments.where((segment) => segment.isNotEmpty),
              'lib',
              ...uri.pathSegments.skip(1),
            ],
          );
        } else {
          // A relative path can reach another package without naming it.
          final resolved = uri.hasScheme ? null : file.uri.resolveUri(uri);
          if (resolved == null ||
              !'$resolved'.startsWith('$base') ||
              outside.any((other) => '$resolved'.startsWith('$other'))) {
            errors.add('$name: import leaves the package: $target');
            continue;
          }
          owner = base;
          imported = resolved;
        }
        if (!_isRead(owner, imported)) {
          errors.add('$name: imports a file this check does not read: $target');
        }
      }
    }
  }
  return errors..sort();
}

YamlMap? _readPubspec(Uri uri) {
  final file = File.fromUri(uri);
  if (!file.existsSync()) return null;
  final yaml = loadYaml(file.readAsStringSync());
  return yaml is YamlMap ? yaml : null;
}

/// Files and links under [directory], without what is in hidden directories,
/// in the directories whose paths are in [skip] or in a package's build output.
/// Links are not followed.
Iterable<FileSystemEntity> _entries(
  Directory directory, {
  Set<String> skip = const {},
}) sync* {
  if (!directory.existsSync()) return;
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is! Directory) {
      yield entity;
      continue;
    }
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (!_isSkipped(directory.uri, name) &&
        !skip.contains(entity.uri.toFilePath())) {
      yield* _entries(entity, skip: skip);
    }
  }
}

/// Whether the directory [name] inside [parent] is left unread. Only the
/// `build` directory beside a pubspec.yaml is output; elsewhere it is source.
bool _isSkipped(Uri parent, String name) =>
    name.startsWith('.') ||
    (name == 'build' &&
        File.fromUri(parent.resolve('pubspec.yaml')).existsSync());

/// Whether [file], inside the package at [base], is one the check reads: a Dart
/// file outside every skipped directory.
bool _isRead(Uri base, Uri file) {
  // The last segment of a directory URI is empty.
  final segments = file.pathSegments
      .skip(base.pathSegments.length - 1)
      .toList();
  if (segments.isEmpty || !segments.last.endsWith('.dart')) return false;
  var directory = base;
  for (final segment in segments.take(segments.length - 1)) {
    if (_isSkipped(directory, segment)) return false;
    directory = directory.resolve('${Uri.encodeComponent(segment)}/');
  }
  return true;
}

String _relative(Uri root, Uri uri) {
  final path = Uri.decodeFull(uri.path.substring(root.path.length));
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

/// The URIs named by the `import`, `export` and `part` directives of [source],
/// including every branch of a conditional import, with string escapes decoded.
///
/// `parsed` is false when [source] has syntax errors or a URI is not a plain
/// string, so that a directive may be missing from `uris`.
({List<String> uris, bool parsed}) readDirectives(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final literals = <StringLiteral>[
    for (final directive in result.unit.directives)
      ...switch (directive) {
        NamespaceDirective() => [
          directive.uri,
          for (final branch in directive.configurations) branch.uri,
        ],
        UriBasedDirective() => [directive.uri],
        PartOfDirective(:final uri?) => [uri],
        _ => const <StringLiteral>[],
      },
  ];
  final uris = [for (final literal in literals) ?literal.stringValue];
  return (
    uris: uris,
    parsed: result.errors.isEmpty && uris.length == literals.length,
  );
}

void main(List<String> arguments) {
  final errors = checkDependencies(Directory(arguments.firstOrNull ?? '.'));
  if (errors.isEmpty) {
    stdout.writeln('Dependency rule check passed.');
  } else {
    errors.forEach(stderr.writeln);
    exitCode = 1;
  }
}
