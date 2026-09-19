# App Store Submission Readiness

**Status:** Gap analysis + first implementation pass — 2026-09-19. Cross-references
`RELEASE_SIGNING_SETUP.md` (the build/sign/upload pipeline) with Apple's
current App Review Guidelines to produce a single checklist of what's
already true of this repo, what's a code-side gap, and what only the human
account owner can do (Apple Developer Program membership, App Store
Connect configuration, credentials, and a few product decisions).

Nothing in this doc has been dry-run tested against a real App Store
Connect account — same caveat `RELEASE_SIGNING_SETUP.md` already carries.

**2026-09-19 update — decisions made and implemented:**
- Reviewer testability → **in-app demo mode**, built. See "Reviewer
  testability" below — this is now closed, not open.
- Privacy policy / support URL → **hosted on agentmux.ai** (`agentmux-landing`
  repo). Built — see "Privacy policy / support URL" below.
- Cognito federation (Guideline 4.8) → **still unresolved**, needs a human
  to check the actual Cognito Hosted UI config in AWS. Not something
  readable from either repo's source.

## Why apps actually get rejected (grounded in current data, not folklore)

Apple reviewed ~9.1M submissions in 2025 and rejected ~23% of them. Ranked
by volume, the categories that account for the overwhelming majority are:

1. **Guideline 2.1 (App Completeness)** — crashes, bugs, or a reviewer
   simply not being able to get past a login/empty screen. This is the
   single largest rejection category — more than every other category
   combined.
2. **Guideline 5.1.1 (Data Collection & Storage)** — missing/inaccurate
   privacy policy, a Privacy Nutrition Label that doesn't match what the
   app actually does, missing `PrivacyInfo.xcprivacy`.
3. **Guideline 2.3 (Accurate Metadata)** — mismatched screenshots, broken
   URLs, description that oversells functionality.
4. **Guidelines 4.2 / 4.3 (Minimum Functionality / Spam)** — not a likely
   risk for this app (it's a real client for a real backend service, not a
   template/wrapper), noted for completeness.
5. **Guideline 3.1.1 (In-App Purchase)** — not applicable, this app has no
   IAP.
6. **Guideline 5.1.1(v) (Account Deletion)** — any app with account
   creation must offer in-app account deletion.

