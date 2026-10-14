import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/viewer/paired_host.dart';
import '../../core/viewer/pairing_service.dart';
import '../../core/viewer/paired_hosts_repository.dart';
import '../../core/viewer/viewer_client.dart';

/// What the channel list knows about a paired computer's terminals.
sealed class ChannelPanes {
  const ChannelPanes();
}

/// The computer's terminals, in its order (window, then tab, then position),
/// and whether it lets this device watch them.
class PanesListed extends ChannelPanes {
  const PanesListed(this.terminals, {required this.shared});
  final List<ViewerPane> terminals;
  final bool shared;
}

/// The computer's AgentMux can't list its panes (404).
class PanesTooOld extends ChannelPanes {
  const PanesTooOld();
}

/// The computer didn't answer.
class PanesUnreachable extends ChannelPanes {
  const PanesUnreachable();
}

/// The computer refused this device's pairing: it was unpaired there.
class PanesUnpaired extends ChannelPanes {
  const PanesUnpaired();
}

/// Which paired computer, by where it was reached.
typedef PanesKey = ({String pairId, String host, int port});

PanesKey panesKeyOf(PairingMatch pairing) =>
    (pairId: pairing.paired.id, host: pairing.host, port: pairing.port);

/// A paired computer's terminals for the channel list
/// (`PLAN_CHANNEL_AS_ONE_LIST_2026_10_13.md` step 1). Read when the channel's
/// rows are shown, and again on pull-to-refresh; dropped when they aren't.
final channelPanesProvider =
    FutureProvider.autoDispose.family<ChannelPanes, PanesKey>((ref, key) async {
  final hosts = ref.read(pairedHostsProvider);
  final paired = hosts.where((h) => h.id == key.pairId).firstOrNull;
  if (paired == null || paired.invalid) return const PanesUnpaired();
  final client = ref.read(viewerClientFactoryProvider)(
    host: key.host,
    port: key.port,
    fingerprint: paired.fingerprint,
    token: paired.token,
  );
  try {
    final result = await client.panes();
    return PanesListed(
      [
        for (final p in result.panes)
          if (p.kind == PaneKind.terminal) p,
      ],
      shared: result.terminalsShared,
    );
  } on ViewerUnauthorized {
    await ref.read(pairedHostsProvider.notifier).markInvalid(paired.id);
    return const PanesUnpaired();
  } on ViewerNotFound {
    return const PanesTooOld();
  } catch (_) {
    return const PanesUnreachable();
  } finally {
    client.close();
  }
});

/// A terminal's title: its label, else what it is.
String terminalTitle(ViewerPane pane) =>
    pane.label.isNotEmpty ? pane.label : (pane.parentBlockId != null ? "Agent's shell" : 'Terminal');

/// A terminal row's second line: whether it runs, and that it opens here.
String terminalSubtitle(ViewerPane pane) => [
      if (pane.parentBlockId != null && pane.label.isNotEmpty) "Agent's shell",
      switch (pane.running) {
        true => 'running',
        false => 'stopped',
        null => null,
      },
      'watch live',
    ].whereType<String>().join(' · ');

/// The terminals at the end of a paired channel's list, flattened in the
/// desktop's order; the tab is a label on the right, never a group.
class ChannelTerminals extends ConsumerWidget {
  const ChannelTerminals({super.key, required this.pairing, required this.indent});
  final PairingMatch pairing;
  final double indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = panesKeyOf(pairing);
    final state = ref.watch(channelPanesProvider(key));
    // Nothing while the first read runs: the list doesn't jump twice.
    final panes = state.valueOrNull;
    if (panes == null) return const SizedBox.shrink();
    return switch (panes) {
      PanesListed(:final terminals) when terminals.isEmpty => const SizedBox.shrink(),
      PanesListed(:final terminals, shared: false) => _Note(
          '${terminals.length} ${terminals.length == 1 ? 'terminal' : 'terminals'} · '
          'turn on Share terminals on the computer to watch them here',
          indent: indent,
        ),
      PanesListed(:final terminals) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final t in terminals)
              TerminalRow(
                key: ValueKey('terminal:${t.blockId}'),
                pane: t,
                indent: indent,
                onTap: () => openTerminal(context, pairing, t),
              ),
          ],
        ),
      PanesTooOld() => _Note("This computer can't list its terminals: update AgentMux on it", indent: indent),
      PanesUnreachable() => _Note(
          "Couldn't list terminals · tap to try again",
          indent: indent,
          onTap: () => ref.invalidate(channelPanesProvider(key)),
        ),
      // The channel's own row already says the pairing is gone.
      PanesUnpaired() => const SizedBox.shrink(),
    };
  }
}

/// One terminal: its title, the tab it is in, and whether it runs.
class TerminalRow extends StatelessWidget {
  const TerminalRow({super.key, required this.pane, required this.indent, this.onTap});
  final ViewerPane pane;
  final double indent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: indent, right: 16),
      leading: const Icon(Icons.terminal, size: 16, color: Colors.white70),
      title: Row(
        children: [
          Expanded(
            child: Text(terminalTitle(pane), overflow: TextOverflow.ellipsis),
          ),
          if (pane.tab.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                pane.tab,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        terminalSubtitle(pane),
        style: const TextStyle(fontSize: 12, color: Colors.white54),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {required this.indent, this.onTap});
  final String text;
  final double indent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = Padding(
      padding: EdgeInsets.fromLTRB(indent, 4, 16, 10),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.white38)),
    );
    return onTap == null ? line : InkWell(onTap: onTap, child: line);
  }
}

/// Opens [pane] read-only, on the terminal screen.
void openTerminal(BuildContext context, PairingMatch pairing, ViewerPane pane) {
  context.push(
    '/viewer/${Uri.encodeComponent(pairing.paired.id)}'
    '/terminal/${Uri.encodeComponent(pane.blockId)}',
    extra: {'pairing': pairing, 'label': terminalTitle(pane)},
  );
}
