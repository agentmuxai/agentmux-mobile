import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/discovery/models/lan_instance.dart';
import '../../core/fleet/fleet_store.dart';
import '../../core/viewer/paired_host.dart';
import '../../core/viewer/paired_hosts_repository.dart';
import '../../core/viewer/pairing_service.dart';
import '../../core/viewer/viewer_client.dart';
import '../../shared/theme/app_theme.dart';

/// One tab's panes, in the desktop's order.
class PaneTabGroup {
  PaneTabGroup({required this.tabId, required this.name, required this.active});
  final String tabId;
  final String name;
  final bool active;
  final List<ViewerPane> panes = [];
}

/// One window's tabs.
class PaneWindowGroup {
  PaneWindowGroup({required this.windowId, required this.name});
  final String windowId;
  final String name;
  final List<PaneTabGroup> tabs = [];
}

/// The desktop's flat, ordered list as windows and tabs, keeping its order.
List<PaneWindowGroup> groupPanes(List<ViewerPane> panes) {
  final windows = <PaneWindowGroup>[];
  for (final p in panes) {
    var window = windows.where((w) => w.windowId == p.windowId).firstOrNull;
    if (window == null) {
      window = PaneWindowGroup(windowId: p.windowId, name: p.window);
      windows.add(window);
    }
    var tab = window.tabs.where((t) => t.tabId == p.tabId).firstOrNull;
    if (tab == null) {
      tab = PaneTabGroup(tabId: p.tabId, name: p.tab, active: p.tabActive);
      window.tabs.add(tab);
    }
    tab.panes.add(p);
  }
  return windows;
}

/// Every pane of a paired computer, window by window and tab by tab
/// (`docs/reports/REPORT_PANE_LIST_TERMINALS_AND_FROZEN_FEED_2026_10_12.md`
/// §2.5, phase A). Agents open their live feed; terminals say whether they
/// run; every other pane is listed by name and opens on the computer.
/// Read-only, like the feed.
class PanesScreen extends ConsumerStatefulWidget {
  const PanesScreen({
    super.key,
    required this.pairing,
    required this.instance,
    this.channel,
    this.route,
  });

  final PairingMatch pairing;

  /// The discovered channel the list was opened from, for the feed screen.
  final LanInstance instance;
  final String? channel;
  final ChannelRoute? route;

  @override
  ConsumerState<PanesScreen> createState() => _PanesScreenState();
}

enum _Failure { unpaired, tooOld, unreachable }

