import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Persistent "you're looking at sample data" banner for demo-mode screens.
/// Deliberately loud (not just a small badge) — the whole point is that
/// nobody, reviewer or user, mistakes demo agents for a real connection.
class DemoBanner extends StatelessWidget implements PreferredSizeWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warning,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: const Text(
        'DEMO DATA — not a live connection',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(28);
}