Sources: [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[Apple — Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files),
[Apple News — privacy manifest enforcement](https://developer.apple.com/news/?id=pvszzano).

## This app's specific #1 risk: reviewer testability — RESOLVED

**Was the single biggest risk in this doc; now closed by an in-app demo
mode.** An Apple reviewer has no AgentMux desktop instance and no real
Cognito account, and (until this change) there was no way to see the app
actually do anything beyond an empty Discovery screen — exactly the
failure mode Guideline 2.1 rejects apps for.

**What was built (2026-09-19):**
- `lib/core/demo/demo_data.dart` — static sample agents/messages, computed
  relative to `DateTime.now()` so "Active now" / "Xm ago" labels always
  look plausible. No network call anywhere on this path.
- `lib/features/demo/demo_fleet_screen.dart` +
  `lib/features/demo/demo_agent_detail_screen.dart` — visually match the
  real Agent List / Agent Detail screens, with a persistent
  `DemoBanner` ("DEMO DATA — not a live connection") so it's never
  mistaken for a live connection. Inject is visibly present but disabled
  (shows a "not available in demo mode" snackbar) since there's no live
  agent to inject into.
- Routes `/demo` and `/demo/agent/:id` registered in `lib/app.dart`
  alongside the other no-auth routes.
- Three entry points, so it's reachable regardless of app state: an eye
  icon in the Discovery app bar (always visible), a "View a demo fleet"
  button in Discovery's empty state, and a Settings → About list item.
- Verified end-to-end in the Android sandbox (screenshots taken of the
  fleet list and message detail, both showing the demo banner and sample
  data correctly) and covered by the existing `flutter test` / `flutter
  analyze` gates (44/44 tests passing after this change).

**Put this in App Store Connect's "Notes for Review":** tell Apple to tap
the eye icon in the top bar (or "View a demo fleet" on the empty
Discovery screen) to see the app's core screens without needing a real
account or network.

## Checklist

### Already in place (verified by reading the actual files)

- Build, sign, and TestFlight-upload pipeline is fully coded and
  non-interactive: `flutter build ipa` → App Store Connect API key
  (`.p8`, JWT) auth via `altool` — no Apple ID/password anywhere in CI.
  (`.github/workflows/release-ios.yml`)
- Optional, also fully coded, App Store submission step via fastlane
  (`ios/fastlane/Fastfile`'s `submit_for_review` lane).
- Correct `NSCameraUsageDescription` (QR pairing) and
  `NSLocalNetworkUsageDescription` + `NSBonjourServices` (mDNS discovery)
  — both match actual plugin usage, both required since iOS 14.
- No `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` exception —
  nothing overriding default HTTPS-only behavior.
- `ITSAppUsesNonExemptEncryption = false` already present (flagged below
  as "confirm, don't assume").
- Full 24-entry `AppIcon.appiconset` with all files present as real
  generated PNGs (alpha channel correctly flattened for iOS — Apple
  rejects any transparency in the App Store icon).
- Bundle ID `com.agentmux.agentmuxMobile` and deployment target
  (`IPHONEOS_DEPLOYMENT_TARGET = 15.5`) consistently set.
- App doesn't force a login wall on first launch (Discovery is the
  default unauthenticated route).
- CI runs `flutter analyze` + `flutter test` + an XML well-formedness
  check on every PR (`.github/workflows/ci.yml`).
- `TARGETED_DEVICE_FAMILY = "1,2"` — app is built for both iPhone and
  iPad, which means **iPad screenshots are required at submission**, not
  optional.

### Code-side gaps

- [x] **`PrivacyInfo.xcprivacy` added** (`ios/Runner/PrivacyInfo.xcprivacy`,
      registered in `project.pbxproj`'s Resources build phase). Declares
      `NSPrivacyTracking = false`, no tracking domains, and email address
      collected for App Functionality only. **Caveat, not fully closed:**
      this only covers what this repo's own Dart/Swift code does.
      `NSPrivacyAccessedAPITypes` is left empty at the app level because no
      first-party code calls a required-reason API directly — but plugins
      like `path_provider`/`flutter_secure_storage` may still need their
      *own* bundled manifests, which Xcode aggregates automatically at
      archive time. **This has not been verified against Xcode's generated
      Privacy Report** (no Mac was available to author this — see the
      in-file comment). Run a real `flutter build ipa` on the CI Mac
      runner and check the Privacy Report before the first submission.
- [x] **Launch screen fixed** — replaced the stock 68-byte placeholder
      PNGs with the app icon centered on the app's actual dark background
      (`#0F0F0F`, matching `AppColors.background`), and updated
      `LaunchScreen.storyboard`'s background color to match (was white,
      which would have flashed against the dark app on launch). **Not
      visually verified** — this is iOS-only and this sandbox only has the
      Android emulator; the edits are syntactically correct XML/plist but
      should get an eyeball check on a real iOS simulator/device before
      submission.
- [ ] **No account-deletion path anywhere in `lib/`** (grepped, no
      matches) — **still open.** Guideline 5.1.1(v) requires in-app account
      deletion for any app that supports account creation. This wasn't
      built in this pass because the actual deletion capability (deleting
      a Cognito user + associated MuxBus data) lives in `agentmux-cloud`,
      outside both repos touched so far — needs a backend endpoint before
      the mobile app can offer a self-service "Delete my account" action.
      The mobile privacy policy currently documents an email-based
      workaround (`privacy@agentmux.ai`) as an interim measure, but that
      is not a substitute for the in-app flow Apple's guideline requires.
- [x] **README iOS version fixed** — was "iOS 16+", now says "iOS 15.5+"
      matching the Xcode project's actual `IPHONEOS_DEPLOYMENT_TARGET`.
- [x] **Privacy Policy / Support links added to in-app Settings** —
      `lib/features/settings/settings_screen.dart`'s About section now has
      "Privacy Policy" and "Support" list tiles (open via `url_launcher`,
      added as a direct `pubspec.yaml` dependency since the app now calls
      it directly rather than only pulling it in transitively) plus a
      "View a demo fleet" entry, pointing at the pages added below.

### Needs a product/business decision from you before I can build it

- [x] **Reviewer-testability strategy** — decided: in-app demo mode. Built,
      see above.
- [x] **Where does the privacy policy live?** Decided: `agentmux.ai` via
      `agentmux-landing`. Built: `src/components/MobilePrivacyPage.tsx` at
      `/mobile-privacy`, distinct from the existing `/privacy` page (which
      is about the desktop app and explicitly says "runs locally, no
      data transmitted" — accurate for desktop, would have been a false
      statement if reused for the mobile app, which does transmit data via
      MuxBus/Cognito). Cross-links both directions. **Still needs**: a
      human to review the actual legal text before `agentmux-landing` is
      deployed to prod — I drafted it accurately against what the code
      does, but I'm not the one accountable for it being legally sufficient.
- [x] **Support URL** — decided: `agentmux.ai`. Built:
      `src/components/SupportPage.tsx` at `/support`, pointing at GitHub
      Issues (`agentmux-mobile` and `agentmux` repos) and the AgentMux
      Discord — both real, already-active channels linked elsewhere on the
      site. Deliberately did **not** invent a new `support@agentmux.ai`
      email alias since I can't verify it's a monitored inbox; only reused
      `privacy@agentmux.ai`, which the existing `/privacy` page already
      established as real.
- [ ] **Does the Cognito Hosted UI federate to Google/Facebook/etc.?**
      This lives in AWS, outside this repo, so it can't be answered by
      reading the code. If yes, Guideline 4.8 requires an equivalent
      "Sign in with Apple" option (or a login option that independently
      meets 4.8's three criteria: name+email only, private-email-relay
      option, no non-consensual ad tracking) before submission — this is
      a build-affecting change, not a metadata fix, so it needs to be
      known before the first submission, not discovered from a rejection.
- [ ] **App name / subtitle / category / keywords / description /
      screenshots copy** — needs actual product copy from you; I can
      draft first passes once the reviewer-testability decision is made
      (screenshots should probably show the demo data path, if you pick
      that option).
- [ ] **Confirm the export-compliance answer** (`ITSAppUsesNonExemptEncryption
      = false`, i.e. "uses only standard/exempt encryption like TLS") —
      this is a legal declaration; I flagged it as a reasonable technical
      default already in the repo's own comments, but you're the one
      accountable for confirming it's accurate.
- [ ] **App icon is the generic desktop AgentMux mark**, not a
      mobile-specific design — not a rejection risk, but worth a deliberate
      yes/no before it's permanently the first thing users see in the App
      Store.

### Apple Developer / App Store Connect actions — only you can do these

Numbered in the order you'd actually do them:

1. **Confirm Apple Developer Program enrollment** (individual or
   AgentMux Corp. organization account, $99/year) is active for the team
   that will own this app.
2. **Register the App ID** `com.agentmux.agentmuxMobile` under
   Certificates, Identifiers & Profiles on developer.apple.com, matching
   the Xcode project exactly.
3. **Create an "Apple Distribution" certificate** (not "Developer ID
   Application" — that's the macOS-app cert already used by
   `build-macos.yml`, a different cert type). Export as `.p12` with a
   password.
4. **Create an App Store provisioning profile** for that App ID, using
   the Distribution certificate from step 3. Download the
   `.mobileprovision`.
5. **Create an App Store Connect record** for the app (My Apps → +),
   bundle ID from step 2, SKU, primary language.
6. **Generate an App Store Connect API key** (Users and Access →
   Integrations → App Store Connect API). **Role must be "App Manager"**,
   not "Developer" — a Developer-role key can upload builds but cannot
   create versions or submit for review, and `release-ios.yml`'s optional
   submission step needs the higher role. Save the Key ID, Issuer ID, and
   the `.p8` file — **Apple only lets you download the `.p8` once.**
7. **Base64-encode and add these 6 GitHub repo secrets** (per
   `RELEASE_SIGNING_SETUP.md`): `IOS_DISTRIBUTION_CERTIFICATE`,
   `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE`,
   `APPSTORE_CONNECT_API_KEY`, `APPSTORE_CONNECT_API_KEY_ID`,
   `APPSTORE_CONNECT_ISSUER_ID`. `APPLE_TEAM_ID` already exists as a repo
   secret (shared with `build-macos.yml`) — nothing to do there.
8. **Fill in App Privacy ("Nutrition Label") questionnaire** in App
   Store Connect. Based on the actual dependency list (no ads, no
   analytics, no crash-reporting SDK, no IDFA use anywhere), this should
   land as minimal/"Data Not Linked to You," but you're the one who has
   to answer it accurately for this specific build.
9. **Fill in App Store listing metadata**: name, subtitle, category
   (likely Developer Tools or Utilities), age rating questionnaire,
   privacy policy URL (`https://agentmux.ai/mobile-privacy`), support URL
   (`https://agentmux.ai/support`), description, keywords, promotional
   text, copyright. **Prerequisite**: `agentmux-landing` needs to actually
   be built and deployed with these new pages before Apple can reach
   them — they exist in the repo (`src/components/MobilePrivacyPage.tsx`,
   `src/components/SupportPage.tsx`, both routed in `src/index.tsx`) but
   haven't been shipped to prod as part of this pass.
10. **Provide screenshots**: at minimum one 6.9" iPhone set (1320×2868,
    1290×2796, or 1260×2736 px) — and, because this app targets iPad too,
    one 13" iPad set (2064×2752 px). Apple auto-scales these down for
    smaller/older devices; you don't need to supply every historical
    size separately anymore.
11. **Provide "Notes for App Review"** — this is where the reviewer-access
    strategy from above actually gets communicated: demo credentials +
    walkthrough, or a note pointing at the in-app demo mode, whichever you
    picked.
12. **Trigger `release-ios.yml` with `submit-for-review: true`** once 1–11
    are done, review the TestFlight build first, then let the optional
    fastlane step submit it. `automatic_release: false` is already set in
    the Fastfile, so approval will wait for you to click "Release" — it
    won't go live automatically the moment Apple approves it.

## Notes on 2026-specific requirements

- Apple has required builds to use **Xcode 26+ with current SDKs since
  April 28, 2026** for new submissions. `release-ios.yml` runs on GitHub's
  `macos-latest` runner — worth explicitly confirming (not assumed here)
  that image is currently shipping Xcode 26+ before relying on it, since
  "latest" tags can lag a hard Apple cutoff.
- Screenshot requirements were simplified in 2026 to just the 6.9" iPhone
  class + 13" iPad class (Apple auto-scales for everything else) — see
  item 10 above; older multi-size screenshot guidance you may find
  elsewhere is stale.

Sources: [App Store screenshot specs (2026)](https://www.mobileaction.co/guide/app-screenshot-sizes-and-guidelines-for-the-app-store/),
[Apple Developer API key setup / fastlane docs](https://docs.fastlane.tools/app-store-connect-api/),
[Guideline 4.8 breakdown](https://appraysal.com/rules/4.8_sign_in_with_apple).
