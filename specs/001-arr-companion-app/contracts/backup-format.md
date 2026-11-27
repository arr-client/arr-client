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

- `createdAt` and the dates of records are ISO 8601, written in UTC.
- Without credentials: `encrypted` is false; payload holds no credential fields, custom headers or
  cookies. An unencrypted file with a `credential` is refused.
- Decrypted or plain `payload` schema: `profiles[]` are Profile records; `instances[]` are Instance
  fields (data-model names, including `profileId`; no `lastProbe`, `detectedVersion`,
  `unsupportedVersion` or `authFailed`, which are ignored if present), each with,
  in encrypted exports only, `credential`:
  `{apiKey?, username?, password?, basicUser?, basicPassword?, customHeaders?}`; `preferences` is
  Preferences without `activeProfileId` and `appLock`; `subscriptions[]` are
  NotificationSubscription records. All profiles are exported.
- With credentials: `encrypted` is true and `payload` is replaced by
  `{"kdf":{"name":"argon2id","salt":b64,"memoryKiB":65536,"iterations":3,"parallelism":1},
  "cipher":"aes-256-gcm","nonce":b64,"data":b64}`. The authentication tag is appended to `data`;
  `format` and `version` are authenticated as associated data. Passphrase minimum 10 characters.
- Encryption, exactly: the associated data is the UTF-8 text `arr-client-setup:1`; the passphrase is
  its UTF-8 bytes, without Unicode normalisation, and its length is counted in code points; the key
  is 32 bytes; the tag is the last 16 bytes of `data`; the salt is 16 and the nonce 12 random bytes,
  new at each export; base64 is the standard alphabet with padding. Argon2id is version 1.3, without
  secret or associated data. The encrypted text is the UTF-8 JSON of the plain `payload`.
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
- Also rejected: a kdf other than `argon2id` or cipher other than `aes-256-gcm`, memoryKiB under 8
  and iterations under 1. All of these are checked before a key is derived. Key derivation and
  decryption run off the UI isolate.
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
- Notification markers are initialized as for a new subscription (data-model EventMarker): the
  markers of every imported instance are removed, and a subscription without one takes its baseline
  before it notifies.

## Records

`payload`, `profiles`, `instances`, `preferences` and `subscriptions` are required. Unknown fields are
ignored. One record that breaks a rule refuses the whole file.

- Profile: `id`, `name`, `sortOrder`.
- Instance: `id`, `profileId`, `name`, `serviceType`, `url`, `authKind`, `enabled`, `sortOrder`,
  `links` (`{type, instanceId}`), `createdAt`; optionally `certPin`, `customCa`, `credential`. An
  export also writes `updatedAt`, which an import does not read.
- `id` is a lower-case UUID, unique among the file's profiles or instances. `sortOrder` is from 0 to
  2147483647.
- `serviceType` is a registered module and `authKind` one that the add form offers for it.
- `certPin` is 64 lower-case hexadecimal digits. `customCa` is at most 64 KiB and is read as a
  hand-imported authority is: only its certificates are kept, and a private key refuses it.
- Links are those of data-model.md, to an instance of the same profile in the file.
- In `credential`, every value is text, header names are valid, and basic auth is not combined with
  an API key that uses `Authorization`. A `sessionCookie` is ignored. A credential with nothing in it
  is the same as none.
- Subscription: `instanceId` (an instance of the file), `eventType`, `enabled`; one per pair.
- `preferences`: `themeMode`, `trueBlack`, `dynamicColor`, `loadThirdPartyArtwork`, and optionally
  `view`, as `{profileId: {library: {layout, sort: {field, ascending}, filters: {text, states,
  monitored, qualityProfiles, tags}, instanceScope?}}}` with option ids as `[instanceId, optionId]`,
  and `lastAddChoices`, as `{instanceId: {rootFolderId, qualityProfileId, monitorOptionId,
  searchNow, metadataProfileId, tagIds, seriesType, seasonFolder, minimumAvailability}}`. A setting
  that the file does not name (or gives as null) stays as it is; one of the wrong type refuses the
  file. Inside `sort`, `filters` and add choices, unknown values are dropped as when read from the
  database. Ids of instances that are not in the view's profile in the file are dropped.

## Export

- An export leaves nothing out. If a saved instance, view or credential cannot be read, if a record
  would be refused by an import (for example of a module that is no longer registered), if the secret
  store fails (with credentials) or if the file would be over 1 MiB, there is no file. Event types
  that this version does not know are the one exception.

## Applying an import

- All of it or nothing: records change in one database transaction, and secrets that were written or
  deleted are put back if anything fails, as far as the store allows. If what the preview rests on
  has changed since (names, addresses, trust, settings, or an edit of a replaced instance), the import
  is refused and must be previewed again.
- A file that would move an existing instance `id` to another profile or change its service is
  refused.
- Records that are replaced keep their position. New ones follow those saved, in the order of their
  `sortOrder` in the file.
- Names are in use if a record that stays has them, or one named earlier in the import, so replaced
  records may swap names. A record keeping its name has the first claim, then other replacements,
  then new records. The suffix is a space and a number in parentheses.
- A replaced instance takes `url`, `authKind`, `enabled`, `links`, `createdAt` and `customCa` from
  the file; without `customCa` the stored authority is removed. A `certPin` in the file replaces the
  stored one; without one, the stored pin stays while the origin does. `lastProbe` stays,
  `detectedVersion` and `unsupportedVersion` are cleared if the url changes.
- Its subscriptions become exactly those of the file. Its views and last add choices change only
  where the file has them; these are not listed in the preview.
- `updatedAt` of every imported instance is set anew, later than before, so that it gets a new
  session and is probed.
- Credentials: one that the file carries replaces the stored one as a whole. The session is kept only
  if origin, `authKind` and what the user enters stay the same; a changed `authKind` alone drops it.
- `authFailed` is cleared only by a credential that differs from the stored one. The same credential,
  or dropping the secrets for a new origin, leaves it set.
- A replacement that makes basic auth stored on the device share a header with the API key, with no
  credential in the file and the same origin, is refused.
- A new instance gets the file's credential or none: a secret still stored under its `id`, left by a
  deleted instance, is erased or overwritten as part of the import.
