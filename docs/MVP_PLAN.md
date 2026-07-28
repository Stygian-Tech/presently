# Presently MVP plan

## Product question

Will people use a dedicated, distraction-free camera to share a fleeting photo
to their existing AT Protocol identity and social graph?

The proof of concept should validate the act of sharing. It does not need to
validate browsing, engagement, group moments, or event discovery.

## MVP user journey

1. Launch Presently directly into a full-screen camera.
2. If signed out, connect an AT Protocol account through the system browser.
3. Capture one still photo.
4. Review, retake, and choose whether to save a copy to the device library.
5. Tap **Post story**.
6. Presently uploads one JPEG blob to the signed-in account's PDS.
7. Presently creates a `blue.flashes.story.post` record with a 24-hour expiry.
8. The app confirms the returned AT URI and returns to the camera.

The story is public repository data. "Ephemeral" means Flashes stops displaying
it after the declared duration; it is not a promise of immediate physical
deletion from every copy of the network.

## Technical boundaries

### Included

- iOS 17+ SwiftUI app using AVFoundation and SwiftData.
- Android 23+ Jetpack Compose app using CameraX and Room.
- Native public-client AT Protocol OAuth with PKCE, PAR, DPoP, and secure token
  storage on each platform.
- A small Go HTTP service deployed from `Dockerfile.vercel` that publishes the
  OAuth client metadata document.
- JPEG output, under the schema's 10 MiB maximum.
- Local pending/failed draft persistence and safe retry.
- Optional save to Photos/MediaStore.
- Exact Flashes `blue.flashes.story.post` compatibility.

### Excluded

- Feed, story viewer, replies, reactions, view counts, notifications.
- Video, multiple images, text overlays, facets, filters, editing.
- Events, RSVP discovery, GPS, group moments, or a Presently lexicon.
- A backend that stores user access or refresh tokens.
- Claiming network deletion when the record's display window expires.

## Architecture

```text
Camera UI
   |
   v
Local draft (SwiftData / Room)
   |
   v
Native OAuth session (Keychain / Android Keystore)
   |
   +--> uploadBlob (JPEG)
   |
   +--> createRecord (blue.flashes.story.post)
   |
   v
Published AT URI or retryable failure

Vercel Go container --> stable public OAuth client metadata only
```

Each mobile app owns its OAuth tokens and DPoP keys. The Vercel deployment is
not an auth proxy and never receives account credentials.

## Delivery slices

### Slice 0 — repository foundation (this scaffold)

- Monorepo, platform projects, worker, story contract, and build instructions.
- Native camera/review UI.
- SwiftData/Room pending draft model.
- Exact story record factory and unit coverage.
- Go OAuth metadata endpoint, container definition, and endpoint tests.

Exit: all three projects build; contract tests agree on the collection,
required fields, expiry, MIME type, and size limit.

### Slice 1 — native OAuth

- Resolve handles and authorization server metadata.
- Implement system-browser authorization with PKCE and PAR.
- Generate per-session DPoP keys in Keychain/Android Keystore.
- Persist and refresh tokens securely.
- Verify callback state, issuer, and token `sub`.
- Add sign-out and terminal-session recovery.

Exit: users on both Bluesky-hosted and independent PDS accounts can sign in,
restart the app, refresh a session, and sign out.

### Slice 2 — publish vertical

- Normalize orientation and encode a bounded JPEG.
- Upload with `com.atproto.repo.uploadBlob`.
- Create a TID-keyed `blue.flashes.story.post`.
- Persist pending/failed/published state and returned AT URI.
- Retry idempotently: do not create duplicate records after an ambiguous
  response.

Exit: a photo created on each platform appears as a story in the current
Flashes client and expires from its story UI after 24 hours.

### Slice 3 — device hardening

- Permission denial/recovery UI.
- Offline capture and later retry.
- Background/foreground camera lifecycle.
- Storage pressure, 10 MiB limit, slow upload, token expiry, and PDS errors.
- Accessibility labels, Dynamic Type, TalkBack, and screen-reader focus.
- Physical-device camera and photo-library verification.

Exit: deterministic automated coverage plus a signed device test checklist for
iOS and Android.

### Slice 4 — small-cohort beta

- Privacy disclosure explaining public records and expiration semantics.
- Terms/support pages linked from OAuth metadata.
- App Store/TestFlight and Play internal testing builds.
- Minimal privacy-safe diagnostics for capture, upload, and create-record
  outcomes; never upload photos or tokens as telemetry.

Exit: a small invited cohort can complete the loop and the team can measure
capture-to-publish completion without introducing a feed.

## Acceptance criteria

- App launch reaches a usable camera in one interaction after permission is
  granted.
- A user can always retake before any network mutation.
- Saving to the device is opt-in and its failure does not silently block post.
- Posting uses only:
  `atproto repo:blue.flashes.actor.profile?action=create
  repo:blue.flashes.story.post?action=create blob:image/jpeg`.
- Record `$type` and collection both equal `blue.flashes.story.post`.
- `image` is the exact blob object returned by the PDS.
- `createdAt` is UTC RFC 3339 and `expiresInMinutes` is `1440`.
- Images above 10 MiB are recompressed or rejected before record creation.
- The UI does not report success until `createRecord` returns an AT URI.
- Failed drafts survive process death and expose retry/discard controls.
- No OAuth tokens, DPoP private keys, or captured images reach the Vercel
  metadata service.

## Decisions still needed before Slice 1

These are genuine product/deployment decisions and should be locked before the
OAuth implementation:

1. Stable production origin for the OAuth `client_id`.
2. Final Apple bundle ID and Android application ID. The scaffold uses
   `tech.stygian.presently`.
3. One shared native client metadata document or distinct iOS and Android
   client IDs. The scaffold uses one shared document and callback scheme.
4. Whether a successful publish immediately deletes the local draft image or
   retains a short retry/history entry without image data.
5. Exact copy for explaining that a 24-hour story is publicly replicated data,
   not guaranteed erasure.
