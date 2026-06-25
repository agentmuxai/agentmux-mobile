import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_provider.dart';
import '../../core/models/usage.dart';

class UsageNotifier extends AsyncNotifier<UsageSummary> {
  @override
  Future<UsageSummary> build() => ref.read(muxbusClientProvider).getUsage();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(muxbusClientProvider).getUsage(),
    );
  }
}

final usageProvider = AsyncNotifierProvider<UsageNotifier, UsageSummary>(
  UsageNotifier.new,
);
