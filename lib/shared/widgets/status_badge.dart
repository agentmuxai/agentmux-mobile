import 'package:flutter/material.dart';

import '../../core/models/agent.dart';
import '../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final AgentStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (status) {
          AgentStatus.active => AppColors.success,
          AgentStatus.idle => AppColors.warning,
          AgentStatus.offline => AppColors.textMuted,
        },
      ),
    );
  }
}