class _PanesScreenState extends ConsumerState<PanesScreen> {
  List<ViewerPane>? _panes;
  _Failure? _failure;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paired = widget.pairing.paired;
    if (paired.invalid) {
      setState(() => _failure = _Failure.unpaired);
      return;
    }
    setState(() => _loading = true);
    final client = ref.read(viewerClientFactoryProvider)(
      host: widget.pairing.host,
      port: widget.pairing.port,
      fingerprint: paired.fingerprint,
      token: paired.token,
    );
    try {
      final panes = await client.panes();
      if (!mounted) return;
      setState(() {
        _panes = panes;
        _failure = null;
      });
    } on ViewerUnauthorized {
      await ref.read(pairedHostsProvider.notifier).markInvalid(paired.id);
      if (mounted) setState(() => _failure = _Failure.unpaired);
    } on ViewerNotFound {
      if (mounted) setState(() => _failure = _Failure.tooOld);
    } catch (_) {
      if (mounted) setState(() => _failure = _Failure.unreachable);
    } finally {
      client.close();
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openAgent(String name) {
    final location = '/viewer/${Uri.encodeComponent(widget.pairing.paired.id)}'
        '/agent/${Uri.encodeComponent(name)}';
    context.push(location, extra: {
      'pairing': widget.pairing,
      'instance': widget.instance,
      'agent': LanAgent(name: name),
      'route': widget.route,
      'channel': widget.channel,
    });
  }

  @override
  Widget build(BuildContext context) {
    final where = [
      widget.pairing.paired.hostname,
      if (widget.channel != null) widget.channel!,
    ].join('  •  ');
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Panes'),
            Text(
              where,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    final panes = _panes;
    final failure = _failure;
    // Unpaired: the list is gone with the pairing (its agents' feeds would
    // be refused). Any other failure keeps a list already shown, with a note.
    if (failure != null && (panes == null || failure == _Failure.unpaired)) {
      final (title, detail) = switch (failure) {
        _Failure.unpaired => (
            'This device was unpaired on the computer',
            'Pair again to see its panes.',
          ),
        _Failure.tooOld => (
            'This computer can\'t list its panes',
            'Update AgentMux on the computer.',
          ),
        _Failure.unreachable => (
            'Can\'t reach the computer',
            'Check that this device is on the same network.',
          ),
      };
      return _Message(
        title: title,
        detail: detail,
        action: failure == _Failure.unreachable
            ? FilledButton(onPressed: _load, child: const Text('Try again'))
            : null,
      );
    }
    if (panes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (panes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            _Message(title: 'No panes open.', detail: null),
          ],
        ),
      );
    }
    final windows = groupPanes(panes);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                failure == _Failure.tooOld
                    ? "Couldn't refresh: this computer can't list its panes."
                    : "Couldn't refresh: can't reach the computer. "
                        'This is the list from before.',
                style: const TextStyle(fontSize: 12, color: AppColors.warning),
              ),
            ),
          for (final (i, w) in windows.indexed) ...[
            if (windows.length > 1)
              _Header(
                text: w.name.isEmpty ? 'Window ${i + 1}' : w.name,
                top: true,
              ),
            for (final t in w.tabs) ...[
              _Header(text: t.name.isEmpty ? 'Tab' : t.name, active: t.active),
              for (final p in t.panes)
                PaneRow(
                  key: ValueKey(p.blockId),
                  pane: p,
                  onOpen: p.kind == PaneKind.agent && p.agent != null
                      ? () => _openAgent(p.agent!)
                      : null,
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.text, this.active = false, this.top = false});
  final String text;
  final bool active;
  final bool top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, top ? 20 : 14, 16, 4),
      child: Row(
        children: [
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: top ? 15 : 13,
                fontWeight: FontWeight.w600,
                color: top ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 8),
            const Text(
              'shown',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// One pane: what it is, and what tapping it does.
class PaneRow extends StatelessWidget {
  const PaneRow({super.key, required this.pane, this.onOpen});
  final ViewerPane pane;

  /// Null when the pane opens only on the computer.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final shell = pane.parentBlockId != null;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: shell ? 40 : 16, right: 16),
      leading: Icon(paneIcon(pane), size: 20, color: Colors.white70),
      title: Text(
        pane.label.isEmpty ? paneTypeName(pane) : pane.label,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        paneSubtitle(pane),
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
      trailing: onOpen == null ? null : const Icon(Icons.chevron_right),
      onTap: onOpen,
    );
  }
}

IconData paneIcon(ViewerPane pane) => switch (pane.kind) {
      PaneKind.agent => Icons.smart_toy_outlined,
      PaneKind.terminal => Icons.terminal,
      PaneKind.other => switch (pane.view) {
          'editor' || 'codeeditor' => Icons.description_outlined,
          'browser' || 'preview' => Icons.public,
          'files' => Icons.folder_outlined,
          'media' => Icons.perm_media_outlined,
          'sysinfo' || 'tower' => Icons.monitor_heart_outlined,
          'help' => Icons.help_outline,
          'settings' => Icons.settings_outlined,
          _ => Icons.widgets_outlined,
        },
    };

/// What a pane is, in words: "Editor", "Browser", a widget's id.
String paneTypeName(ViewerPane pane) => switch (pane.kind) {
      PaneKind.agent => 'Agent',
      PaneKind.terminal => 'Terminal',
      PaneKind.other => switch (pane.view) {
          'editor' || 'codeeditor' => 'Editor',
          'browser' || 'preview' => 'Browser',
          'files' => 'Files',
          'media' => 'Media',
          'sysinfo' => 'System info',
          'tower' => 'Tower',
          'help' => 'Help',
          'settings' => 'Settings',
          'swarm' => 'Swarm',
          'connectors' => 'Connectors',
          'memory' => 'Memory',
          final v when v.startsWith('ext:') => 'Widget',
          '' => 'Pane',
          final v => '${v[0].toUpperCase()}${v.substring(1)}',
        },
    };

/// The row's second line: what the pane is and where it opens.
String paneSubtitle(ViewerPane pane) => switch (pane.kind) {
      PaneKind.agent =>
        pane.agent == null ? 'Agent · not running' : 'Agent · watch live',
      PaneKind.terminal => [
          pane.parentBlockId != null ? 'Agent\'s shell' : 'Terminal',
          switch (pane.running) {
            true => 'running',
            false => 'stopped',
            null => null,
          },
          'opens on the computer',
        ].whereType<String>().join(' · '),
      PaneKind.other => '${paneTypeName(pane)} · opens on the computer',
    };

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.detail, this.action});
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
