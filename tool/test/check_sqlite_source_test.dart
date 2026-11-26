import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../check_sqlite_source.dart';

const _content = 'int sqlite;';
final _hash = '${sha256.convert(utf8.encode(_content))}';

const _pubspec = '''
hooks:
  user_defines:
    sqlite3:
      source: source
      path: third_party/sqlite/sqlite3.c
''';

void main() {
  late Directory root;

  void write(String path, String content) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// What the hook runner leaves behind for one target.
  void writeRun(String name, String os, List<String> dependencies) {
    write(
      '.dart_tool/hooks_runner/sqlite3/$name/input.json',
      jsonEncode({
        'config': {
          'extensions': {
            'code_assets': {'target_os': os},
          },
        },
      }),
    );
    write(
      '.dart_tool/hooks_runner/sqlite3/$name/output.json',
      jsonEncode({'status': 'success', 'dependencies': dependencies}),
    );
  }

  List<String> check({String? builtFor}) =>
      checkSqliteSource(root, builtFor: builtFor, sourceSha256: _hash);

  String vendored() => '${root.path}/third_party/sqlite/sqlite3.c';

  setUp(() {
    root = Directory.systemTemp.createTempSync('sqlite_check');
    write('pubspec.yaml', _pubspec);
    write('pubspec.lock', 'packages:\n  sqlite3: {}\n');
    write('third_party/sqlite/sqlite3.c', _content);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('accepts the vendored source', () {
    expect(check(), isEmpty);
  });

  test('requires the hook to be configured to compile', () {
    for (final pubspec in [
      'name: x\n',
      _pubspec.replaceFirst('source: source', 'source: system'),
      _pubspec.replaceFirst('third_party/sqlite/sqlite3.c', 'other.c'),
    ]) {
      write('pubspec.yaml', pubspec);
      expect(check(), [contains('hooks.user_defines.sqlite3')]);
    }
  });

  test('rejects a changed or missing source', () {
    write('third_party/sqlite/sqlite3.c', 'int other;');
    expect(check(), [contains('SHA-256 differs')]);

    File(vendored()).deleteSync();
    expect(check(), [contains('missing')]);
  });

  test('rejects packages that bring SQLite binaries', () {
    write('pubspec.lock', 'packages:\n  sqlite3_flutter_libs: {}\n');
    expect(check(), [contains('sqlite3_flutter_libs')]);
  });

  test('accepts a build that compiled the source', () {
    writeRun('a', 'android', [vendored()]);
    writeRun('b', 'linux', [vendored()]);
    expect(check(builtFor: 'android'), isEmpty);
  });

  test('rejects a build that did not compile the source', () {
    writeRun('a', 'android', [vendored()]);
    writeRun('b', 'android', []);
    expect(check(builtFor: 'android'), [contains('did not compile')]);
  });

  test('rejects a downloaded library', () {
    writeRun('a', 'android', [vendored()]);
    write(
      '.dart_tool/hooks_runner/shared/sqlite3/build/download-1/libsqlite3.so',
      '',
    );
    expect(check(builtFor: 'android'), [contains('was downloaded')]);
  });

  test('does not pass without a build for the target', () {
    expect(check(builtFor: 'android'), [contains('no build of SQLite')]);

    writeRun('a', 'linux', [vendored()]);
    expect(check(builtFor: 'android'), [contains('no build of SQLite')]);
  });

  test('accepts this repository', () {
    expect(checkSqliteSource(Directory.current), isEmpty);
  });
}
