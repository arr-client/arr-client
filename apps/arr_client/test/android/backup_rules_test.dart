import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _main = 'android/app/src/main';

/// Every place Android takes an app's files from for backup or transfer.
const _domains = [
  'root',
  'file',
  'database',
  'sharedpref',
  'external',
  'device_root',
  'device_file',
  'device_database',
  'device_sharedpref',
];

String _read(String path) =>
    File('$_main/$path')
        .readAsStringSync()
        .replaceAll(RegExp('<!--.*?-->', dotAll: true), '');

void _expectEverythingExcluded(String xml, String section) {
  final body = RegExp(
    '<$section>(.*?)</$section>',
    dotAll: true,
  ).firstMatch(xml)?.group(1);
  expect(body, isNotNull, reason: 'no <$section>');
  expect(body, isNot(contains('<include')));
  final excluded = RegExp(r'<exclude domain="(\w+)" path="\." />')
      .allMatches(body!)
      .map((match) => match.group(1));
  expect(excluded, unorderedEquals(_domains));
}

void main() {
  test('the manifest names both sets of backup rules', () {
    final manifest = _read('AndroidManifest.xml');

    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('Android 11 and lower back up nothing', () {
    _expectEverythingExcluded(
      _read('res/xml/backup_rules.xml'),
      'full-backup-content',
    );
  });

  for (final section in ['cloud-backup', 'device-transfer']) {
    test('Android 12 and later: $section takes nothing', () {
      _expectEverythingExcluded(
        _read('res/xml/data_extraction_rules.xml'),
        section,
      );
    });
  }
}
