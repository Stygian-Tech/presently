# Google Play data-safety worksheet

This is an implementation-derived worksheet, not a completed Play Console
declaration. Re-check every answer against the exact beta build and Google's
current definitions before submitting it.

## Current implementation

- No advertising SDKs or third-party analytics SDKs are included.
- Camera access is used only after the user grants permission.
- Photos stay local while being prepared. A photo the user explicitly posts is
  uploaded over HTTPS directly to their AT Protocol Personal Data Server.
- The app creates a public Flashes-compatible story record in the user's AT
  Protocol repository.
- OAuth tokens and cryptographic keys are stored in Android secure storage and
  are not sent to Presently's metadata service.
- Pending and failed drafts may be retained on-device for retry.
- The user can optionally save a separate copy to their photo library.
- Presently's metadata service receives OAuth metadata requests, but not
  passwords, access tokens, refresh tokens, private keys, or captured photos.

## Console answers to confirm

- Data collection: determine whether user-directed transfer of photos and
  account data to the user's chosen PDS is considered collection under the
  current Play definition.
- Data sharing: identify the account provider/PDS as a service provider or
  user-directed destination as applicable under the current form.
- Data types likely involved: photos, user IDs/account identifiers, and app
  activity required to complete a publish request.
- Purposes: app functionality and account management only.
- Processing: encrypted in transit; sensitive credentials stored using Android
  secure storage.
- Deletion: repository content and account data are controlled through the
  user's AT Protocol provider; local drafts can be removed by clearing app data
  or uninstalling the app.

Public story expiration is a display convention, not guaranteed deletion from
independent indexes, caches, replicas, or archives.
