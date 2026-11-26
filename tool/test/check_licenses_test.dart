import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../check_licenses.dart';

const mit = '''
MIT License

Copyright (c) 2020 Jane Doe

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';

const _bsdStart = '''
Copyright 2014 The Authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
''';

const _bsdEndorsement = '''
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.
''';

const _bsdAdvertising = '''
    * All advertising materials mentioning features or use of this software
      must display the following acknowledgement: This product includes
      software developed by the organization.
''';

const _bsdEnd = '''

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
''';

const bsd2 = '$_bsdStart$_bsdEnd';
const bsd3 = '$_bsdStart$_bsdEndorsement$_bsdEnd';
const bsd4 = '$_bsdStart$_bsdAdvertising$_bsdEndorsement$_bsdEnd';

const nonCommercial = '''
Creative Commons Attribution-NonCommercial 4.0 International Public License
''';

const proprietary = '''
Copyright (c) 2024 Vendor Inc. All rights reserved.
This software is licensed, not sold. You may not redistribute it.
''';

/// The license of a package this repository really depends on.
String licenseOf(String package) {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(configFile.readAsStringSync()) as Map;
  final entry = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((entry) => entry['name'] == package);
  final root = configFile.uri.resolve('${entry['rootUri']}/');
  return File.fromUri(root.resolve('LICENSE')).readAsStringSync();
}

/// A workspace on disk shaped like the one pub leaves behind.
class Workspace {
  Workspace() : root = Directory.systemTemp.createTempSync('licenses') {
    addTearDown(() => root.deleteSync(recursive: true));
    write('pubspec.yaml', 'name: root\nworkspace:\n  - app\n');
    write('app/pubspec.yaml', 'name: app\n');
    roots.addAll({'root': '../', 'app': '../app'});
  }

  final Directory root;
  final locked = <String, Object>{};
  final roots = <String, String>{};

  void write(String path, String content) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// Adds a fetched and locked package. A null [license] writes none.
  void add(
    String name, {
    String? license = mit,
    String source = 'hosted',
    String version = '1.0.0',
  }) {
    final directory = 'cache/$name-$version';
    write('$directory/pubspec.yaml', 'name: $name\nversion: $version\n');
    if (license != null) write('$directory/LICENSE', license);
    locked[name] = {'source': source, 'version': version};
    roots[name] = '../$directory';
  }

  /// Writes the lockfile and package config. JSON is also YAML.
  void save() {
    write('pubspec.lock', jsonEncode({'packages': locked}));
    write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          for (final MapEntry(:key, :value) in roots.entries)
            {'name': key, 'rootUri': value, 'packageUri': 'lib/'},
        ],
      }),
    );
  }

  List<String> check() {
    save();
    return checkLicenses(root);
  }
}

void main() {
  group('identifyLicense', () {
    test('accepts the common permissive licenses', () {
      expect(identifyLicense(mit), 'MIT');
      expect(identifyLicense(bsd2), 'BSD-2-Clause');
      expect(identifyLicense(bsd3), 'BSD-3-Clause');
      expect(identifyLicense('$mit\n===\n\n$bsd3'), 'MIT AND BSD-3-Clause');
    });

    test('accepts the long licenses it knows by hash', () {
      final apache = licenseOf('clock');
      expect(identifyLicense(apache), 'Apache-2.0');
      final terms = apache.substring(0, apache.indexOf('APPENDIX:'));
      expect(identifyLicense(terms), 'Apache-2.0');
      expect(identifyLicense(File('LICENSE').readAsStringSync()), 'GPL-3.0');
    });

    // As in file_selector_android.
    test('accepts a part headed by the name of its component', () {
      expect(
        identifyLicense('$bsd3\n---\naFileChooser\n\n${licenseOf('clock')}'),
        'BSD-3-Clause AND Apache-2.0',
      );
      expect(
        identifyLicense('$mit\n---\naFileChooser\n$nonCommercial'),
        isNull,
      );
    });

    final rejected = {
      'an advertising clause': bsd4,
      'a non-commercial license': nonCommercial,
      'a proprietary license': proprietary,
      'an empty file': '',
      'only a copyright statement': 'Copyright 2020 Someone',
      'MIT with an added clause':
          '$mit\nCommons Clause: the Software may not be sold.',
      'MIT with an added clause in another script': '$mit\n禁止商业使用',
      'a restriction after the license, as a copyright line':
          '$mit\nCopyright 2020 Someone, non-commercial use only.',
      'a known license followed by an unknown one': '$mit\n---\n$nonCommercial',
    };
    for (final MapEntry(key: what, value: text) in rejected.entries) {
      test('rejects $what', () => expect(identifyLicense(text), isNull));
    }

    const restrictions = [
      'Copyright (c) 2024 Vendor. Redistribution is forbidden.',
      'Copyright (c) 2024 Vendor. Noncommercial purposes exclusively.',
      'Copyright 2024 Vendor. For evaluation purposes; resale is banned.',
      'Copyright (c) 2024 Vendor. Military applications are disallowed.',
      'Copyright 2024 Vendor, personal and educational purposes exclusively.',
      '(c) 2024 Vendor. A paid subscription is required after 30 days.',
    ];
    for (final line in restrictions) {
      test('rejects a restriction shaped like a copyright: $line', () {
        for (final text in [
          '$line\n$mit',
          '$mit\n$line',
          '$line\n---\n$mit',
          '$mit\n---\n$line',
          '$line\n$bsd3',
          '$line\n${licenseOf('clock')}',
          bsd3.replaceFirst('Google Inc.', line),
        ]) {
          expect(identifyLicense(text), isNull);
        }
      });
    }

    test('drops copyright statements only above the license', () {
      expect(identifyLicense('$mit\nCopyright 2020 Jane Doe'), isNull);
    });

    const statements = [
      'Copyright 2014, the Dart project authors. All rights reserved.',
      'Copyright (c) 2006-2026 Lukas Renggli.',
      'Copyright (c) 2000 - 2019 The Legion of the Bouncy Castle Inc. '
          '(https://www.bouncycastle.org)',
      'Copyright (c) 2020 maRci002, Gergely Padányi-Gulyás (fegyi001)',
      'Copyright (c) 2021 - 2025 André Sousa, 2025 Luka Stillingfleet '
          '(JaffaKetchup)',
      "Copyright (c) 2018-2026, the 'flutter_map' authors and maintainers",
      'Copyright (c) 2020 Ryan Heise and the project contributors.',
      'Copyright 2015 Michael Mitterer (office@mikemitterer.at),',
      '(c) 2018 湖北捷智云技术有限公司',
    ];
    for (final line in statements) {
      test('accepts the header: $line', () {
        expect(identifyLicense('$line\n\n$bsd2'), 'BSD-2-Clause');
      });
    }

    test('accepts the older Apache appendix placeholder', () {
      final apache = licenseOf('clock');
      final older = apache.replaceAll('[', '{').replaceAll(']', '}');
      expect(older, contains('Copyright {yyyy} {name of copyright owner}'));
      expect(identifyLicense(older), 'Apache-2.0');
    });

    test('rejects Apache-2.0 with text added after it', () {
      expect(
        identifyLicense('${licenseOf('clock')}\nNot for military use.'),
        isNull,
      );
    });
  });

  group('checkLicenses', () {
    test('passes compatible dependencies and unlicensed members', () {
      final workspace = Workspace()
        ..add('a')
        ..add('b', license: bsd3, source: 'git');
      expect(workspace.check(), isEmpty);
    });

    test('rejects an incompatible license in a transitive dependency', () {
      final workspace = Workspace()..add('deep', license: bsd4);
      expect(workspace.check(), [startsWith('deep: unrecognized license in ')]);
    });

    test('rejects a missing license', () {
      final workspace = Workspace()..add('bare', license: null);
      expect(workspace.check(), [startsWith('bare: no license file')]);
    });

    test('checks every license file of a package', () {
      final workspace = Workspace()..add('dual');
      workspace.write('cache/dual-1.0.0/COPYING.vendor', proprietary);
      expect(workspace.check(), [contains('COPYING.vendor')]);
    });

    test('checks path dependencies outside the workspace', () {
      final workspace = Workspace()
        ..add('local', license: null, source: 'path');
      expect(workspace.check(), [startsWith('local: no license file')]);
    });

    test('rejects an unknown dependency source', () {
      final workspace = Workspace()..add('odd', source: 'carrier-pigeon');
      expect(workspace.check(), [contains('unknown dependency source')]);
    });

    test('rejects a fetched package that is not locked', () {
      final workspace = Workspace()..add('extra');
      workspace.locked.remove('extra');
      expect(workspace.check(), [startsWith('extra: not in pubspec.lock')]);
    });

    test('rejects a locked package that is not fetched', () {
      final workspace = Workspace()..add('gone');
      workspace.roots.remove('gone');
      expect(workspace.check(), [startsWith('gone: locked but not fetched')]);
    });

    test('rejects a fetched version other than the locked one', () {
      final workspace = Workspace()..add('old');
      workspace.locked['old'] = {'source': 'hosted', 'version': '2.0.0'};
      expect(workspace.check(), [startsWith('old: pubspec.lock has 2.0.0')]);
    });

    test('fails when pub has not run', () {
      final workspace = Workspace();
      expect(checkLicenses(workspace.root), [contains('is missing')]);
    });

    test('takes the license of SDK packages from the SDK root', () {
      final workspace = Workspace();
      workspace
        ..write('sdk/LICENSE', bsd3)
        ..write('sdk/packages/flutter/pubspec.yaml', 'name: flutter\n');
      workspace.locked['flutter'] = {'source': 'sdk', 'description': 'flutter'};
      workspace.roots['flutter'] = '../sdk/packages/flutter';
      expect(workspace.check(), isEmpty);

      workspace.write('sdk/LICENSE', proprietary);
      expect(workspace.check(), [startsWith('flutter: unrecognized license')]);
    });

    test('rejects a proprietary SDK wrapper despite a free license', () {
      final workspace = Workspace()..add('firebase_core', license: bsd3);
      expect(workspace.check(), [contains('denied by name')]);
    });

    test('rejects Google Play services in a plugin Gradle file', () {
      final workspace = Workspace()..add('locator');
      // The string with "/*" must not be read as the start of a comment.
      workspace.write('cache/locator-1.0.0/android/build.gradle', '''
