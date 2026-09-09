# AgentMux Mobile

Mobile companion for the [AgentMux](https://github.com/agentmuxai/agentmux) fleet.
Built with Flutter. Connects via [agentmux-cloud](https://github.com/agentmuxai/agentmux-cloud) (muxbus) when off the local network, or directly to the desktop backend over LAN (mDNS discovery, UDP-broadcast fallback, QR-code pairing).

**Private repo — AgentMux Corp.**

## What it does

- **Agent list** — see every agent, last-seen status, and unread badge
- **Message feed** — read per-agent message history in real time
- **Inject** — send a prompt to any running agent
- **Usage & billing** — monthly quota bars (messages, drone runs, emails) + tier
- **LAN mode** — discover and pair with a desktop backend directly on the local network (mDNS, UDP-broadcast fallback, QR-code pairing), bypassing muxbus entirely

It is read-first. Agent configuration, workspace, and tool execution stay on the desktop app.

## Local Android sandbox (Windows dev machine)

**Read this before "Quick start" below if `flutter`/`dart` aren't already on PATH, or if you
need a real device to run against.** This app must run on a real OS — "it should be its own
system, not a browser" — so `flutter run -d chrome` is NOT an acceptable substitute for
verifying a change; use the Android emulator below.

A ready-to-use AVD already exists on this machine — **`AgentMux_Pixel9`** (Pixel 9, Android 15 /
API 35, x86_64, `google_apis` image, ~3.6 GB, at `C:\Users\<user>\.android\avd\AgentMux_Pixel9.avd`).
The Android SDK, licenses, and Java (bundled with Android Studio) are already fully configured —
`ANDROID_HOME`/`ANDROID_SDK_ROOT` are already set as user env vars. You do NOT need to create a
new AVD or accept licenses again.

```bash
# 1. Get Flutter on PATH (not pre-installed as of 2026-08-18). Match the exact
#    version pinned in .fvmrc — currently 3.38.9 — don't just grab "latest stable".
#    (fvm — dart pub global activate fvm — also works if you prefer version-switching,
#    but a direct SDK install is simpler and was what was actually verified working.)
curl -L -o flutter_sdk.zip \
  "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$(cat .fvmrc | grep -o '[0-9.]*')-stable.zip"
# Extract to a clean, short path (avoid spaces/admin-only dirs) — C:\src\flutter is a safe default.
unzip -q flutter_sdk.zip -d /c/src
export PATH="/c/src/flutter/bin:/c/Users/<user>/AppData/Local/Android/Sdk/platform-tools:$PATH"

# 2. Launch the emulator — long-running GUI process, run it detached/backgrounded.
#    The trailing `&` below is for a HUMAN in an interactive shell, where the
#    parent shell stays alive and the emulator survives.
#    AGENTS: do NOT copy the `&`. A Bash *tool call* returns immediately, so the
#    backgrounded emulator is killed out from under you — silently, leaving only
#    a stale `offline` entry in `adb devices`. Use the harness's own background
#    mechanism instead (Bash tool `run_in_background: true`, no `&`), or just run
#    `scripts/dev-full.sh`. See CLAUDE.md's sandbox section.
"C:\Users\<user>\AppData\Local\Android\Sdk\emulator\emulator.exe" -avd AgentMux_Pixel9 &

# 3. Wait for a FULL boot (not just adb-visible — sys.boot_completed is the real signal).
#    `adb devices` can show a stale/offline ghost entry alongside the real one; always
#    target the real emulator explicitly with -s (usually emulator-5554, confirm via
#    `adb devices -l` — the one with status "device", not "offline").
while [ "$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do sleep 3; done

# 4. Standard Flutter workflow, targeting the emulator explicitly:
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d emulator-5554 \
  --dart-define=MUXBUS_COGNITO_DOMAIN=<your-cognito-domain> \
  --dart-define=MUXBUS_CLIENT_ID=<public-app-client-id> \
  --dart-define=MUXBUS_API_BASE=https://muxbus.agentmux.ai \
  --dart-define=MUXBUS_WS_BASE=wss://muxbus-ws.agentmux.ai
```

**Gotchas hit while verifying this end-to-end (2026-08-18):**
- **`adb` device-side paths from Git Bash get mangled** (e.g. `/sdcard/foo.png` silently rewrites
  to `C:/Program Files/Git/sdcard/foo.png`). Prefix the command with `MSYS2_ARG_CONV_EXCL="*"`
  when passing on-device absolute paths to `adb pull`/`adb push`/`adb shell`.
- **A real, previously-undiscovered Android build failure was caught this way**: `AndroidManifest.xml`
  had a literal `--` inside an XML comment (invalid per the XML spec — comments can't contain
  `--` anywhere except the closing `-->`), which failed `ManifestMerger2` on 100% of Android
  builds. This had never been caught because nothing had actually built for Android before. If
  you see `ManifestMerger2$MergeFailureException: Error parsing AndroidManifest.xml` /
  `The string "--" is not permitted within comments`, that's the bug class — search the manifest
  for a stray `--` inside a `<!-- ... -->` block. (Already fixed as of this writing — this note is
  here so it's recognized instantly if a similar copy-pasted comment reintroduces it.)
- mDNS discovery does NOT work on the Android emulator's default networking (see
  [issue #2](https://github.com/agentmuxai/agentmux-mobile/issues/2)'s reliability table) — a real
  device is needed to exercise mDNS itself.
- **The Discovery screen CAN still find your desktop's real AgentMux instance from the emulator**,
  without mDNS: run `dart run scripts/discovery_relay.dart` on this machine (leave it running
  alongside the emulator), then use the app's normal Discovery screen — no manual IP entry, no
  dev-bootstrap dart-defines needed. Researched and ruled out general LAN bridging for the
  emulator on Windows first (`-net-tap` and Genymotion's bridged mode are both documented as
  unreliable-to-broken on Windows specifically) — this relay is a purpose-built workaround for
  this app's own discovery protocol instead. See
  `docs/specs/DISCOVERY_DIAGNOSTICS_TELEMETRY.md`'s follow-up section for the full design, and
  that script's own doc comment for how it works.
- **`scripts/dev-full.sh` combines the emulator boot, the discovery relay, and
  `run-emulator.sh` into one command** — every discovery path (sidecar
  auto-connect, LAN relay, QR, manual, cloud) is live on every launch instead
  of requiring the steps above separately each time:
  `scripts/dev-full.sh [extra flutter run args]`.

## Quick start

```bash
# Install fvm if needed
dart pub global activate fvm
fvm install   # reads .fvmrc

# Install dependencies
fvm flutter pub get

# Generate freezed / json_serializable code
dart run build_runner build --delete-conflicting-outputs

# Run (provide build-time config via --dart-define)
fvm flutter run \
  --dart-define=MUXBUS_COGNITO_DOMAIN=<your-cognito-domain> \
  --dart-define=MUXBUS_CLIENT_ID=<public-app-client-id> \
  --dart-define=MUXBUS_API_BASE=https://muxbus.agentmux.ai \
  --dart-define=MUXBUS_WS_BASE=wss://muxbus-ws.agentmux.ai
```

## Platform setup

### Android — custom scheme

`flutter_web_auth_2` requires its own `com.linusu.flutter_web_auth_2.CallbackActivity`
declared in `android/app/src/main/AndroidManifest.xml` — the intent-filter must
NOT be added to `.MainActivity`; the plugin's own runtime listens on this
separate activity for the redirect:

```xml
<activity
  android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
  android:exported="true"
  android:taskAffinity="">
  <intent-filter android:label="flutter_web_auth_2">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="agentmuxmobile" />
  </intent-filter>
</activity>
```

See the [package's Android setup docs](https://pub.dev/packages/flutter_web_auth_2) for the full requirements (e.g. `android:exported="true"` is mandatory for SDK 31+).

### iOS — custom scheme

In `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>agentmuxmobile</string>
    </array>
  </dict>
</array>
```

### Cognito app client

Create a **public app client** (no client secret) in the existing muxbus Cognito User Pool:

- Grant type: Authorization code
- Allowed callback URLs: `agentmuxmobile://auth/callback`
- Allowed sign-out URLs: `agentmuxmobile://auth/callback`
- Auth flows: `ALLOW_USER_SRP_AUTH`, `ALLOW_REFRESH_TOKEN_AUTH`
- No client secret

Use the new client ID as `MUXBUS_CLIENT_ID` in `--dart-define`.

## Project structure

```
lib/
├── main.dart                      # ProviderScope entry point
├── app.dart                       # MaterialApp.router + GoRouter (auth redirect)
├── core/
│   ├── auth/
│   │   ├── token_storage.dart     # FlutterSecureStorage wrapper
│   │   ├── auth_repository.dart   # Cognito PKCE sign-in/out/refresh
│   │   └── auth_provider.dart     # AuthStatus Riverpod notifier
│   ├── api/
│   │   ├── muxbus_client.dart     # Dio REST client + 401 refresh interceptor
│   │   ├── muxbus_socket.dart     # WebSocket /ws, foreground lifecycle
│   │   └── api_provider.dart      # Riverpod providers for client + socket
│   ├── discovery/
│   │   ├── mdns_scanner.dart          # mDNS discovery of desktop backends on LAN
│   │   ├── udp_broadcast_prober.dart  # UDP-broadcast fallback discovery
│   │   ├── local_api_client.dart      # Direct REST client to desktop backend
│   │   ├── android_multicast_lock.dart
│   │   └── discovery_provider.dart
│   ├── billing/
│   │   └── billing_provider.dart
│   ├── logging/
│   │   └── app_logger.dart        # dart:developer.log wrapper + in-memory ring buffer
│   └── models/
│       ├── agent.dart             # Agent (freezed)
│       ├── message.dart           # Message (freezed)
│       ├── injection.dart         # Injection (freezed)
│       └── usage.dart             # UsageSummary + QuotaItem
├── features/
│   ├── login/                     # Login screen (Cognito hosted UI)
│   ├── agent_list/                # Agent list + provider
│   ├── agent_detail/              # Per-agent message feed + provider
│   ├── injection/                 # Injection bottom sheet + provider
│   ├── usage/                     # Usage & billing screen + provider
│   ├── discovery/                 # LAN discovery, QR pairing, manual-add screens
│   ├── lan_agent/                 # Agent view served over the direct LAN connection
│   ├── debug/                     # In-app debug log viewer (AppLogger ring buffer)
│   └── settings/                  # Sign-out + version info
└── shared/
    ├── theme/app_theme.dart       # AgentMux dark palette
    └── widgets/
        ├── status_badge.dart      # Traffic-light dot (active/idle/offline)
        └── quota_bar.dart         # Linear quota progress bar
```

## Architecture notes

- **State**: Riverpod 2 `AsyncNotifier` / `Notifier` — no code generation required to run, though `@riverpod` annotations are available for future use.
- **Auth**: Cognito hosted UI via PKCE (`flutter_web_auth_2`). Tokens stored in platform keychain (`flutter_secure_storage`). Concurrent 401s handled with a `Completer`-based "one future" mutex in the Dio interceptor.
- **Real-time**: WebSocket to `wss://muxbus-ws.agentmux.ai` connects on foreground, disconnects on pause. On `inject_available` broadcast, providers refresh the agent list and active message feed.
- **x-agent-id**: `GET /api/agents`, `/usage/current`, `/billing/tier` require no agent ID header. `GET /api/messages` passes the viewed agent's ID. `POST /reactive/inject` passes `mobile:<cognito_sub>` as the source identifier.

## Requirements

- Flutter 3.38.9 (pinned via `.fvmrc`)
- Dart 3.10+
- iOS 16+ / Android API 24+
- Cognito public app client (see Platform setup above)
