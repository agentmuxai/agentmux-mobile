import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_provider.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/injection.dart';

class InjectionState {
  const InjectionState({
    this.message = '',
    this.priority = 'normal',
    this.submitting = false,
    this.error,
    this.quotaExceeded = false,
    this.sent,
  });

  final String message;
  final String priority;
  final bool submitting;
  final String? error;
  final bool quotaExceeded;
  final Injection? sent;

  InjectionState copyWith({
    String? message,
    String? priority,
    bool? submitting,
    String? error,
    bool? quotaExceeded,
    Injection? sent,
  }) =>
      InjectionState(
        message: message ?? this.message,
        priority: priority ?? this.priority,
        submitting: submitting ?? this.submitting,
        error: error, // null when omitted — clears on setMessage/setPriority (intentional UX)
        quotaExceeded: quotaExceeded ?? this.quotaExceeded,
        sent: sent ?? this.sent,
      );
}

class InjectionNotifier extends FamilyNotifier<InjectionState, String> {
  @override
  InjectionState build(String targetAgent) => const InjectionState();

  void setMessage(String v) => state = state.copyWith(message: v);
  void setPriority(String v) => state = state.copyWith(priority: v);

  Future<void> submit() async {
    final msg = state.message.trim();
    if (msg.isEmpty) return;

    state = state.copyWith(submitting: true, error: null, quotaExceeded: false);

    try {
      final auth = ref.read(authRepositoryProvider);
      final sub = await auth.getUserSub() ?? 'mobile';
      final sourceId = 'mobile:$sub';

      final injection = await ref.read(muxbusClientProvider).postInjection(
            targetAgent: arg,
            message: msg,
            priority: state.priority,
            sourceAgentId: sourceId,
          );
      state = state.copyWith(submitting: false, sent: injection, message: '');
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        state = state.copyWith(submitting: false, quotaExceeded: true);
      } else {
        state = state.copyWith(submitting: false, error: e.message ?? e.toString());
      }
    } catch (e) {
      state = state.copyWith(submitting: false, error: e.toString());
    }
  }
}

final injectionProvider =
    NotifierProviderFamily<InjectionNotifier, InjectionState, String>(
  InjectionNotifier.new,
);
