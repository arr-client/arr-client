import 'dart:io';

import 'package:arr_client/app/platform/local_network.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_local_network/platform_local_network.dart';

const notRequired = LocalNetworkPermissionState.notRequired;
const granted = LocalNetworkPermissionState.granted;
const denied = LocalNetworkPermissionState.denied;

class FakePlatform implements LocalNetworkPlatform {
  LocalNetworkSnapshot value = snapshotWith();
  bool grantOnRequest = false;
  int requests = 0;

  @override
  Future<LocalNetworkSnapshot> snapshot() async => value;

  @override
  Future<bool> requestPermission() async {
    requests++;
    return grantOnRequest;
  }
}

LocalNetworkSnapshot snapshotWith({
  bool granted = false,
  List<NetworkRoute>? lanRoutes = const [],
  List<NetworkRoute> vpnRoutes = const [],
}) => LocalNetworkSnapshot(
  granted: granted,
  lanRoutes: lanRoutes,
  vpnRoutes: vpnRoutes,
);

NetworkRoute route(String cidr, {bool excluded = false}) {
  final [address, length] = cidr.split('/');
  return NetworkRoute(
    InternetAddress(address).rawAddress,
    int.parse(length),
    excluded: excluded,
  );
}

void main() {
  late FakePlatform platform;
  late Map<String, List<String>> names;
  late List<String> looked;
  late DeviceLocalNetworkPermission permission;

  setUp(() {
    platform = FakePlatform();
    names = {};
    looked = [];
    permission = DeviceLocalNetworkPermission(
      platform: platform,
      lookup: (host) async {
        looked.add(host);
        final addresses = names[host];
        if (addresses == null) throw const SocketException('not found');
        return [for (final address in addresses) InternetAddress(address)];
      },
    );
  });

  group('classifies the address', () {
    const local = [
      '10.0.0.0',
      '10.255.255.255',
      '172.16.0.0',
      '172.31.255.255',
      '192.168.0.0',
      '192.168.255.255',
      '169.254.0.1',
      '100.64.0.0',
      '100.127.255.255',
      '224.0.0.251',
      '239.255.255.250',
      '255.255.255.255',
      'fe80::1',
      'febf::1',
      'ff02::fb',
      '::ffff:192.168.1.10',
    ];
    const notLocal = [
      '9.255.255.255',
      '11.0.0.0',
      '172.15.255.255',
      '172.32.0.0',
      '192.167.255.255',
      '192.169.0.0',
      '169.253.255.255',
      '169.255.0.0',
      '100.63.255.255',
      '100.128.0.0',
      '223.255.255.255',
      '240.0.0.1',
      '8.8.8.8',
      '127.0.0.1',
      '::1',
      'fec0::1',
      // Private, but local only when a route says so.
      'fd12:3456::1',
      '2001:db8::1',
      '::ffff:8.8.8.8',
    ];

    for (final address in local) {
      test('$address as local', () async {
        expect(await permission.status(address), denied);
        expect(looked, isEmpty);
      });
    }

    for (final address in notLocal) {
      test('$address as not local', () async {
        expect(await permission.status(address), notRequired);
        expect(looked, isEmpty);
      });
    }
  });

  group('IPv6 routes of the local network', () {
    setUp(() {
      platform.value = snapshotWith(
        lanRoutes: [
          route('::/0'),
          route('0.0.0.0/0'),
          route('2001:db8:1::/64'),
          route('fd00:2::/48'),
          route('192.0.2.0/24'),
        ],
      );
    });

    test('make a directly connected address local', () async {
      expect(await permission.status('2001:db8:1::5'), denied);
    });

    test('make an address of a further subnet local', () async {
      expect(await permission.status('fd00:2:0:9::1'), denied);
    });

    test('leave the rest to the default route', () async {
      expect(await permission.status('2001:db8:2::5'), notRequired);
    });

    test('add nothing to the IPv4 ranges', () async {
      expect(await permission.status('192.0.2.5'), notRequired);
    });
  });

  group('classifies the host name', () {
    test('ending in .local without resolving it', () async {
      for (final host in ['nas.local', 'NAS.Local', 'nas.local.']) {
        expect(await permission.status(host), denied, reason: host);
      }
      expect(looked, isEmpty);
    });

    test('that only contains .local by its addresses', () async {
      names['nas.local.example.org'] = ['203.0.113.5'];

      expect(await permission.status('nas.local.example.org'), notRequired);
    });

    test('as local when any address is', () async {
      names['media.example.org'] = ['203.0.113.5', '192.168.1.5'];

      expect(await permission.status('media.example.org'), denied);
    });

    test('as not local when no address is', () async {
      names['media.example.org'] = ['203.0.113.5', '2001:db8::1'];

      expect(await permission.status('media.example.org'), notRequired);
    });

    test('that does not resolve as needing nothing', () async {
      expect(await permission.status('nowhere.example.org'), notRequired);
      expect(looked, ['nowhere.example.org']);
    });
  });

  test('accepts an IPv6 address in brackets or with a zone', () async {
    for (final host in ['[fe80::1]', 'fe80::1%wlan0', '[fe80::1%25wlan0]']) {
      expect(await permission.status(host), denied, reason: host);
    }
    expect(looked, isEmpty);
  });

  group('needs nothing', () {
    test('before Android 17', () async {
      platform.value = const LocalNetworkSnapshot.notEnforced();

      expect(await permission.status('192.168.1.10'), notRequired);
      expect(await permission.request('nas.local'), notRequired);
      expect(platform.requests, 0);
    });

    test('without Wi-Fi or Ethernet', () async {
      platform.value = snapshotWith(lanRoutes: null);

      expect(await permission.status('192.168.1.10'), notRequired);
      expect(await permission.status('nas.local'), notRequired);
      expect(await permission.status('media.example.org'), notRequired);
      expect(looked, isEmpty);
    });
  });

  group('with a VPN', () {
    test('needs nothing for what the tunnel carries', () async {
      platform.value = snapshotWith(vpnRoutes: [route('0.0.0.0/0')]);

      expect(await permission.status('192.168.1.10'), notRequired);
    });

    test('applies to what a split tunnel leaves out', () async {
      platform.value = snapshotWith(vpnRoutes: [route('100.64.0.0/10')]);

      expect(await permission.status('100.100.1.1'), notRequired);
      expect(await permission.status('192.168.1.10'), denied);
    });

    test('applies to a route excluded from a full tunnel', () async {
      platform.value = snapshotWith(
        vpnRoutes: [
          route('0.0.0.0/0'),
          route('192.168.0.0/16', excluded: true),
        ],
      );

      expect(await permission.status('192.168.1.10'), denied);
      expect(await permission.status('10.0.0.1'), notRequired);
    });
  });

  group('status', () {
    test('says granted for a local host with the permission', () async {
      platform.value = snapshotWith(granted: true);

      expect(await permission.status('192.168.1.10'), granted);
    });

    test('says notRequired for a remote host with the permission', () async {
      platform.value = snapshotWith(granted: true);

      expect(await permission.status('8.8.8.8'), notRequired);
    });

    test('never prompts', () async {
      await permission.status('192.168.1.10');

      expect(platform.requests, 0);
    });
  });

  group('request', () {
    test('prompts when needed and reports a grant', () async {
      platform.grantOnRequest = true;

      expect(await permission.request('192.168.1.10'), granted);
      expect(platform.requests, 1);
    });

    test('reports a refusal', () async {
      expect(await permission.request('192.168.1.10'), denied);
      expect(platform.requests, 1);
    });

    test('does not prompt when already granted', () async {
      platform.value = snapshotWith(granted: true);

      expect(await permission.request('192.168.1.10'), granted);
      expect(platform.requests, 0);
    });

    test('does not prompt for a remote host', () async {
      expect(await permission.request('8.8.8.8'), notRequired);
      expect(platform.requests, 0);
    });
  });
}
