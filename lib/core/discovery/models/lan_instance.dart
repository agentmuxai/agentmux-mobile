// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'lan_instance.freezed.dart';
part 'lan_instance.g.dart';

@freezed
class LanAgent with _$LanAgent {
  const factory LanAgent({
    required String name,
    @JsonKey(name: 'last_seen') String? lastSeen,
    @Default(true) bool addressable,
  }) = _LanAgent;

  factory LanAgent.fromJson(Map<String, dynamic> json) =>
      _$LanAgentFromJson(json);
}

@freezed
class LanInstance with _$LanInstance {
  const factory LanInstance({
    required String hostname,
    required String version,
    required String address,
    required int port,
    required String authKey,
    String? instanceId,
    @Default([]) List<LanAgent> agents,
  }) = _LanInstance;

  factory LanInstance.fromJson(Map<String, dynamic> json) =>
      _$LanInstanceFromJson(json);
}
