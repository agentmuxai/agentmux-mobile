import 'dart:async';

import 'package:agentmux_mobile/features/welcome/welcome.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _Seen extends WelcomeSeen {
  @override
  FutureOr<bool> build() => true;
}

/// The welcome page was shown on an earlier launch: what a test of the
/// screens behind it wants. Known from the first frame, with no store read
/// (the real store has no platform side in a widget test, and never answers).
final Override welcomeAlreadySeen = welcomeSeenProvider.overrideWith(_Seen.new);
