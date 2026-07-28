# Presently

Presently is a camera-first AT Protocol client for sharing a photo as a
24-hour story that Flashes can display. The MVP intentionally has no feed: it
opens to the camera, captures one JPEG, optionally saves it to the device photo
library, and publishes a `blue.flashes.story.post` record.

## Monorepo

```text
apps/
  android/          Jetpack Compose, CameraX, and Room
  ios/              SwiftUI, AVFoundation, and SwiftData
services/
  oauth-worker/     Go ATProto OAuth metadata service for Vercel containers
docs/
  MVP_PLAN.md       Delivery plan, boundaries, and acceptance criteria
  STORY_CONTRACT.md Published Flashes record contract used by both clients
```

## Current Implementation

- Both clients implement the camera/review interaction, friendly account
  typeahead, native OAuth/DPoP session handling, and durable local story drafts.
- Both clients model the exact current Flashes story record.
- The Go OAuth service serves native public-client metadata with the minimum
  create-only Flashes actor, story, and JPEG blob permissions.
- Both apps implement JPEG blob upload and `blue.flashes.story.post` creation.
  Login idempotently
  provisions `blue.flashes.actor.profile/self` when the account does not
  already have one, and failed story drafts retain their record key for safe
  retries.
- On iOS 18 and later, Presently provides a Camera Control zoom/camera picker,
  a locked capture extension, and an Open Presently Camera control for Control
  Center and the Lock Screen. The user can select that control as the Camera
  Control or Action button launch action in system settings.
- On Android 7 and later, Presently provides an “Open Presently Camera” Quick
  Settings tile. Android does not expose Apple Camera Control or Lock Screen
  control extensions; the launcher and Quick Settings tile open the same
  camera-first experience instead.

## Develop

### iOS

```sh
cd apps/ios
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project Presently.xcodeproj \
  -scheme Presently \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The simulator cannot provide a live camera. Run on a physical device to verify
capture and photo-library saving.

### Android

```sh
cd apps/android
./gradlew testDebugUnitTest assembleDebug lintDebug
```

### OAuth worker

```sh
cd services/oauth-worker
go test ./...
go build ./...
docker build -f Dockerfile.vercel .
```

The stable production client ID is
`https://oauth.presently.photo/oauth/client-metadata.json`, with native callback
`photo.presently.oauth:/oauth/callback`. Configure the production environment
from `services/oauth-worker/.env.example`. Vercel detects the root
`vercel.json` container preset, builds
`services/oauth-worker/Dockerfile.vercel`, and routes public requests to the
container listening on the platform-provided `PORT`.

## Reference material

- [Published Flashes story schema](https://eurosky.social/xrpc/com.atproto.repo.getRecord?repo=did%3Aplc%3A24kqkpfy6z7avtgu3qg57vvl&collection=com.atproto.lexicon.schema&rkey=blue.flashes.story.post)
- [AT Protocol OAuth client guide](https://docs.bsky.app/docs/advanced-guides/oauth-client)
- [AT Protocol permissions](https://atproto.com/specs/permission)