android { packagingOptions { exclude "**/*.so" } }
dependencies {
    implementation 'com.google.android.gms:play-services-location:21.0.0'
}
/* end */
''');
      expect(workspace.check(), [
        startsWith('locator: proprietary SDK com.google.android.gms in '),
      ]);
    });

    const coordinates = {
      'com.google.ads.interactivemedia.v3:interactivemedia': 'com.google.ads',
      'com.google.android.ads:mobile-ads-lite': 'com.google.android.ads',
      'com.google.android.ump:user-messaging-platform':
          'com.google.android.ump',
      'com.google.android.recaptcha:recaptcha': 'com.google.android.recaptcha',
      'com.google.ar:core': 'com.google.ar',
      'com.facebook.android:facebook-login': 'com.facebook.android',
      'com.unity3d.ads:unity-ads': 'com.unity3d.ads',
      'com.applovin:applovin-sdk': 'com.applovin',
    };
    for (final MapEntry(key: artifact, value: group) in coordinates.entries) {
      test('rejects the Maven artifact $artifact', () {
        final workspace = Workspace()..add('wrapper', license: bsd3);
        workspace.write(
          'cache/wrapper-1.0.0/android/build.gradle.kts',
          'dependencies { implementation("$artifact:1.0.0") }',
        );
        expect(workspace.check(), [
          startsWith('wrapper: proprietary SDK $group in '),
        ]);
      });
    }

    test('allows free libraries from the same vendors', () {
      final workspace = Workspace()..add('free');
      workspace.write('cache/free-1.0.0/android/build.gradle', '''
