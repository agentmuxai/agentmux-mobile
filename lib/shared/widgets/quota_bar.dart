import 'package:flutter/material.dart';

import '../../core/models/usage.dart';
import '../theme/app_theme.dart';

class QuotaBar extends StatelessWidget {
  const QuotaBar({super.key, required this.item});

  final QuotaItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.isExhausted
        ? AppColors.error
        : item.isNearLimit
            ? AppColors.warning
            : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _label(item.resource),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              '${item.used} / ${item.limit}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: item.fraction,
            minHeight: 6,
            backgroundColor: AppColors.surfaceVariant,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  String _label(String resource) => switch (resource) {
        'jekt_messages' => 'Messages',
        'drone_runs' => 'Drone runs',
        'emails' => 'Emails',
        _ => resource,
      };
}
