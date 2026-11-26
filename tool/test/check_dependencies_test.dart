import 'dart:io';

import 'package:test/test.dart';

import '../check_dependencies.dart';
import '../check_dependencies.dart' as script show main;

/// Workspace member path to package name, mirroring the real layout.
const _members = {
  'apps/arr_client': 'arr_client',
  'packages/core': 'core',
  'packages/ui': 'ui',
  'packages/servarr': 'servarr',
  'packages/platform_local_network': 'platform_local_network',
  'packages/modules/sonarr': 'sonarr',
  'packages/modules/radarr': 'radarr',
  'packages/modules/seerr': 'seerr',
};

void main() {
  late Directory root;

  void write(String path, String content) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  void pubspec(
    String member, {
    List<String> uses = const [],
    String section = 'dependencies',
  }) {
    write(
      '$member/pubspec.yaml',
      'name: ${_members[member]}\n'
          '${uses.isEmpty ? '' : '$section:\n'}'
          '${uses.map((name) => '  $name: any\n').join()}',
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('check_dependencies_');
    write(
      'pubspec.yaml',
      'name: root\nworkspace:\n'
          '${_members.keys.map((path) => '  - $path\n').join()}',
    );
    _members.keys.forEach(pubspec);
  });

  tearDown(() => root.deleteSync(recursive: true));

  List<String> check() => checkDependencies(root);

  test('accepts every dependency the plan allows', () {
    pubspec(
      'apps/arr_client',
      uses: ['sonarr', 'seerr', 'core', 'ui', 'platform_local_network'],
    );
    pubspec('packages/modules/sonarr', uses: ['core', 'ui', 'servarr']);
    pubspec('packages/modules/seerr', uses: ['core', 'ui']);
    pubspec('packages/servarr', uses: ['core']);
    pubspec('packages/ui', uses: ['core']);
    write(
      'packages/modules/sonarr/lib/sonarr_module.dart',
      "import 'dart:io';\n"
          "import 'package:core/core.dart';\n"
          "import 'package:servarr/servarr.dart';\n"
          "import 'package:sonarr/src/api.dart';\n"
          "import 'package:dio/dio.dart';\n"
          "export 'src/api.dart';\n",
    );
    write(
      'packages/modules/sonarr/test/contract/api_test.dart',
      "import '../../lib/src/api.dart';\n",
    );
    write('tool/test/a_test.dart', "import '../a.dart';\n");

    expect(check(), isEmpty);
  });

  for (final (from, to) in [
    ('packages/modules/sonarr', 'radarr'),
    ('packages/modules/sonarr', 'arr_client'),
    ('packages/modules/sonarr', 'platform_local_network'),
    ('packages/modules/seerr', 'servarr'),
    ('packages/core', 'ui'),
    ('packages/core', 'sonarr'),
    ('packages/ui', 'sonarr'),
    ('packages/ui', 'servarr'),
    ('packages/servarr', 'ui'),
    ('packages/servarr', 'sonarr'),
    ('packages/platform_local_network', 'core'),
    ('apps/arr_client', 'servarr'),
  ]) {
    test('rejects $from depending on $to', () {
      pubspec(from, uses: [to]);

      expect(
        check().single,
        allOf(contains('$from/pubspec.yaml'), contains('depend on $to')),
      );
    });

    test('rejects $from importing $to without declaring it', () {
      write('$from/lib/a.dart', "import 'package:$to/$to.dart';\n");

      expect(check().single, contains('$from/lib/a.dart'));
    });
  }

  for (final section in ['dev_dependencies', 'dependency_overrides']) {
    test('applies the rule to $section', () {
      pubspec('packages/modules/sonarr', uses: ['radarr'], section: section);

      expect(check().single, contains(section));
    });
  }

  test('rejects the workspace root reaching into a member', () {
    write(
      'pubspec.yaml',
      '${File('${root.path}/pubspec.yaml').readAsStringSync()}'
          'dev_dependencies:\n  core: any\n',
    );
    write('tool/a.dart', "import '../packages/core/lib/core.dart';\n");

    expect(check(), [
      contains('root must not depend on core'),
      contains('tool/a.dart: import leaves the package'),
    ]);
  });

  for (final (what, directive) in [
    ('an export', "export 'package:radarr/radarr_module.dart';"),
    (
      'a conditional import',
      "import 'stub.dart'\n"
          "    if (dart.library.io) 'package:radarr/radarr_module.dart';",
    ),
    (
      'an import behind comments and annotations',
      '// c\n/* /* nested */ */\n@Deprecated("a)")\nlibrary;\n'
          "import 'dart:io'; import 'package:radarr/radarr_module.dart';",
    ),
    ('a split string', "import 'package:rad' 'arr/radarr_module.dart';"),
    ('a relative import', "import '../../radarr/lib/radarr_module.dart';"),
    ('a relative part', "part '../../radarr/lib/radarr_module.dart';"),
    ('a file URI', "import 'file:///srv/radarr_module.dart';"),
    ('an escaped URI', r"import 'package:\x72adarr/radarr_module.dart';"),
    (
      'an import after a generic annotation',
      '@A<int>()\nlibrary;\n'
          "import 'package:radarr/radarr_module.dart';",
    ),
    (
      'an import after nested quotes in an annotation',
      '@Deprecated(\'\${f(\')\')}\')\nlibrary;\n'
          "import 'package:radarr/radarr_module.dart';",
    ),
  ]) {
    test('rejects $what that reaches another package', () {
      write('packages/modules/sonarr/lib/a.dart', '$directive\n');

      expect(check().single, contains('packages/modules/sonarr/lib/a.dart'));
    });
  }

  for (final (what, path, target) in [
    ('a hidden directory', 'lib/.h/a.dart', '.h/a.dart'),
    (
      'a hidden directory by package',
      'lib/.h/a.dart',
      'package:sonarr/.h/a.dart',
    ),
    ('an encoded hidden directory', 'lib/.h/a.dart', '%2Eh/a.dart'),
    ('build output', 'build/a.dart', '../build/a.dart'),
    ('a file that is not Dart', 'lib/a.txt', 'a.txt'),
  ]) {
    test('rejects an import of $what', () {
      write(
        'packages/modules/sonarr/$path',
        "import 'package:radarr/radarr_module.dart';\n",
      );
      write('packages/modules/sonarr/lib/b.dart', "import '$target';\n");

      expect(check().single, endsWith('does not read: $target'));
    });
  }

  test("rejects an import of another package's hidden directory", () {
    write(
      'packages/modules/sonarr/lib/a.dart',
      "import 'package:core/.h/a.dart';\n",
    );

    expect(check().single, contains('does not read'));
  });

  for (final (what, link, target) in [
    ('a directory', 'lib/other', '../../radarr/lib'),
    ('a file', 'lib/a.dart', '../../radarr/lib/radarr_module.dart'),
    ('a build directory in lib', 'lib/build', '../../radarr/lib'),
  ]) {
    test('rejects a symlink to $what inside a package', () {
      write('packages/modules/radarr/lib/radarr_module.dart', '');
      Link('${root.path}/packages/modules/sonarr/$link')
          .createSync(target, recursive: true);

      expect(
        check().single,
        'packages/modules/sonarr/$link: symlinks are not allowed',
      );
    });
  }

  test('rejects a file that does not parse', () {
    write('packages/modules/sonarr/lib/a.dart', 'class {\n');

    expect(check().single, contains('does not parse'));
  });

  test('ignores directives in comments and strings', () {
    write(
      'packages/modules/sonarr/lib/a.dart',
      "// import 'package:radarr/radarr_module.dart';\n"
          "/* import 'package:radarr/radarr_module.dart'; */\n"
          "const example = '''\n"
          "import 'package:radarr/radarr_module.dart';\n"
          "''';\n",
    );

    expect(check(), isEmpty);
  });

  test('ignores build output', () {
    write(
      'packages/modules/sonarr/build/a.dart',
      "import 'package:radarr/radarr_module.dart';\n",
    );

    expect(check(), isEmpty);
  });

  test('checks a source directory that happens to be called build', () {
    write(
      'packages/modules/sonarr/lib/src/build/a.dart',
      "import 'package:radarr/radarr_module.dart';\n",
    );

    expect(check().single, contains('lib/src/build/a.dart'));
  });

  test('rejects a package left out of the workspace', () {
    write('packages/modules/bazarr/pubspec.yaml', 'name: bazarr\n');

    expect(check().single, contains('not a workspace member'));
  });

  test('rejects a member it has no rule for', () {
    write('pubspec.yaml', 'name: root\nworkspace:\n  - packages/utils\n');
    write('packages/utils/pubspec.yaml', 'name: utils\n');

    expect(check(), contains(contains('no dependency rule')));
  });

  test('fails when there is nothing to check', () {
    write('pubspec.yaml', 'name: root\n');

    expect(check().single, contains('no workspace members'));
  });

  test('sets the exit code on a violation', () {
    addTearDown(() => exitCode = 0);
    pubspec('packages/core', uses: ['ui']);

    script.main([root.path]);

    expect(exitCode, 1);
  });

  test('this repository follows the rule', () {
    // Tests run from the repository root, as in CI.
    expect(checkDependencies(Directory.current), isEmpty);
  });
}