dependencies {
    implementation 'com.facebook.fresco:fresco:3.0.0'
    implementation 'com.google.android.material:material:1.0.0'
}
''');
      expect(workspace.check(), isEmpty);
    });

    test('rejects the Interactive Media Ads plugin by name', () {
      final workspace = Workspace()
        ..add('interactive_media_ads', license: bsd3);
      expect(workspace.check(), [contains('denied by name')]);
    });

    test('rejects a proprietary SDK added by our own Android project', () {
      final workspace = Workspace()
        ..write(
          'app/android/app/build.gradle.kts',
          'dependencies { implementation("com.google.firebase:firebase-x:1") }',
        );
      expect(workspace.check(), [
        startsWith('app: proprietary SDK com.google.firebase in '),
      ]);
    });

    test('ignores a proprietary SDK named only in a comment', () {
      final workspace = Workspace()..add('clean');
      workspace.write('cache/clean-1.0.0/android/build.gradle', '''
// No com.google.android.gms here.
/* nor com.google.firebase */
repositories { maven { url "https://example.org" } }
''');
      expect(workspace.check(), isEmpty);
    });
  });

  group('the command', () {
    Future<ProcessResult> run(Workspace workspace) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/check_licenses.dart', workspace.root.path],
    );

    test('exits 0 when every dependency is compatible', () async {
      final workspace = Workspace()
        ..add('a')
        ..save();
      final result = await run(workspace);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });

    test('exits 1 and names the package on a violation', () async {
      final workspace = Workspace()
        ..add('vendor_sdk', license: proprietary)
        ..save();
      final result = await run(workspace);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('vendor_sdk: unrecognized license'));
    });
  });
}
