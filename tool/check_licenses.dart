/// Rejects dependencies that are not GPL-3.0 compatible free software
/// (constitution VII). Run from the workspace root, after `flutter pub get`:
///
///     dart run tool/check_licenses.dart
///
/// Every package in `pubspec.lock` and `.dart_tool/package_config.json` is
/// checked, development dependencies included, using only files on disk.
/// Anything the check cannot identify is an error.
///
/// A license file is accepted only when all of its text is known licenses:
/// extra or changed wording makes it unknown. To accept another license, check
/// that it is GPL-3.0 compatible and add it to [identifyLicense].
///
/// Maven artifacts that Gradle resolves on behalf of other Maven artifacts are
/// not visible here; only coordinates written in a package's Gradle files are.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';

/// Packages that wrap a proprietary SDK, whatever their own license says.
final _proprietaryPackage = RegExp(
  r'^(firebase_.*|cloud_firestore.*|cloud_functions.*|google_mobile_ads'
  r'|google_mlkit_.*|google_maps_flutter.*|google_sign_in.*'
  r'|google_api_availability.*|in_app_(purchase|review|update).*|huawei_.*'
  r'|play_(integrity|install_referrer|asset_delivery).*|purchases_flutter'
  r'|onesignal_flutter|appsflyer_sdk)$',
);

/// Maven groups of proprietary SDKs.
final _proprietaryMaven = RegExp(
  r'\b(com\.google\.android\.(gms|play|libraries)|com\.google\.firebase'
  r'|com\.google\.mlkit|com\.google\.gms|com\.android\.billingclient'
  r'|com\.android\.installreferrer|com\.crashlytics|com\.huawei)\b',
);

final _licenseFileName = RegExp(
  r'^((un)?licen[sc]e|copying)([._-].*)?$',
  caseSensitive: false,
);

const _titles = {
  'mit license',
  'the mit license',
  'the mit license mit',
  'mit license mit',
  'bsd 2 clause license',
  'bsd 3 clause license',
  'all rights reserved',
};

// The shape of a bare copyright statement. Anything it does not describe is
// treated as license wording, so these accept as little as real holders need.
const _years = r'(?:19|20)\d\d(?: ?- ?(?:19|20)\d\d)?,?';
const _token = r'[\p{L}\p{N}_]+';
const _word = r"(?:\p{Lu}\.|\p{Lu}[\p{L}\p{M}'’-]*)";
// At most four capitalised words: a name, not a sentence.
const _name = '$_word(?: (?:of the |of )?$_word){0,3}';
const _suffix = r'(?:,? (?:Inc\.|Inc|LLC|Ltd\.|Ltd|GmbH|Corp\.))?';
const _contact =
    r'(?: (?:\((?:https?://[^\s()]+|[^\s()@]+@[^\s()@]+|[\p{L}\p{N}_]+)\)'
    r'|<(?:https?://[^\s<>]+|[^\s<>@]+@[^\s<>@]+)>))';
const _holder =
    "(?:(?:the )?'?$_token'? (?:project authors|authors and maintainers)"
    '|$_name$_suffix(?: and the project contributors)?'
    '|$_token)$_contact?';
// A further holder must bring its own years or contact.
const _another =
    '(?:, $_years $_name$_suffix$_contact?|, $_name$_suffix$_contact)';

final _copyrightStatement = RegExp(
  r'^(?:(?:Copyright|COPYRIGHT)(?: \([Cc]\)| ©)?|\([Cc]\)|©) '
  '$_years $_holder(?:$_another)*'
  r'[.,]?(?: All [Rr]ights [Rr]eserved\.?)?$',
  unicode: true,
);

/// The Apache appendix has its own copyright line, directly above this one.
const _appendixNext = 'Licensed under the Apache License';

/// The owner named by the third BSD clause.
final _endorser = RegExp(
  '[Nn]either the name of (?:the copyright holder|(?:the )?$_name$_suffix) '
  'nor the names of',
  unicode: true,
);

