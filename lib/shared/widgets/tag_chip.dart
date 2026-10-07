import 'package:flutter/material.dart';

import '../../core/discovery/host_tree.dart';
import '../../core/discovery/models/lan_instance.dart';
import '../../core/fleet/fleet_store.dart';
import '../theme/app_theme.dart';

/// A small label next to a host, channel or agent name: platform, route, or
/// where an agent runs (`SPEC_FLEET_HOST_TAGS_AND_CLOUD_HOSTS_2026_10_06.md`
/// section 4). One widget so every tag on the screen reads alike.
///
/// [filled] tints the background instead of drawing a border, as the
/// desktop's HOST/SANDBOX tag does.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    this.color = AppColors.textSecondary,
    this.filled = false,
    this.tooltip,
  });

  final String label;
  final Color color;
  final bool filled;
  final String? tooltip;

  /// `Windows` / `macOS` / `Linux`.
  factory TagChip.platform(HostPlatform platform, {Key? key}) => TagChip(
        key: key,
        label: platformLabel(platform),
      );

  /// `LAN`, `Cloud`, `LAN + Cloud` or `Direct`.
  factory TagChip.route(ChannelRoute route, {Key? key}) => TagChip(
        key: key,
        label: routeLabel(route),
        color: switch (route) {
          ChannelRoute.lan => AppColors.success,
          ChannelRoute.cloud => AppColors.primary,
          ChannelRoute.lanAndCloud => const Color(0xFF2DD4BF),
          ChannelRoute.direct => const Color(0xFFA78BFA),
        },
        tooltip: routeTooltip(route),
      );

  /// `HOST` / `SANDBOX`, in the desktop `RuntimeBadge` tag's colours.
  factory TagChip.agentKind(AgentKind kind, {Key? key}) => switch (kind) {
        AgentKind.host => TagChip(
            key: key,
            label: 'HOST',
            color: const Color(0xFFF59E0B),
            filled: true,
            tooltip: 'Runs directly on the machine',
          ),
        AgentKind.container => TagChip(
            key: key,
            label: 'SANDBOX',
            color: AppColors.textPrimary,
            filled: true,
            tooltip: 'Runs in an isolated container',
          ),
      };

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.1 : 0),
        borderRadius: BorderRadius.circular(4),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
    final tip = tooltip;
    return tip == null ? chip : Tooltip(message: tip, child: chip);
  }
}

String platformLabel(HostPlatform p) => switch (p) {
      HostPlatform.windows => 'Windows',
      HostPlatform.macos => 'macOS',
      HostPlatform.linux => 'Linux',
    };

String routeLabel(ChannelRoute r) => switch (r) {
      ChannelRoute.lan => 'LAN',
      ChannelRoute.cloud => 'Cloud',
      ChannelRoute.lanAndCloud => 'LAN + Cloud',
      ChannelRoute.direct => 'Direct',
    };

String routeTooltip(ChannelRoute r) => switch (r) {
      ChannelRoute.lan => 'Reached on this network',
      ChannelRoute.cloud => 'Reached through the cloud',
      ChannelRoute.lanAndCloud =>
        'On this network and in the cloud; reached on this network',
      ChannelRoute.direct => 'Reached directly at the address you entered',
    };
