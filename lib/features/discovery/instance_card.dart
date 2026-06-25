import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/models/lan_instance.dart';

class InstanceCard extends StatelessWidget {
  const InstanceCard({super.key, required this.instance});
  final LanInstance instance;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.computer, color: Colors.greenAccent),
        title: Text(
          instance.hostname,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'v${instance.version}  •  ${instance.address}:${instance.port}',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
        initiallyExpanded: true,
        children: [
          if (instance.agents.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'No agents reported.',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            ...instance.agents.map(
              (agent) => _AgentRow(agent: agent, instance: instance),
            ),
        ],
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent, required this.instance});
  final LanAgent agent;
  final LanInstance instance;

  @override
  Widget build(BuildContext context) {
    final lastSeen = agent.lastSeen;
    final isActive = lastSeen != null && _isRecent(lastSeen);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(
        Icons.circle,
        size: 10,
        color: isActive ? Colors.greenAccent : Colors.white24,
      ),
      title: Text(agent.name),
      subtitle: lastSeen != null
          ? Text(
              lastSeen,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            )
          : null,
      onTap: () => context.push(
        '/instance/${instance.address}:${instance.port}/agent/${agent.name}',
        extra: {'instance': instance, 'agent': agent},
      ),
    );
  }

  bool _isRecent(String lastSeen) {
    try {
      final dt = DateTime.parse(lastSeen);
      return DateTime.now().difference(dt).inMinutes < 5;
    } catch (_) {
      return false;
    }
  }
}