/// Reduces a license text to its words: no case, layout, punctuation or list
/// markers. Titles and bare copyright statements are dropped only where they
/// head the text. Letters of every script are kept.
String normalizeLicense(String text) {
  final lines = [
    for (final line in const LineSplitter().convert(text)) line.trim(),
  ];
  final body = lines
      .skipWhile(
        (line) =>
            _titles.contains(_words(line.toLowerCase())) ||
            _words(line).isEmpty ||
            _copyrightStatement.hasMatch(line),
      )
      .toList();

  for (var i = body.length - 1; i >= 0; i--) {
    if (!body[i].startsWith(_appendixNext)) continue;
    var above = i - 1;
    while (above >= 0 && body[above].isEmpty) {
      above--;
    }
    if (above >= 0 &&
        (body[above] == 'Copyright [yyyy] [name of copyright owner]' ||
            _copyrightStatement.hasMatch(body[above]))) {
      body.removeAt(above);
      i = above;
    }
  }

  final joined = body
      .map((line) => line.replaceFirst(RegExp(r'^([*•-]|\d\.)\s+'), ''))
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(_endorser, 'neither the name of holder nor the names of');
  return _words(joined.toLowerCase().replaceAll('https://', 'http://'));
}

String _words(String text) =>
    text.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

const _mit =
    'permission is hereby granted free of charge to any person obtaining a copy '
    'of this software and associated documentation files the software to deal '
    'in the software without restriction including without limitation the '
    'rights to use copy modify merge publish distribute sublicense and or sell '
    'copies of the software and to permit persons to whom the software is '
    'furnished to do so subject to the following conditions the above copyright '
    'notice and this permission notice shall be included in all copies or '
    'substantial portions of the software the software is provided as is '
    'without warranty of any kind express or implied including but not limited '
    'to the warranties of merchantability fitness for a particular purpose and '
    'noninfringement in no event shall the authors or copyright holders be '
    'liable for any claim damages or other liability whether in an action of '
    'contract tort or otherwise arising from out of or in connection with the '
    'software or the use or other dealings in the software';

const _bsdConditions =
    'redistribution and use in source and binary forms with or without '
    'modification are permitted provided that the following conditions are met '
    'redistributions of source code must retain the above copyright notice this '
    'list of conditions and the following disclaimer redistributions in binary '
    'form must reproduce the above copyright notice this list of conditions and '
    'the following disclaimer in the documentation and or other materials '
    'provided with the distribution';

const _bsdDisclaimer =
    'this software is provided by the copyright holders and contributors as is '
    'and any express or implied warranties including but not limited to the '
    'implied warranties of merchantability and fitness for a particular purpose '
    // The second form is the unfilled <COPYRIGHT HOLDER> of the template.
    'are disclaimed in no event shall '
    '(?:the copyright (?:owner|holder) (?:or|and) contributors|copyright holder) '
    'be liable for any direct indirect incidental '
    'special exemplary or consequential damages including but not limited to '
    'procurement of substitute goods or services loss of use data or profits or '
    'business interruption however caused and on any theory of liability '
    'whether in contract strict liability or tort including negligence or '
    'otherwise arising in any way out of the use of this software even if '
    'advised of the possibility of such damage';

/// The third BSD clause, with the owner's name replaced by [_endorser].
const _bsdNoEndorsement =
    'neither the name of holder nor the names of its contributors may be used '
    'to endorse or promote products derived from this software without specific '
    'prior written permission';

final _bsd2 = RegExp('^$_bsdConditions $_bsdDisclaimer\$');
final _bsd3 = RegExp('^$_bsdConditions $_bsdNoEndorsement $_bsdDisclaimer\$');

/// SHA-256 of [normalizeLicense] of license texts too long to spell out.
const _longLicenses = {
  // Terms only, without the appendix.
  'd3b761037b99e5cb84d7615d780e864d6d33a661f7613e225a5e78983311b5f9':
      'Apache-2.0',
  '6a27e8d798463bfcb1d7336d22261b3416565e3f1285f702ae583afdda156cc1': 'MPL-2.0',
  '247c5b7d84c33edca2a78d44b2c8a8bef5475cd1ea2d73b1ba9b3dc7063196b7': 'GPL-3.0',
};

