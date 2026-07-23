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
