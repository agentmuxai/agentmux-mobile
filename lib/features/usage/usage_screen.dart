import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/quota_bar.dart';
import 'usage_provider.dart';

class UsageScreen extends ConsumerWidget {
  const UsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usageAsync = ref.watch(usageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usage & Billing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(usageProvider.notifier).refresh(),
          ),
        ],
      ),
      body: usageAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Text(e.toString(),
              style: const TextStyle(color: AppColors.textSecondary)),
        ),
        data: (summary) => RefreshIndicator(
          onRefresh: () => ref.read(usageProvider.notifier).refresh(),
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TierBanner(tier: summary.tier),
              const SizedBox(height: 20),
              const Text(
                'Monthly quota',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...summary.quotas.map((q) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: QuotaBar(item: q),
                  )),
              if (summary.isFree) ...[
                const SizedBox(height: 8),
                const Text(
                  'Resets at the start of each billing period.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TierBanner extends StatelessWidget {
  const _TierBanner({required this.tier});
  final String tier;

  @override
  Widget build(BuildContext context) {
    final isFree = tier == 'free';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            isFree ? Icons.star_border : Icons.star,
            color: isFree ? AppColors.textMuted : AppColors.warning,
            size: 20,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFree ? 'Free tier' : 'Pro',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                isFree
                    ? 'Upgrade at cloud.agentmux.ai/billing'
                    : 'Metered billing active',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
