// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'injection.freezed.dart';
part 'injection.g.dart';

@freezed
class Injection with _$Injection {
  const factory Injection({
    required String id,
    @JsonKey(name: 'target_agent') required String targetAgent,
    @JsonKey(name: 'source_agent') @Default('') String sourceAgent,
    required String message,
    @Default('normal') String priority,
    @Default('pending') String status,
    @JsonKey(name: 'created_at') required String createdAt,
  }) = _Injection;

  factory Injection.fromJson(Map<String, dynamic> json) =>
      _$InjectionFromJson(json);

  /// Builds an [Injection] from `POST /reactive/inject`'s actual response
  /// shape — a flat object (`success`, `injection_id`, `source_agent`,
  /// `target_agent`, `priority`, `created_at`, `ttl_seconds`; see
  /// muxbus/server/src/index.ts in agentmux-cloud), not the `{id, message,
  /// status, ...}` shape [Injection.fromJson] expects. The server never
  /// echoes the message back, so it's supplied by the caller (who already
  /// has it — it's what was just sent). Do not call [Injection.fromJson]
  /// on this endpoint's response: that's the exact bug this factory fixes
  /// (DOC-001, 2026-08-03 documentation analyst — every Inject call threw
  /// because the client parsed a nonexistent nested `injection` key using
  /// a schema this endpoint never returns).
  factory Injection.fromInjectResponse(
    Map<String, dynamic> json, {
    required String message,
  }) =>
      Injection(
        id: json['injection_id'] as String,
        targetAgent: json['target_agent'] as String,
        sourceAgent: json['source_agent'] as String? ?? '',
        message: message,
        priority: json['priority'] as String? ?? 'normal',
        createdAt: json['created_at'] as String,
      );
}
