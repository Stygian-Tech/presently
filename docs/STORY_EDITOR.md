# Native story editor

Tracked in [PRSTLY-1](https://linear.app/stygian-tech/issue/PRSTLY-1/add-native-text-and-sticker-editing-to-photo-stories).

## First version

The photo review screen is an editable composition. A user can add text with
font, color, alignment and background options; add emoji or a static image;
move, resize and rotate layers; align them to the photo's center; delete a
selected layer; and undo edits.

Use native text input and image selection on each platform. Image input from
keyboards depends on the installed keyboard and operating system. Imported
images become local sticker assets. Subject cutouts, animation, video, filters
and remote sticker catalogs are outside this version.

## Composition and rendering

- Keep the original photo and a versioned recipe of editable layers locally.
- Store layer coordinates relative to the upright photo, excluding letterbox
  bars and editor controls. Scale text and assets in this same coordinate space.
- Draw layers in stable stacking order. Selection borders and alignment guides
  are editor UI and never appear in exported photos.
- Use the same native drawing routines for preview and export. Bound decoded
  image sizes and perform expensive image work outside gesture updates.
- Render the composition to JPEG before publishing. The resulting JPEG must
  meet the existing 10 MiB limit. No editor metadata is sent to the PDS.

The existing `blue.flashes.story.post` record and OAuth scopes remain sufficient.
Other clients display the final photo without needing editor support. Text drawn
on a photo is separate from the record's optional text/facets fields.

## Draft and retry lifecycle

Persist a draft before posting and save completed edits so the composition can
be restored after the app exits. Existing photo-only drafts must remain usable.
Keep failed drafts and expose retry and discard.

Before the first network publish attempt, freeze the rendered JPEG, creation
time and record key together. Retries use that exact publication snapshot, and
editing is disabled for a draft that has entered publication. This prevents an
ambiguous response from causing a retry to publish a different composition.
Use the same JPEG for publishing and the optional device-library copy.

## Verification

Automated checks should cover:

- Recipe round trips, invalid/unsupported recipes, stable layer identity.
- Undo for insertion, editing, deletion and complete gestures.
- Portrait and landscape image geometry, scale limits and center snapping.
- Text wrapping, emoji, transparent stickers and orientation-aware rendering.
- Output limits, old draft migration, restored edits and frozen retry data.

Rendered checks should exercise text entry and style controls, image insertion,
drag/scale/rotation, guides, selection, deletion, undo, and force-quit/relaunch.
Check that toolbars remain reachable with the keyboard and larger text sizes.

Physical camera capture, device-specific image keyboards, photo-library saving,
and authenticated publishing to a PDS require separate device acceptance.
Simulator builds and local export tests do not establish that acceptance.

### Implementation validation — 2026-09-14

- iOS: build and all 39 tests passed. Simulator checks covered native text
  entry, emoji, Photos picker sticker import, drag, delete/undo, and draft
  restoration after stop/relaunch. A text-input synchronization regression
  found during these checks was fixed and covered by regression tests.
- Android: the isolated editor commit passed all 34 unit tests, debug build,
  and lint. The working checkout also passed its 41 tests, including unrelated
  existing local changes. Native instrumentation exercised text, emoji, image
  import, undo, deletion, resize/rotation/nudges, and draft restoration after
  force-stop/relaunch in separate processes.
- Web type checking/build and Go service tests/build passed.
- Physical-device camera and keyboard behavior, photo-library saving, and an
  authenticated PDS publish remain release acceptance checks.

For local editor QA without camera capture, Debug builds accept `--editor-demo`
on iOS and the boolean launch extra `presently.editor.sample` on Android. These
seed a synthetic photo only when no unfinished draft exists. They do not sign
in or publish a story.
