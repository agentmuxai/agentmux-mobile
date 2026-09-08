# Release Signing Setup — Android & iOS Store Deploy

**Status:** Setup guide (workflows exist; secrets below do not yet)

This documents the one-time setup needed before `.github/workflows/release-android.yml`
and `.github/workflows/release-ios.yml` can actually run. Neither workflow
works today — they reference GitHub repo secrets that don't exist yet.
Nothing here has been executed; no real key material has been generated or
stored as part of writing this doc.

## Android — Play Console

1. **Generate a release keystore** (once, keep forever — losing it means you
   can never update the app under the same listing again):
   ```bash
   keytool -genkey -v -keystore agentmux-mobile-release.keystore \
     -alias agentmux-mobile -keyalg RSA -keysize 2048 -validity 10000
   ```
2. **Create a Play Console service account** for CI uploads: Play Console →
   Setup → API access → create a service account in the linked Google Cloud
   project, grant it "Release manager" access to this app, download its JSON
   key.
3. **Add GitHub repo secrets** (Settings → Secrets → Actions):
   - `ANDROID_KEYSTORE` — `base64 -w0 agentmux-mobile-release.keystore`
   - `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_PASSWORD` — from step 1
   - `ANDROID_KEY_ALIAS` — `agentmux-mobile` (or whatever alias you chose)
   - `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` — the raw JSON content from step 2
     (not base64 — `r0adkll/upload-google-play` expects plain text)
4. Store the keystore itself (the actual file, not just the CI secret)
   somewhere durable outside this repo — `secrets-cli` (`@a5af/secrets`,
   `services/infra`) is the recommended place, following the same
   `<host>`/`<app>`-prefixed flat-key convention already used for other
   credentials there (e.g. `agentmux-mobile-android-keystore`, base64
   value). It is your only copy; GitHub secrets are write-only and can't be
   read back if lost.

## iOS — App Store Connect / TestFlight

This needs an **Apple Distribution** certificate, distinct from the
**Developer ID Application** certificate `agentmux`'s `build-macos.yml`
already uses for the desktop app — the two are different certificate types
issued for different purposes (App Store submission vs. outside-the-Store
distribution) and are not interchangeable.

1. **Create an Apple Distribution certificate** (Apple Developer portal →
   Certificates → "+" → Apple Distribution), export it as a `.p12` with a
   password from Keychain Access.
2. **Register an App ID** for `com.agentmux.agentmuxMobile` if not already
   done, then **create an App Store provisioning profile** for it using the
   certificate from step 1. Download the `.mobileprovision`.
3. **Create an App Store Connect API key** (App Store Connect → Users and
   Access → Keys → "+"), role "App Manager" or "Developer" is sufficient for
   uploads. Download the `.p8` **once** — Apple does not let you download it
   again. Note the Key ID and Issuer ID shown on that page.
4. **Add GitHub repo secrets**:
   - `IOS_DISTRIBUTION_CERTIFICATE` — `base64 -w0 Certificates.p12`
   - `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` — the export password from step 1
   - `IOS_PROVISIONING_PROFILE` — `base64 -w0 profile.mobileprovision`
   - `APPSTORE_CONNECT_API_KEY` — `base64 -w0 AuthKey_XXXXXXXXXX.p8`
   - `APPSTORE_CONNECT_API_KEY_ID`, `APPSTORE_CONNECT_ISSUER_ID` — from step 3
   - `APPLE_TEAM_ID` **is already set** (reused from `agentmux`'s own repo
     secrets) — Team ID is account-level, not certificate-specific, so no
     new value is needed here.
5. As with the Android keystore, back up the `.p12`, `.mobileprovision`, and
   `.p8` in `secrets-cli` (`services/infra`) under a consistent
   `agentmux-mobile-ios-*` naming convention — GitHub secrets can't be read
   back once written.

## After setup

- `release-android.yml` — manual `workflow_dispatch`, choose a Play Console
  track (internal/alpha/beta/production). Start with `internal` to verify
  the pipeline before touching a public track.
- `release-ios.yml` — manual `workflow_dispatch`, uploads to TestFlight.
  There is currently no separate "internal vs. production" choice here —
  App Store submission itself is a manual step in App Store Connect after
  the TestFlight build lands, same as it always was.
- Both workflows delete the decoded signing material at the end of the job
  (`if: always()`), but note GitHub Actions runners are ephemeral and
  destroyed after the job regardless — this is defense in depth, not the
  only thing standing between the secret and the next job.
