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
}
