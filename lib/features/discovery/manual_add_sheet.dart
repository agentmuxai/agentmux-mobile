import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_provider.dart';
import '../../shared/theme/app_theme.dart';

class ManualAddSheet extends ConsumerStatefulWidget {
  const ManualAddSheet({super.key});

  @override
  ConsumerState<ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends ConsumerState<ManualAddSheet> {
  final _addressCtrl = TextEditingController();
  final _authKeyCtrl = TextEditingController();
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _addressCtrl.dispose();
    _authKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final raw = _addressCtrl.text.trim();
    final authKey = _authKeyCtrl.text.trim();

    if (raw.isEmpty || authKey.isEmpty) {
      setState(() => _error = 'Address and auth key are required.');
      return;
    }

    // Parse host:port
    final lastColon = raw.lastIndexOf(':');
    if (lastColon < 0) {
      setState(() => _error = 'Enter address as host:port (e.g. 10.0.2.2:59151).');
      return;
    }
    final host = raw.substring(0, lastColon);
    final port = int.tryParse(raw.substring(lastColon + 1));
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Invalid port number.');
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      await ref.read(discoveryProvider.notifier).addManual(host, port, authKey);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Could not connect — check address and auth key.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scrolls when the keyboard leaves less room than the form needs (a
    // landscape phone): it overflowed there and hid the Connect button.
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Connect manually',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close, color: context.palette.textMuted),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Enter the address and auth key shown in AgentMux → Settings.',
            style: TextStyle(color: context.palette.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _addressCtrl,
            autofocus: true,
            keyboardType: TextInputType.url,
            style: TextStyle(color: context.palette.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: 'host:port  (e.g. 10.0.2.2:59151)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _authKeyCtrl,
            obscureText: true,
            style: TextStyle(
                color: context.palette.textPrimary,
                fontSize: 14,
                fontFamily: 'monospace'),
            decoration: const InputDecoration(
              labelText: 'Auth key',
              hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style:
                    TextStyle(color: context.palette.error, fontSize: 12)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _connecting ? null : _connect,
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.primary,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _connecting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

void showManualAddSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // Keeps the sheet out of the notch / Dynamic Island side insets in landscape.
    useSafeArea: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const ManualAddSheet(),
  );
}