const _apacheAppendix =
    '50bb8131750d8251aab3e2636df786bcfdcdb256ed4bd6e527fe167814988bed';

String _hash(String text) => sha256.convert(utf8.encode(text)).toString();

/// Separates the licenses of a file that holds more than one.
final _separator = RegExp(r'^[ \t]*(={3,}|-{3,})[ \t\r]*$', multiLine: true);

/// The SPDX expression for [text], or null unless all of it is accepted
/// licenses: one, or several divided by lines of `===` or `---`.
String? identifyLicense(String text) {
  final whole = _identifyOne(text);
  if (whole != null) return whole;
  final ids = [
    for (final part in text.split(_separator))
      if (normalizeLicense(part).isNotEmpty) _identifyOne(part),
  ];
  return ids.isEmpty || ids.contains(null) ? null : ids.join(' AND ');
}

String? _identifyOne(String text) {
  final words = normalizeLicense(text);
  if (words == _mit) return 'MIT';
  if (_bsd2.hasMatch(words)) return 'BSD-2-Clause';
  if (_bsd3.hasMatch(words)) return 'BSD-3-Clause';

  // The Apache appendix is optional, and nothing else may follow the terms.
  const end = 'end of terms and conditions';
  final at = words.indexOf(end);
  if (at >= 0) {
    final rest = words.substring(at + end.length).trim();
    if (rest.isEmpty || _hash(rest) == _apacheAppendix) {
      final id = _longLicenses[_hash(words.substring(0, at + end.length))];
      if (id == 'Apache-2.0') return id;
    }
  }
  return _longLicenses[_hash(words)];
}

/// Checks the workspace at [root] and returns one message per problem.
/// Throws if the files that describe the dependencies cannot be read.
List<String> checkLicenses(Directory root) {
  final base = root.absolute.uri;
  File file(String path) => File.fromUri(base.resolve(path));

  final lockFile = file('pubspec.lock');
  final configFile = file('.dart_tool/package_config.json');
  for (final required in [file('pubspec.yaml'), lockFile, configFile]) {
    if (!required.existsSync()) {
      return ['${required.path} is missing: run `flutter pub get` first'];
    }
  }

  final workspace = loadYaml(file('pubspec.yaml').readAsStringSync()) as Map;
  final members = {
    for (final path in ['.', ...?workspace['workspace'] as List?])
      _canonical(Directory.fromUri(base.resolve('$path/'))),
  };

  final lock = loadYaml(lockFile.readAsStringSync()) as Map;
  final locked = lock['packages'] as Map? ?? const {};

  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final roots = <String, Directory>{
    for (final package
        in (config['packages'] as List).cast<Map<dynamic, dynamic>>())
      package['name'] as String: Directory.fromUri(
        configFile.uri.resolve('${package['rootUri']}/'),
      ),
  };

  final errors = <String>[];
  for (final name in locked.keys.cast<String>()) {
    if (!roots.containsKey(name)) {
      errors.add('$name: locked but not fetched: run `flutter pub get`');
    }
  }

  for (final MapEntry(key: name, value: directory) in roots.entries) {
    if (!directory.existsSync()) {
      errors.add('$name: ${directory.path} does not exist');
      continue;
    }
    errors.addAll(_proprietaryUse(name, directory));
    if (members.contains(_canonical(directory))) continue; // our own code

    final entry = locked[name];
    if (entry is! Map) {
      errors.add('$name: not in pubspec.lock: run `flutter pub get`');
      continue;
    }
    switch (entry['source']) {
      case 'sdk' when entry['description'] == 'flutter':
        // Packages of the Flutter SDK share the license at its root, found
        // from the `flutter` package at <sdk>/packages/flutter.
        final flutter = roots['flutter'];
        if (flutter == null) {
          errors.add('$name: cannot locate the Flutter SDK license');
        } else {
          errors.addAll(_licenseProblems(name, flutter.parent.parent));
        }
      case 'hosted' || 'git':
        final version = _version(directory);
        if (version != entry['version']) {
          errors.add(
            '$name: pubspec.lock has ${entry['version']} but $version is '
            'fetched: run `flutter pub get`',
          );
        } else {
          errors.addAll(_licenseProblems(name, directory));
        }
      case 'path':
        errors.addAll(_licenseProblems(name, directory));
      case final source:
        errors.add('$name: unknown dependency source "$source"');
    }
  }
  return errors..sort();
}

