import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final updateSetting = ref.read(updateSettingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (s) => ListView(
          children: [
            const _SectionHeader('Terminal'),
            ListTile(
              title: const Text('Font Size'),
              subtitle: Text('${s.termFontSize.toInt()}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => updateSetting(
                        'term:fontsize', (s.termFontSize - 1).clamp(8, 32)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => updateSetting(
                        'term:fontsize', (s.termFontSize + 1).clamp(8, 32)),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Copy on Select'),
              value: s.termCopyOnSelect,
              onChanged: (v) => updateSetting('term:copyonselect', v),
            ),
            ListTile(
              title: const Text('Scrollback Lines'),
              subtitle: Text('${s.termScrollback}'),
            ),
            const _SectionHeader('AI'),
            ListTile(
              title: const Text('Model'),
              subtitle: Text(s.aiModel.isNotEmpty ? s.aiModel : 'Default'),
            ),
            ListTile(
              title: const Text('Preset'),
              subtitle: Text(s.aiPreset.isNotEmpty ? s.aiPreset : 'Default'),
            ),
            const _SectionHeader('Privacy'),
            SwitchListTile(
              title: const Text('Telemetry'),
              subtitle: const Text(
                  'Help improve AgentMux by sending anonymous usage data'),
              value: s.telemetryEnabled,
              onChanged: (v) => updateSetting('telemetry:enabled', v),
            ),
            const _SectionHeader('About'),
            const ListTile(
              title: Text('AgentMux Mobile'),
              subtitle: Text('Version 0.1.0'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
