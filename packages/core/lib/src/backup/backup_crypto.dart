/// The encryption of an export with credentials (contracts/backup-format.md):
/// Argon2id and AES-256-GCM.
///
/// Both run in another isolate, as the key derivation takes long on purpose.
/// These are top-level functions so that what is sent there is only what is
/// named here.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// What an export is written with.
const exportMemoryKiB = 65536;

/// What an export is written with.
const exportIterations = 3;

/// The most an import derives with, so that a file cannot exhaust memory.
const maximumMemoryKiB = 131072;

/// The least Argon2 allows for one lane.
const minimumMemoryKiB = 8;

/// The most an import derives with, so that a file cannot take for ever.
const maximumIterations = 10;

/// The bytes of a salt.
const saltLength = 16;

/// The bytes of a nonce.
const nonceLength = 12;

const _tagLength = 16;

// The format and version of the envelope, authenticated with the data.
const _associatedData = 'arr-client-setup:1';

/// [clear] encrypted, with the authentication tag appended.
Future<Uint8List> seal(
  Uint8List clear, {
  required String passphrase,
  required Uint8List salt,
  required Uint8List nonce,
}) => Isolate.run(() async {
  final box = await DartAesGcm.with256bits().encrypt(
    clear,
    secretKey: await _key(passphrase, salt, exportMemoryKiB, exportIterations),
    nonce: nonce,
    aad: utf8.encode(_associatedData),
  );
  return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
});

/// What [sealed] holds, or null if the passphrase is wrong or any of the input
/// was changed. The parameters must be within the limits above.
Future<Uint8List?> open(
  Uint8List sealed, {
  required String passphrase,
  required Uint8List salt,
  required Uint8List nonce,
  required int memoryKiB,
  required int iterations,
}) async {
  if (sealed.length < _tagLength) return null;
  return Isolate.run(() async {
    final end = sealed.length - _tagLength;
    try {
      final clear = await DartAesGcm.with256bits().decrypt(
        SecretBox(
          Uint8List.sublistView(sealed, 0, end),
          nonce: nonce,
          mac: Mac(Uint8List.sublistView(sealed, end)),
        ),
        secretKey: await _key(passphrase, salt, memoryKiB, iterations),
        aad: utf8.encode(_associatedData),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      return null;
    }
  });
}

Future<SecretKey> _key(
  String passphrase,
  Uint8List salt,
  int memoryKiB,
  int iterations,
) async {
  // In this isolate alone: with isolates of its own the package gives up on a
  // slow device after a fixed time.
  final state = DartArgon2id(
    memory: memoryKiB,
    iterations: iterations,
    parallelism: 1,
    hashLength: 32,
    maxIsolates: 0,
    blocksPerProcessingChunk: -1,
  ).newState();
  // Not `deriveKey`, which takes the passphrase as a `SecretKey`: that cannot
  // be empty, and a wrong passphrase may be.
  return SecretKey(
    await state.deriveKeyBytes(password: utf8.encode(passphrase), nonce: salt),
  );
}