String _canonical(Directory directory) => directory.existsSync()
    ? directory.resolveSymbolicLinksSync()
    : directory.path;

Object? _version(Directory package) {
  final pubspec = File.fromUri(package.uri.resolve('pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  return (loadYaml(pubspec.readAsStringSync()) as Map)['version'];
}

String _read(File file) =>
    utf8.decode(file.readAsBytesSync(), allowMalformed: true);

String _baseName(FileSystemEntity entity) =>
    entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);

/// Every license file at the top of [directory] must be an accepted license.
List<String> _licenseProblems(String name, Directory directory) {
  final files = directory
      .listSync()
      .where((entity) => _licenseFileName.hasMatch(_baseName(entity)))
      .map((entity) => File(entity.path))
      .toList();
  if (files.isEmpty) return ['$name: no license file in ${directory.path}'];

  final errors = <String>[];
  for (final file in files) {
    final id = identifyLicense(_read(file));
    if (id == null) {
      errors.add('$name: unrecognized license in ${file.path}');
    } else if (id.contains('MPL-2.0') && _optsOutOfGpl(directory)) {
      errors.add(
        '$name: MPL-2.0 marked "Incompatible With Secondary Licenses"',
      );
    }
  }
  return errors;
}

/// MPL-2.0 is GPL compatible unless a source file carries this notice.
bool _optsOutOfGpl(Directory directory) => directory
    .listSync(recursive: true, followLinks: false)
    .whereType<File>()
    .where(
      (file) => RegExp(r'\.(dart|c|cc|cpp|h|java|kt)$').hasMatch(file.path),
    )
    .any(
      (file) => _read(file).contains('Incompatible With Secondary Licenses'),
    );

/// Matches a string literal (kept) or a comment (dropped).
final _gradleToken = RegExp(
  r'''("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')|//[^\n]*|/\*[\s\S]*?\*/''',
);

/// A proprietary package name, or a proprietary SDK in its Android build files.
List<String> _proprietaryUse(String name, Directory package) {
  final errors = <String>[
    if (_proprietaryPackage.hasMatch(name))
      '$name: wraps a proprietary SDK (denied by name)',
  ];
  final pending = [Directory.fromUri(package.uri.resolve('android/'))];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is Directory) {
        if (!const {'build', '.gradle'}.contains(_baseName(entity))) {
          pending.add(entity);
        }
      } else if (entity is File &&
          RegExp(r'\.(gradle|gradle\.kts|toml)$').hasMatch(entity.path)) {
        final code = _read(entity)
            .replaceAllMapped(_gradleToken, (match) => match[1] ?? ' ');
        for (final group in {
          for (final match in _proprietaryMaven.allMatches(code)) match[0],
        }) {
          errors.add('$name: proprietary SDK $group in ${entity.path}');
        }
      }
    }
  }
  return errors;
}

void main(List<String> arguments) {
  final root = arguments.isEmpty ? Directory.current : Directory(arguments[0]);
  final errors = checkLicenses(root);
  if (errors.isEmpty) {
    stdout.writeln('License check passed.');
    return;
  }
  errors.forEach(stderr.writeln);
  stderr.writeln(
    '${errors.length} license problem(s). See tool/check_licenses.dart.',
  );
  exitCode = 1;
}
