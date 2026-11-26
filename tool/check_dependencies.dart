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
/// import of another workspace package still compiles.
///
/// Run from the repository root: `dart run tool/check_dependencies.dart`
library;

import 'dart:io';

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

  // A package left out of the workspace list would otherwise go unchecked.
  for (final top in ['apps', 'packages']) {
    final directory = Directory.fromUri(rootUri.resolve('$top/'));
    for (final file in _files(directory)) {
      if (file.uri.pathSegments.last != 'pubspec.yaml') continue;
      final path = _relative(rootUri, file.uri.resolve('.'));
      if (!members.contains(path)) {
        errors.add('$path: has a pubspec.yaml but is not a workspace member');
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

  for (final package in packages) {
    final isRoot = package.role == _Role.workspace;
    final base = isRoot ? rootUri : rootUri.resolve('${package.path}/');
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
    final outside = isRoot
        ? [base.resolve('apps/'), base.resolve('packages/')]
        : const <Uri>[];
    final dartFiles = _files(
      Directory.fromUri(base),
      skip: {for (final directory in outside) directory.toFilePath()},
    ).where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final name = _relative(rootUri, file.uri);
      for (final target in directiveUris(file.readAsStringSync())) {
        final uri = Uri.tryParse(target);
        if (uri == null) {
          errors.add('$name: unreadable import $target');
        } else if (uri.scheme == 'package') {
          final other = byName[uri.pathSegments.firstOrNull];
          if (other != null && !package.mayUse(other)) {
            errors.add('$name: ${package.name} must not import $target');
          }
        } else if (uri.scheme != 'dart') {
          // A relative path can reach another package without naming it.
          final resolved = uri.hasScheme ? null : '${file.uri.resolveUri(uri)}';
          if (resolved == null ||
              !resolved.startsWith('$base') ||
              outside.any((other) => resolved.startsWith('$other'))) {
            errors.add('$name: import leaves the package: $target');
          }
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

/// Files under [directory], without hidden directories, links, the directories
/// whose paths are in [skip], or a package's build output. Only the `build`
/// directory beside a pubspec.yaml is output; elsewhere it is source.
Iterable<File> _files(
  Directory directory, {
  Set<String> skip = const {},
}) sync* {
  if (!directory.existsSync()) return;
  final isPackage = File.fromUri(directory.uri.resolve('pubspec.yaml'))
      .existsSync();
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is File) {
      yield entity;
    } else if (entity is Directory) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (!name.startsWith('.') &&
          !(isPackage && name == 'build') &&
          !skip.contains(entity.uri.toFilePath())) {
        yield* _files(entity, skip: skip);
      }
    }
  }
}

String _relative(Uri root, Uri uri) {
  final path = Uri.decodeFull(uri.path.substring(root.path.length));
  return path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}

final _token = RegExp(
  r'(?<space>\s+|//[^\n]*)'
  r'|(?<comment>/\*)'
  r"""|(?<string>r?(?:'{3}[\s\S]*?'{3}|"{3}[\s\S]*?"{3}"""
  r"""|'(?:\\.|[^'\\\n])*'|"(?:\\.|[^"\\\n])*"))"""
  r'|(?<word>[A-Za-z_$][A-Za-z0-9_$]*)'
  r'|(?<symbol>.)',
);

typedef _Token = ({String text, bool isString});

/// The URIs named by the `import`, `export` and `part` directives of [source],
/// including every branch of a conditional import.
///
/// Directives precede all declarations, so reading stops at the first token
/// that is not part of one. Comments and strings elsewhere are never matched.
List<String> directiveUris(String source) {
  final tokens = _tokens(source);
  final uris = <String>[];
  var i = 0;

  String text(int at) => at < tokens.length ? tokens[at].text : '';

  while (i < tokens.length) {
    if (text(i) == '@') {
      // An annotation: a dotted name, then perhaps an argument list.
      i += 2;
      while (text(i) == '.') {
        i += 2;
      }
      if (text(i) == '(') {
        var depth = 0;
        do {
          if (text(i) == '(') depth++;
          if (text(i) == ')') depth--;
          i++;
        } while (depth > 0 && i < tokens.length);
      }
    } else if (const {
      'library',
      'import',
      'export',
      'part',
    }.contains(text(i))) {
      var depth = 0;
      String? uri;
      for (i++; i < tokens.length && text(i) != ';'; i++) {
        if (text(i) == '(') depth++;
        if (text(i) == ')') depth--;
        // Strings inside a condition's parentheses are values, not URIs.
        if (tokens[i].isString && depth == 0) {
          // Adjacent strings are one literal.
          uri = (uri ?? '') + _unquote(text(i));
        } else if (uri != null) {
          uris.add(uri);
          uri = null;
        }
      }
      if (uri != null) uris.add(uri);
      i++;
    } else {
      break;
    }
  }
  return uris;
}

List<_Token> _tokens(String source) {
  final tokens = <_Token>[];
  // Skip a script tag.
  var at = source.startsWith('#!') ? source.indexOf('\n') : 0;
  if (at < 0) return tokens;
  while (at < source.length) {
    final match = _token.matchAsPrefix(source, at) as RegExpMatch?;
    if (match == null) break;
    at = match.end;
    if (match.namedGroup('space') != null) continue;
    if (match.namedGroup('comment') != null) {
      // Block comments nest in Dart.
      var depth = 1;
      while (depth > 0 && at < source.length) {
        if (source.startsWith('/*', at)) {
          depth++;
          at += 2;
        } else if (source.startsWith('*/', at)) {
          depth--;
          at += 2;
        } else {
          at++;
        }
      }
      continue;
    }
    tokens.add((text: match[0]!, isString: match.namedGroup('string') != null));
  }
  return tokens;
}

String _unquote(String literal) {
  final body = literal.startsWith('r') ? literal.substring(1) : literal;
  final quotes = body.startsWith("'''") || body.startsWith('"""') ? 3 : 1;
  return body.substring(quotes, body.length - quotes);
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
