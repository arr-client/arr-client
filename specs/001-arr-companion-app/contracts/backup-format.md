# Contract: Setup Export (version 1)

File extension `.arrclient.json`, UTF-8 JSON.

```json
{
  "format": "arr-client-setup",
  "version": 1,
  "createdAt": "2026-11-26T00:00:00Z",
  "encrypted": false,
  "payload": { "profiles": [], "instances": [], "preferences": {}, "subscriptions": [] }
}
```

- Without credentials: `encrypted` is false; payload holds no credential fields, custom headers or
  cookies.
- Decrypted or plain `payload` schema: `profiles[]` are Profile records; `instances[]` are Instance
  fields (data-model names, including `profileId`; no `lastProbe`, `detectedVersion` or `authFailed`, which are ignored if present), each with,
  in encrypted exports only, `credential`:
  `{apiKey?, username?, password?, basicUser?, basicPassword?, customHeaders?}`; `preferences` is
  Preferences without `activeProfileId` and `appLock`; `subscriptions[]` are
  NotificationSubscription records. All profiles are exported.
- With credentials: `encrypted` is true and `payload` is replaced by
  `{"kdf":{"name":"argon2id","salt":b64,"memoryKiB":65536,"iterations":3,"parallelism":1},
  "cipher":"aes-256-gcm","nonce":b64,"data":b64}`. The authentication tag is appended to `data`;
  `format` and `version` are authenticated as associated data. Passphrase minimum 10 characters.
- Session cookies and event markers are never exported.
- `preferences.appLock` and `preferences.activeProfileId` are ignored if present in an imported
  file; each is set on the device. The active profile does not change on import, except that on a
  fresh install whose only profile is empty, the empty profile is removed and the first imported one
  becomes active.
- Imported preferences replace the current ones. The preview says so and lists each setting that
  would change, including third-party artwork loading, before the user confirms.
- Certificate pins and custom CA certificates are exported, and are listed in the import preview.
- Import rejects unknown `format` or newer `version`, files over 1 MiB, and kdf parameters above
  memoryKiB 131072 or iterations 10, parallelism other than 1, a salt other than 16 bytes or a nonce
  other than 12 bytes. Records are validated by the same rules as manual entry.
- Profiles and instances match on `id`: the preview shows add or replace and every address change;
  nothing changes before confirmation. Local profiles and instances absent from the file are kept.
- A replacement that changes an instance's origin and carries no credential deletes the stored
  secrets, session and certificate pin for it, since the user did not type that address. A credential
  carried by the file and accepted in the preview, which shows the new address, is used. Replacing an
  instance's credentials clears `authFailed`.
- A different `id` with a name already in use (profile names; instance names within a profile) gets
  a numbered suffix, shown in the preview; the base name is shortened so the result stays within 40
  characters. On a fresh install, the empty profile that is going to be removed is ignored when
  checking for collisions, so restoring "Default" keeps its name.
- Every instance must reference a profile in the file.
- Notification markers are initialized as for a new subscription (data-model EventMarker).
