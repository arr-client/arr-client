/// Certificates of the fake HTTPS servers, for 127.0.0.1. Test material only:
/// copies of packages/core/test/network/certs, whose keys are public and trusted
/// by nothing. A test on a device cannot read the repository's files.
library;

/// A certificate and its key, in PEM, and its SHA-256 fingerprint as the app
/// stores it.
typedef TestCertificate = ({String chain, String key, String sha256});

/// A self-signed certificate (self_signed.pem).
const TestCertificate selfSigned = (
  sha256: 'bfdcef9e5018ee2c03c2ee622ed9deea2e37e5a058ea2d17360842fcd7ab61e7',
  chain: '''
-----BEGIN CERTIFICATE-----
MIIBnzCCAUWgAwIBAgIUAIA7VvddJuNIaeTDHDARbr9kJ1gwCgYIKoZIzj0EAwIw
FjEUMBIGA1UEAwwLc2VsZl9zaWduZWQwIBcNMjUwMTAxMDAwMDAwWhgPMjEyNTAx
MDEwMDAwMDBaMBYxFDASBgNVBAMMC3NlbGZfc2lnbmVkMFkwEwYHKoZIzj0CAQYI
KoZIzj0DAQcDQgAEX+tsDLsqzW7CznRyBtiJJ7+OFqttT2cl0bwMYRXyV7oDKtu1
Ca/z7mgMRVLGBgSsUSWQAWsEDmffXfZeEHSftKNvMG0wHQYDVR0OBBYEFEoRCcml
ER29VZLa6JejVVyGQxVbMB8GA1UdIwQYMBaAFEoRCcmlER29VZLa6JejVVyGQxVb
MA8GA1UdEwEB/wQFMAMBAf8wGgYDVR0RBBMwEYcEfwAAAYIJbG9jYWxob3N0MAoG
CCqGSM49BAMCA0gAMEUCIQDpNEEViKWEt2hHnDWyFZ0gIlowe2Q7Qyil5cSqP6gg
7gIgT0lqczE5sp+BFGvlqyfw6+HO9Dnwm2xSyNfOOyQCxoI=
-----END CERTIFICATE-----
''',
  key: '''
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIB/DbLzZVRWA0lhY8XXSEiJANESgE/ilnty82P0iCzeVoAoGCCqGSM49
AwEHoUQDQgAEX+tsDLsqzW7CznRyBtiJJ7+OFqttT2cl0bwMYRXyV7oDKtu1Ca/z
7mgMRVLGBgSsUSWQAWsEDmffXfZeEHSftA==
-----END EC PRIVATE KEY-----
''',
);

/// Another one, as after a server was reinstalled (self_signed_other.pem).
const TestCertificate otherSelfSigned = (
  sha256: '7818468aa9633e86d39a16622cf821fcaf2778814bcddd005a9caede48097ea5',
  chain: '''
-----BEGIN CERTIFICATE-----
MIIBrDCCAVGgAwIBAgIUHSB0ZuXVtmx9f48S1VY5OP0qTxEwCgYIKoZIzj0EAwIw
HDEaMBgGA1UEAwwRc2VsZl9zaWduZWRfb3RoZXIwIBcNMjUwMTAxMDAwMDAwWhgP
MjEyNTAxMDEwMDAwMDBaMBwxGjAYBgNVBAMMEXNlbGZfc2lnbmVkX290aGVyMFkw
EwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEpXoQdk0ukHzXI2OGQD5ZftsF4H0AohFT
vHK/BKcmgFkCm4+GCxj2C6XTm/6zvYXBEI7ZUJCvDDLPNS0ERTJ8RaNvMG0wHQYD
VR0OBBYEFFXhYii7O2DbDztl+Bo6bJ7bdds5MB8GA1UdIwQYMBaAFFXhYii7O2Db
Dztl+Bo6bJ7bdds5MA8GA1UdEwEB/wQFMAMBAf8wGgYDVR0RBBMwEYcEfwAAAYIJ
bG9jYWxob3N0MAoGCCqGSM49BAMCA0kAMEYCIQCI5UCcCWwa/OOuU+ERIdEbhXDe
XVR9fJ6GTM+2cqfpuAIhAJFg8VxUbXDhYR3/+4c2RS1cAJR1ws6GnsrW4VBFoIEw
-----END CERTIFICATE-----
''',
  key: '''
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIEmNyvkfT28whXu/yXK1xMp+wca3PV5hQ8WMr8aHPWb9oAoGCCqGSM49
AwEHoUQDQgAEpXoQdk0ukHzXI2OGQD5ZftsF4H0AohFTvHK/BKcmgFkCm4+GCxj2
C6XTm/6zvYXBEI7ZUJCvDDLPNS0ERTJ8RQ==
-----END EC PRIVATE KEY-----
''',
);
