// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'lan_instance.freezed.dart';
part 'lan_instance.g.dart';

/// Where an agent runs, as the desktop's block `agentMode` says: directly on
/// the machine (`host`) or in a sandbox container (`container`). Display
/// only; an unknown value parses to null, never to a guess.
enum AgentKind {
  @JsonValue('host')
  host,
  @JsonValue('container')
  container,
}

@freezed
class LanAgent with _$LanAgent {
  const factory LanAgent({
    @JsonKey(name: 'agent_id') required String name,
    @JsonKey(name: 'last_seen') int? lastSeen,
    @Default(true) bool addressable,

    /// The AgentMux channel (e.g. `stable`, `dev`) this agent lives in, set
    /// only for an agent reported by a SIBLING channel on the same host
    /// (`host.cross_channel`). Null for an agent hosted by the instance
    /// itself.
    String? channel,

    /// Host or sandbox, when the desktop reports it (`agent_kinds`). Null
    /// for an older desktop or a value this app does not know.
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
    AgentKind? kind,
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

    /// This instance's own AgentMux channel (e.g. `stable`, `dev`), when the
    /// desktop reports it. Null for a server that does not.
    String? channel,

    /// The host's platform token (`windows`, `macos`, `linux`, ...), already
    /// validated by `parseOs`. Null when not reported.
    String? os,

    /// How many channels the machine runs, including ones not shared on the
    /// LAN (1 to 99). Null for a desktop that does not report it.
    @JsonKey(name: 'channels_running') int? channelsRunning,

    /// This install's WAN instance id, the key the cloud list uses. The LAN
    /// `instance_id` above is the version string, not this.
    @JsonKey(name: 'install_id') String? installId,
    @Default([]) List<LanAgent> agents,
  }) = _LanInstance;

  factory LanInstance.fromJson(Map<String, dynamic> json) =>
      _$LanInstanceFromJson(json);
}
