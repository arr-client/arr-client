/// Checks that SQLite is compiled from the vendored source and that no prebuilt
/// library is downloaded (research R17, for F-Droid).
///
/// third_party/sqlite/sqlite3.c is the unchanged file of the public-domain
/// amalgamation of SQLite 3.54.1:
///
///     https://sqlite.org/2026/sqlite-amalgamation-3540100.zip
///     SHA3-256 of the zip, as published on https://sqlite.org/download.html:
///     92281c86e2957f9b9305890f9ac04204caa7b677cc868dc326d942689df28e30
///
/// To update it, replace the file with that of a newer amalgamation, verify the
/// zip's hash, and change the version, the address and the hashes here.
///
/// Run from the repository root. Without arguments only the configuration, the
/// file and pubspec.lock are checked:
///
///     dart run tool/check_sqlite_source.dart
///
/// After a build, `--built=<target OS>` also checks what the build hook of
/// package:sqlite3 did, and fails unless it compiled for that system:
///
///     dart run tool/check_sqlite_source.dart --built=android
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

const _source = 'third_party/sqlite/sqlite3.c';

const _sourceSha256 =
    '0c657666d819f261cc4007526ad57e1669de9949df7a8ea847aa284a2bf0ee52';

/// Packages that bring their own SQLite binaries, around the build hook.
const _bundlingPackages = ['sqlite3_flutter_libs', 'sqlcipher_flutter_libs'];

/// Returns one message per problem found in the repository at [root].
///
/// If [builtFor] names a target OS, the outputs of the build hook are checked
/// too, and there must be one for that system.
List<String> checkSqliteSource(
  Directory root, {
  String? builtFor,
  String sourceSha256 = _sourceSha256,
}) {
  final base = root.absolute.uri;
  final errors = <String>[];

  final pubspec = loadYaml(
    File.fromUri(base.resolve('pubspec.yaml')).readAsStringSync(),
  );
  final defines = switch (pubspec) {
    {'hooks': {'user_defines': {'sqlite3': final Map<Object?, Object?> map}}} =>
      map,
    _ => const <Object?, Object?>{},
  };
  // Any other value, or none, makes the hook download or use a system library.
  if (defines['source'] != 'source' || defines['path'] != _source) {
    errors.add(
      'pubspec.yaml: hooks.user_defines.sqlite3 must have "source: source" '
      'and "path: $_source"',
    );
  }

  final source = File.fromUri(base.resolve(_source));
  if (!source.existsSync()) {
    errors.add('$_source: missing');
  } else if ('${sha256.convert(source.readAsBytesSync())}' != sourceSha256) {
    errors.add('$_source: is not the expected file (SHA-256 differs)');
  }

  final lock = File.fromUri(base.resolve('pubspec.lock'));
  if (!lock.existsSync()) {
    errors.add('pubspec.lock: missing');
  } else if (loadYaml(lock.readAsStringSync()) case {
    'packages': final Map<Object?, Object?> packages,
  }) {
    for (final name in _bundlingPackages) {
      if (packages.containsKey(name)) {
        errors.add('pubspec.lock: $name brings prebuilt SQLite libraries');
      }
    }
  }

  if (builtFor != null && source.existsSync()) {
    errors.addAll(_buildProblems(base, source, builtFor));
  }
  return errors;
}

/// What the hook runner recorded: a compiling hook names the source file among
/// its dependencies, and a downloading one keeps its files in `download-*`.
List<String> _buildProblems(Uri base, File source, String builtFor) {
  final errors = <String>[];
  final expected = source.resolveSymbolicLinksSync();

  final shared = Directory.fromUri(
    base.resolve('.dart_tool/hooks_runner/shared/sqlite3/build/'),
  );
  if (shared.existsSync()) {
    for (final entity in shared.listSync(recursive: true)) {
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (entity is Directory && name.startsWith('download-')) {
        errors.add('${entity.path}: a prebuilt SQLite was downloaded');
      }
    }
  }

  final runs = Directory.fromUri(
    base.resolve('.dart_tool/hooks_runner/sqlite3/'),
  );
  var builtForTarget = false;
  for (final run
      in runs.existsSync() ? runs.listSync() : <FileSystemEntity>[]) {
    final input = File('${run.path}/input.json');
    final output = File('${run.path}/output.json');
    if (!input.existsSync()) continue;

    final os = switch (jsonDecode(input.readAsStringSync())) {
      {
        'config': {
          'extensions': {'code_assets': {'target_os': final String os}},
        },
      } =>
        os,
      // A run that builds no code, such as one for the web.
      _ => null,
    };
    if (os == null) continue;

    final result = output.existsSync()
        ? jsonDecode(output.readAsStringSync())
        : null;
    final compiled = switch (result) {
      {'status': 'success', 'dependencies': final List<Object?> files} =>
        files.any(
          (file) =>
              File('$file').existsSync() &&
              File('$file').resolveSymbolicLinksSync() == expected,
        ),
      _ => false,
    };
    if (!compiled) {
      errors.add('${run.path}: the build for $os did not compile $_source');
    } else if (os == builtFor) {
      builtForTarget = true;
    }
  }
  if (!builtForTarget) {
    errors.add('no build of SQLite for $builtFor found: build the app first');
  }
  return errors;
}

void main(List<String> arguments) {
  String? builtFor;
  for (final argument in arguments) {
    if (argument.startsWith('--built=')) {
      builtFor = argument.substring('--built='.length);
    } else {
      stderr.writeln('Unknown argument: $argument');
      exitCode = 64;
      return;
    }
  }

  final errors = checkSqliteSource(Directory.current, builtFor: builtFor);
  if (errors.isEmpty) {
    stdout.writeln('SQLite source check passed.');
  } else {
    errors.forEach(stderr.writeln);
    exitCode = 1;
  }
}
