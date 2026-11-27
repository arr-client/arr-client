"""Writes golden_v1.arrclient.json to standard output.

The file is made with argon2-cffi and Python's cryptography, so that the app's
packages are not their own judge. Salt and nonce are fixed, which no export of
the app may do, so that the output is the same each time:

    nix-shell -p 'python3.withPackages (ps: [ ps.argon2-cffi ps.cryptography ])' \
        --run 'python3 -I golden_v1.py' | diff - golden_v1.arrclient.json

A change of the format needs a new golden file; this one stays, as version 1
files must go on being read.
"""

import base64
import json

from argon2.low_level import Type, hash_secret_raw
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

PASSPHRASE = "correct horse bättery"
SALT = bytes(range(16))
NONCE = bytes(range(100, 112))
PROFILE = "11111111-1111-4111-8111-111111111111"
INSTANCE = "22222222-2222-4222-8222-222222222222"
DATE = "2026-01-02T00:00:00.000Z"

payload = {
    "profiles": [{"id": PROFILE, "name": "Golden", "sortOrder": 0}],
    "instances": [
        {
            "id": INSTANCE,
            "profileId": PROFILE,
            "name": "Movies",
            "serviceType": "radarr",
            "url": "https://nas.test:7878/radarr",
            "authKind": "apiKey",
            "enabled": True,
            "sortOrder": 0,
            "links": [],
            "createdAt": DATE,
            "updatedAt": DATE,
            "credential": {
                "apiKey": "zq-golden-key",
                "customHeaders": {"X-Proxy-Id": "zq-golden-header"},
            },
        }
    ],
    "preferences": {
        "themeMode": "dark",
        "trueBlack": True,
        "dynamicColor": False,
        "loadThirdPartyArtwork": False,
    },
    "subscriptions": [
        {"instanceId": INSTANCE, "eventType": "imported", "enabled": True}
    ],
}

key = hash_secret_raw(
    PASSPHRASE.encode(),
    SALT,
    time_cost=3,
    memory_cost=65536,
    parallelism=1,
    hash_len=32,
    type=Type.ID,
    version=19,
)
# The tag is appended to the data.
data = AESGCM(key).encrypt(NONCE, json.dumps(payload).encode(), b"arr-client-setup:1")


def b64(value):
    return base64.b64encode(value).decode()


print(
    json.dumps(
        {
            "format": "arr-client-setup",
            "version": 1,
            "createdAt": "2026-01-02T00:00:00Z",
            "encrypted": True,
            "payload": {
                "kdf": {
                    "name": "argon2id",
                    "salt": b64(SALT),
                    "memoryKiB": 65536,
                    "iterations": 3,
                    "parallelism": 1,
                },
                "cipher": "aes-256-gcm",
                "nonce": b64(NONCE),
                "data": b64(data),
            },
        },
        indent=2,
    )
)
