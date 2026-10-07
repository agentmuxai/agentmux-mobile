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

/// What an agent is doing, as the desktop reports it
/// (`docs/specs/SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` section
/// 3.1). Null on an agent means unknown: an older desktop, a terminal-pane
/// agent, or a value this app does not know. Never a guess.
enum AgentState {
  /// A turn is running.
  working,

  /// A turn is running and a question waits for the user on the desktop.
  waiting,

  /// The process is alive, no turn is running.
  idle,

  /// The process exited cleanly.
  stopped,

  /// The process exited with an error.
  error,
}

/// How long an agent has been in its state, without ever comparing this
/// device's clock with the desktop's: [elapsedAtReceipt] is the desktop's own
/// `now_ms - since_ms`, and [receivedAt] is this device's clock when that
/// answer arrived. Time since then is measured on this device's clock alone.
class StateSince {
  const StateSince({required this.elapsedAtReceipt, required this.receivedAt});

  final Duration elapsedAtReceipt;
  final DateTime receivedAt;

  /// The time in the state at [now] (this device's clock). Never negative,
  /// and never less than the desktop said, even if the device clock steps
  /// back.
  Duration elapsed(DateTime now) {
    final since = now.difference(receivedAt);
    return elapsedAtReceipt + (since.isNegative ? Duration.zero : since);
  }

  @override
  bool operator ==(Object other) =>
      other is StateSince &&
      other.elapsedAtReceipt == elapsedAtReceipt &&
      other.receivedAt == receivedAt;

  @override
  int get hashCode => Object.hash(elapsedAtReceipt, receivedAt);

  @override
  String toString() =>
      'StateSince(${elapsedAtReceipt.inMilliseconds} ms at $receivedAt)';
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

    /// What the agent is doing (`agent_status` on the LAN, `state` in the
    /// cloud list). Null when not reported. Not read from an agent's own JSON:
    /// it arrives in a separate map, see `peer_fields.dart`.
    @JsonKey(includeFromJson: false, includeToJson: false) AgentState? state,

    /// How long it has been in [state]; LAN only, and only when the desktop
    /// sent both `since_ms` and `now_ms`.
    @JsonKey(includeFromJson: false, includeToJson: false)
    StateSince? stateSince,

    /// For a state read from the cloud list: when the relay received that
    /// record (the relay's clock), so the chip can say how old it is.
    @JsonKey(includeFromJson: false, includeToJson: false) DateTime? stateAsOf,
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
