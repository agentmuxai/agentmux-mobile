# AgentMux Mobile

Terminal & AI agent companion app for [AgentMux](https://github.com/agentmuxai/agentmux).

Built with Flutter, targeting Android and iOS.

## Architecture

See [ARCHITECTURE.md](./ARCHITECTURE.md) for the full specification.

## Quick Start

```bash
# Install dependencies
flutter pub get

# Run on Android
flutter run -d android

# Run on iOS
flutter run -d ios

# Run tests
flutter test
```

## Requirements

- Flutter 3.29+
- Dart 3.7+
- Android SDK 26+ (for Android)
- Xcode 15+ (for iOS)

## Project Structure

```
lib/
├── main.dart                  # Entry point
├── app.dart                   # App root, router, theme
├── core/
│   ├── rpc/                   # WebSocket RPC client
│   ├── models/                # Data models (freezed)
│   └── providers/             # Riverpod providers
├── features/
│   ├── connections/           # Backend connection manager
│   ├── sessions/              # Session browser
│   ├── terminal/              # Terminal emulator view
│   ├── agent/                 # AI agent chat view
│   └── settings/              # App settings
└── shared/
    ├── widgets/               # Reusable components
    └── theme/                 # App theming
```

## License

Private — AgentMux Corp.
