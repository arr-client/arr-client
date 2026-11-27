import 'package:arr_client/features/onboarding/address.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

String? parsed(String text) => switch (parseAddress(text)) {
  Ok(:final value) => value.toString(),
  Err() => null,
};

AddressProblem? problem(String text) => switch (parseAddress(text)) {
  Ok() => null,
  Err(:final error) => error,
};

void main() {
  test('takes http and https, with ports and sub-paths', () {
    expect(parsed('http://nas:7878'), 'http://nas:7878');
    expect(parsed('https://media.test/radarr'), 'https://media.test/radarr');
    expect(parsed('http://[fd00::2]:7878'), 'http://[fd00::2]:7878');
  });

  test('puts https before an address that names no scheme', () {
    expect(parsed('192.168.1.10:7878'), 'https://192.168.1.10:7878');
    expect(parsed('localhost:7878/radarr'), 'https://localhost:7878/radarr');
    expect(parsed('radarr.local'), 'https://radarr.local');
    // The default port of https is not written out; another one is kept.
    expect(parsed('nas:443'), 'https://nas');
    expect(parsed('nas:80'), 'https://nas:80');
  });

  test('drops spaces around it and slashes at its end', () {
    expect(parsed('  http://nas:7878/ '), 'http://nas:7878');
    expect(parsed('https://nas/radarr//'), 'https://nas/radarr');
  });

  // Without this the host would be "http" or "https", over plain http, and
  // the key would go to whatever has that name.
  test('refuses a mistyped scheme instead of reading it as a host', () {
    for (final text in [
      'https:/nas:7878',
      'https//nas',
      r'https:\\nas',
      r'https:\nas',
      r'https\\nas',
      'https/nas',
      'http:/192.168.1.10:7878',
      'HTTP//nas',
      'Https:/nas',
    ]) {
      expect(problem(text), AddressProblem.invalid, reason: text);
    }
  });

  test('keeps a host whose name only begins like a scheme', () {
    expect(parsed('httpbin.test'), 'https://httpbin.test');
    expect(parsed('https-proxy:8443'), 'https://https-proxy:8443');
    expect(parsed('http:7878'), 'https://http:7878');
    expect(parsed('https'), 'https://https');
  });

  test('says what is wrong', () {
    expect(problem('   '), AddressProblem.missing);
    expect(problem('ftp://nas'), AddressProblem.invalid);
    expect(problem('http://'), AddressProblem.invalid);
    expect(problem('my server'), AddressProblem.invalid);
    expect(problem('http://nas:99999'), AddressProblem.invalid);
    expect(problem('http://nas:port'), AddressProblem.invalid);
    expect(problem('http://me:secret@nas'), AddressProblem.userInfo);
    expect(problem('http://nas/login?next=1'), AddressProblem.queryOrFragment);
    expect(problem('http://nas/#/movies'), AddressProblem.queryOrFragment);
  });
}
