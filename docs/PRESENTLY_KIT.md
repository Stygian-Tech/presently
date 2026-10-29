# PresentlyKit

PresentlyKit is the shared iOS 17+ implementation of Presently's photo stories.
The repository root is a Swift package with one library product, `PresentlyKit`,
and no external dependencies. It uses Swift 6 language mode and requires an
Xcode 26 or newer SDK to compile the available smart-framing APIs. Presently
itself consumes this package.

## Ownership

The package owns:

- AVFoundation capture, hardware capture interaction, camera switching, zoom,
  smart selfie framing, and the live viewfinder controls.
- Text, emoji and still-image sticker editing, native keyboard input, layer
  gestures, undo, versioned recipes, upright decoding, framing and JPEG export.
- Flashes story/profile records and default profile settings, required OAuth
  scopes, JPEG blob upload, story creation and verified retry reconciliation.

Each host owns authentication and credentials, PDS discovery, token refresh and
DPoP nonce handling, persistent drafts/settings, navigation, completion/error UI,
photo-library saving and system capture extensions. These are adapters around
one shared implementation. Quill and The Social Wire are future consumers;
this extraction does not change either app.

## Add the package

For a local checkout, add the Presently repository root as a local Swift package
and link its `PresentlyKit` product. XcodeGen example, with a path relative to
the host's project file:

```yaml
packages:
  PresentlyKit:
    path: /path/to/presently
# In each consuming target's dependencies:
# - package: PresentlyKit
```

The root manifest also supports Git URL consumption once these commits are
pushed. Use a pinned revision until a release tag exists. No release has been
published as part of this extraction. This is an iOS package; it does not offer
macOS, Android or web views.

## Capture and edit

Own one `CameraController` in `@State`. Show the shared viewfinder while
capturing; the host may overlay its account, settings and dismiss buttons.
Start the controller in `.task`, call `stop()` when leaving, and start it again
when reopening. The host decides how to respond to app backgrounding.

```swift
import PresentlyKit
import SwiftUI

struct CaptureExample: View {
    @State private var camera = CameraController()
    @State private var capturedRatio: Double?

    var body: some View {
        CameraViewfinder(camera: camera) { ratio in
            capturedRatio = ratio
            camera.capture()
        }
        .task { await camera.start(preferredFacing: .back) }
        .onDisappear { camera.stop() }
    }
}
```

Observe `camera.capturedPhotoData` to enter review. Preserve these original
bytes, create a `StoryComposition(usesStoryCrop: true,
captureViewportAspectRatio: capturedRatio)`, and persist its `encoded()` recipe.
The ratio must be frozen at shutter time to match the aspect-fill preview.
Call `camera.retake()` to clear the previous capture before the next photo.

```swift
let session = try StoryEditorSession(photoData: originalData, recipe: savedRecipe)
session.onChange = { composition in
    // Save originalData + try composition.encoded() in the host's draft store.
}
let editor = StoryEditorView(
    session: session,
    isEditable: !isPublishing,
    onError: showError,
    onEditingChanged: { editing in /* Hide host footer during native text input. */ }
)
```

Embed the editor in a dark review surface, normally a `NavigationStack`, and
provide host discard/publish controls. Only enable completion when
`session.canFinishEditing` is true. Call `session.endTransform()` before saving
on backgrounding. Keep original bytes separate from flattened output; pass the
original and the saved recipe back to `StoryEditorSession` to restore a draft.
Old recipes without crop fields retain their original framing.

Render once after editing finishes:

```swift
let jpeg = try StoryRenderer.jpeg(
    photo: session.photo,
    composition: session.composition,
    maximumBytes: FlashesStoryContract.maximumImageBytes
)
```

Keep that JPEG, creation date and record key unchanged once publication starts.
Disable editing on an attempted draft; reuse the same bytes and key for retry.
Use that same JPEG for optional saving to Photos. Other image workflows can
supply a smaller `maximumBytes`; the renderer throws if it cannot meet it.

## Authentication adapter

Request `StoryPublisher.requiredOAuthScopes` in the host's OAuth flow and ensure
its public client metadata permits those scopes. Existing sessions without them
need reauthorization. Credentials never enter the package.

Implement `StoryPublishingTransport` with the host's existing authenticated
client. A request contains an XRPC procedure, method, encoded query items,
optional body and content type. Resolve it against the pinned account's PDS at
`/xrpc/<procedure>`, encode query items with `URLComponents`, apply authentication
and the host's normal refresh/nonce retry, and return
`StoryPublishingResponse(statusCode:data:)`. Preserve the response body/status
for protocol failures so the publisher can distinguish `RecordNotFound` and
`RecordAlreadyExists`; propagate network/authentication errors normally.

GET requests read public repo records. Presently's adapter sends these without
credentials. POST requests must use authenticated writes. Pin the account for
the whole operation and persist evolving tokens/nonces as the host requires.
Do not redirect an in-flight operation to a newly selected account.

## Flashes actor detection and creation

```swift
let publisher = StoryPublisher(repo: accountDID, transport: authenticatedTransport)
try await publisher.ensureActorProfile()
```

Call this after sign-in, or before first publishing when readiness is unknown.
A successful lookup preserves the user's existing profile/preferences. Only a
confirmed `RecordNotFound` creates `blue.flashes.actor.profile/self` using the
shared defaults. A concurrent `RecordAlreadyExists` response is accepted;
other lookup/create failures propagate. Cache readiness per account only after
the call succeeds. `publish` does not implicitly repeat this lookup.

## Publish and retry

```swift
// Persist this key before the first network write, then reuse it on retry.
let recordKey = ATProtoTID.make(date: createdAt)
let result = try await publisher.publish(
    jpegData: frozenJPEG,
    createdAt: createdAt,
    recordKey: recordKey
)
```

The publisher uploads the JPEG, validates the returned blob, builds the shared
24-hour `blue.flashes.story.post` record and creates it at the supplied key.
If that key already exists, it reads it back and verifies the full record,
including image, creation time, expiry and URI, before returning success. An
unrelated or unverifiable existing record fails instead of claiming success.
For an ambiguous transport failure, retain the draft and retry with the same
key/date/JPEG. The host marks a draft published only after this method returns.

## Permissions and validation

The host needs `NSCameraUsageDescription`. Add
`NSPhotoLibraryAddUsageDescription` only if the host offers saving to Photos.
The editor's system photo picker does not require broad photo-library access.
Lock Screen capture and Control Center extensions remain host targets with
host entitlements and intent routing.

Run the standalone package tests on an installed iOS simulator:

```sh
xcodebuild -scheme PresentlyKit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO test
```

Run Presently's integration suite with its project and scheme. Package tests
cover recipes, framing, rendering, keyboard synchronization, camera queue
ownership, the public consumer API and publishing/profile transport behavior.
Hardware capture, smart framing and real authenticated publishing still require
physical-device/account acceptance; simulator/unit results do not prove them.
