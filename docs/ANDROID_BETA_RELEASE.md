# Android beta release

Presently's first Google Play release should use the **Internal testing** track.
Production promotion is a separate approval gate.

## Release identity

- Application ID: `tech.stygian.presently`
- Default version name: `0.1.0`
- Default version code: `1`
- Minimum SDK: 23
- Target SDK: 36
- Privacy policy: `https://presently.photo/privacy/`
- Support: `https://presently.photo/support/`

The application ID becomes permanent after the first Play upload. Confirm that
the Play Console app record uses this exact value before uploading.

## Upload key

Use a dedicated Google Play upload key and enroll the app in Play App Signing.
Keep the keystore and both passwords in 1Password, with a separate recoverable
backup. Never commit them to Git or place them in a shell history entry.

The Gradle release build reads these environment variables:

- `PRESENTLY_UPLOAD_STORE_FILE`
- `PRESENTLY_UPLOAD_STORE_PASSWORD`
- `PRESENTLY_UPLOAD_KEY_ALIAS`
- `PRESENTLY_UPLOAD_KEY_PASSWORD`
- `PRESENTLY_VERSION_CODE` (optional; defaults to `1`)
- `PRESENTLY_VERSION_NAME` (optional; defaults to `0.1.0`)

Equivalent Gradle properties are `presentlyUploadStoreFile`,
`presentlyUploadStorePassword`, `presentlyUploadKeyAlias`,
`presentlyUploadKeyPassword`, `presentlyVersionCode`, and
`presentlyVersionName`.

## Local release verification

From `apps/android` with signing values already present in the environment:

```sh
./gradlew --no-daemon clean test lintRelease bundleRelease
jarsigner -verify -strict -certs \
  -keystore "$PRESENTLY_UPLOAD_STORE_FILE" \
  -storepass:env PRESENTLY_UPLOAD_STORE_PASSWORD \
  app/build/outputs/bundle/release/app-release.aab "$PRESENTLY_UPLOAD_KEY_ALIAS"
shasum -a 256 app/build/outputs/bundle/release/app-release.aab
```

The signed artifact is
`apps/android/app/build/outputs/bundle/release/app-release.aab`.

## GitHub beta artifact

The `Android` workflow always runs tests and Release lint. A manual workflow
dispatch also builds a signed bundle using the protected `android-beta`
environment.

Configure these environment secrets:

- `PRESENTLY_UPLOAD_KEYSTORE_BASE64`
- `PRESENTLY_UPLOAD_STORE_PASSWORD`
- `PRESENTLY_UPLOAD_KEY_ALIAS`
- `PRESENTLY_UPLOAD_KEY_PASSWORD`

Configure these environment variables and increment the code for every upload:

- `PRESENTLY_VERSION_CODE`
- `PRESENTLY_VERSION_NAME`

The workflow verifies the JAR signature, writes the bundle SHA-256 and commit
SHA, and retains the artifact for 14 days. It does not upload to Google Play.

## Play Console checklist

1. Confirm the correct Google developer account and create the Presently app.
2. Confirm `tech.stygian.presently` before the first bundle upload.
3. Enroll in Play App Signing and register the dedicated upload certificate.
4. Complete App content: privacy policy, ads, app access, target audience,
   content rating, and data safety.
5. Use the copy in `apps/android/play/listing/en-US.md` and verify the public
   privacy/support/terms URLs.
6. Add at least two phone screenshots and the required store graphic assets.
7. Create an Internal testing release and upload the signed `.aab`.
8. Add no more than 100 internal testers and verify the opt-in flow on a
   physical Android device.
9. Exercise camera permission denial/recovery, account sign-in, capture,
   retake, optional local save, publish, retry, and feedback-board handoff.
10. Record the Play release version code, bundle SHA-256, commit SHA, tester
    cohort, and observed device/OS versions.

Do not promote the bundle to closed, open, or Production tracks without a
separate review and explicit approval.
