// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'agent.freezed.dart';
part 'agent.g.dart';

@freezed
class Agent with _$Agent {
  const factory Agent({
    required String id,
    @JsonKey(name: 'last_seen') required String lastSeen,
    @JsonKey(name: 'messages_sent') @Default(0) int messagesSent,
  }) = _Agent;

  factory Agent.fromJson(Map<String, dynamic> json) => _$AgentFromJson(json);
}

extension AgentLastSeenX on Agent {
  Duration get lastSeenAgo {
    try {
      final t = DateTime.parse(lastSeen);
      return DateTime.now().toUtc().difference(t.toUtc()).abs();
    } catch (_) {
      return const Duration(days: 999);
    }
  }

  // Traffic-light status based on last_seen age.
  AgentStatus get status {
    final ago = lastSeenAgo;
    if (ago.inMinutes < 5) return AgentStatus.active;
    if (ago.inHours < 1) return AgentStatus.idle;
    return AgentStatus.offline;
  }
}

enum AgentStatus { active, idle, offline }
