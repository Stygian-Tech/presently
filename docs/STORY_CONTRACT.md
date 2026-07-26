# Flashes story contract

Presently targets the lexicon currently published by the Flashes authority:

```text
authority DID: did:plc:24kqkpfy6z7avtgu3qg57vvl
collection:    blue.flashes.story.post
schema CID:    bafyreidiqimfagsklhh7ot3q3hyakpeqt6duumja3mjxaflip243n4jlzq
observed:      2026-07-25
```

The older `app.flashes.story` collection exists in repositories but is not the
target for new records.

## Minimal record

```json
{
  "$type": "blue.flashes.story.post",
  "image": {
    "$type": "blob",
    "ref": {
      "$link": "<CID returned by com.atproto.repo.uploadBlob>"
    },
    "mimeType": "image/jpeg",
    "size": 123456
  },
  "createdAt": "2026-07-26T02:00:00.000Z",
  "expiresInMinutes": 1440
}
```

Schema constraints:

- `image` and `createdAt` are required.
- Images may be JPEG, PNG, or WebP and must be at most 10,485,760 bytes.
- `expiresInMinutes` is optional, defaults to 1,440, and permits 1 through
  10,080 minutes.
- `text` and rich-text `facets` are optional and intentionally omitted by the
  MVP.
- The record key type is `tid`.

## Publishing sequence

1. POST JPEG bytes to `/xrpc/com.atproto.repo.uploadBlob`.
2. Preserve the returned blob object exactly.
3. POST `com.atproto.repo.createRecord` with:
   - `repo`: authenticated account DID
   - `collection`: `blue.flashes.story.post`
   - `record`: the minimal record above
4. Persist the returned `uri` and `cid`.

Both authenticated calls require an access token bound to a valid DPoP proof.
