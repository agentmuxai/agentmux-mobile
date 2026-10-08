import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/models/lan_instance.dart';
import '../../core/discovery/peer_fields.dart';
import '../../core/fleet/fleet_store.dart';
import '../../core/viewer/paired_host.dart';
import '../../core/viewer/paired_hosts_repository.dart';
import '../../core/viewer/pairing_service.dart';
import '../../core/viewer/viewer_client.dart';
import '../../core/viewer/feed_events.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/agent_state_chip.dart';
import '../../shared/widgets/tag_chip.dart';
import '../discovery/host_card.dart';
import '../discovery/qr_scan_screen.dart';
import 'feed_controller.dart';
import 'transcript.dart';
import 'transcript_view.dart';

/// One agent's pane, live and read-only, over the pinned connection of a
/// paired computer (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` 6.2).
///
/// No composer: "Send a message…" in the menu opens today's message screen.
/// The stream stops in the background and resumes where it left off on
/// return. What it shows stays in memory and is dropped with the screen.
class AgentFeedScreen extends ConsumerStatefulWidget {
  const AgentFeedScreen({
    super.key,
    required this.pairing,
    required this.agent,
    required this.instance,
    this.channel,
    this.route,
  });

  final PairingMatch pairing;
  final LanAgent agent;

  /// The discovered channel the agent was tapped in, for "Send a message…".
  final LanInstance instance;
  final String? channel;
  final ChannelRoute? route;

  @override
  ConsumerState<AgentFeedScreen> createState() => _AgentFeedScreenState();
}

class _AgentFeedScreenState extends ConsumerState<AgentFeedScreen> {
  late PairingMatch _pairing = widget.pairing;
  ViewerClient? _client;
  FeedController? _feed;
  AppLifecycleListener? _lifecycle;
  final _scroll = ScrollController();

  /// Scrolled to the bottom: new output scrolls into view.
  bool _follow = true;
  final _expanded = <int>{};

  /// The transcript [_expanded] belongs to. A snapshot or reset makes a new
  /// transcript whose item keys start again at 0, so expansions are dropped
  /// with the old one rather than opening unrelated tool calls.
  Transcript? _expandedFor;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: () => _feed?.pause(),
      onResume: () => _feed?.resume(),
    );
    _scroll.addListener(_onScroll);
    _connect();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _disconnect();
    _scroll.dispose();
    super.dispose();
  }

  void _connect() {
    _disconnect();
    final paired = _pairing.paired;
    // Already refused by the computer: say so without asking again.
    if (paired.invalid) return;
    final client = ref.read(viewerClientFactoryProvider)(
      host: _pairing.host,
      port: _pairing.port,
      fingerprint: paired.fingerprint,
      token: paired.token,
    );
    final feed = FeedController(
      source: ({lastEventId}) =>
          client.feed(widget.agent.name, lastEventId: lastEventId),
      onUnauthorized: () => unawaited(
        ref.read(pairedHostsProvider.notifier).markInvalid(paired.id),
      ),
    )..addListener(_onFeed);
    _client = client;
    _feed = feed;
    feed.start();
  }

  void _disconnect() {
    _feed
      ?..removeListener(_onFeed)
      ..dispose();
    _feed = null;
    _client?.close();
    _client = null;
  }

  void _onFeed() {
    if (!mounted) return;
    setState(() {});
    if (_follow) _scrollToEndAfterFrame();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final atEnd = p.pixels >= p.maxScrollExtent - 48;
    if (atEnd != _follow) setState(() => _follow = atEnd);
  }

  void _scrollToEndAfterFrame() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _jumpToLatest() {
    setState(() => _follow = true);
    _scrollToEndAfterFrame();
  }

  Future<void> _pairAgain() async {
    final paired = await showQrScanScreen(context);
    if (!mounted || paired == null) return;
    if (!paired.sameTarget(_pairing.paired)) return;
    setState(() {
      _pairing = PairingMatch(paired: paired, host: paired.host, port: paired.port);
    });
    _connect();
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    final connection = _pairing.paired.invalid
        ? FeedConnection.unauthorized
        : (feed?.connection ?? FeedConnection.connecting);
    final kind = widget.agent.kind;
    final stateChip = feedStateChip(
      agent: widget.agent,
      status: feed?.status,
      statusReceivedAt: feed?.statusReceivedAt,
      live: connection == FeedConnection.live ||
          connection == FeedConnection.connecting,
    );
    final where = [
      _pairing.paired.hostname,
      if (widget.channel != null) widget.channel!,
    ].join('  •  ');
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(widget.agent.name, overflow: TextOverflow.ellipsis),
                ),
                if (kind != null) ...[
                  const SizedBox(width: 8),
                  TagChip.agentKind(kind),
                ],
                if (stateChip != null) ...[
                  const SizedBox(width: 6),
                  stateChip,
                ],
              ],
            ),
            Text(
              where,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          ConnectionIndicator(connection: connection),
          // A paired computer discovery has not found has no fleet endpoint
          // or key to send a message with; only its live feed.
          if (widget.instance.authKey.isNotEmpty)
            PopupMenuButton<_FeedMenu>(
              tooltip: 'More',
              onSelected: (action) => switch (action) {
                _FeedMenu.sendMessage => openMessageScreen(
                    context,
                    widget.instance,
                    widget.agent,
                    route: widget.route,
                  ),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _FeedMenu.sendMessage,
                  child: Text('Send a message…'),
                ),
              ],
            ),
        ],
      ),
      body: _body(connection, feed?.transcript),
    );
  }

  Widget _body(FeedConnection connection, Transcript? transcript) {
    switch (connection) {
      case FeedConnection.unauthorized:
        return _Message(
          icon: Icons.link_off,
          title: unpairedOnComputerText,
          detail: 'Pair again to keep watching this computer\'s agents.',
          action: FilledButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Pair again'),
            onPressed: _pairAgain,
          ),
        );
      case FeedConnection.notFound:
        return const _Message(
          icon: Icons.visibility_off_outlined,
          title: 'This agent can\'t be watched',
          detail: 'It no longer exists on the computer, or it is hidden from '
              'paired devices.',
        );
      case FeedConnection.connecting ||
            FeedConnection.live ||
            FeedConnection.reconnecting ||
            FeedConnection.paused:
        break;
    }
    if (transcript == null) {
      return _Message(
        icon: null,
        title: connection == FeedConnection.reconnecting
            ? 'Can\'t reach the computer. Retrying…'
            : 'Connecting…',
        detail: null,
      );
    }
    if (!identical(transcript, _expandedFor)) {
      _expanded.clear();
      _expandedFor = transcript;
    }
    final items = transcript.items;
    if (items.isEmpty) {
      return const _Message(icon: null, title: 'Nothing here yet.', detail: null);
    }
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final item = items[i];
            return TranscriptItemView(
              key: ValueKey(item.key),
              item: item,
              expanded: _expanded.contains(item.key),
              onToggle: item is ToolCallItem
                  ? () => setState(() {
                        if (!_expanded.remove(item.key)) _expanded.add(item.key);
                      })
                  : null,
            );
          },
        ),
        if (!_follow)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.arrow_downward, size: 18),
                label: const Text('Jump to latest'),
                onPressed: _jumpToLatest,
              ),
            ),
          ),
      ],
    );
  }
}

enum _FeedMenu { sendMessage }

/// The header's status chip (spec 6.2, with phase 1's [AgentStateChip]).
///
/// The feed's latest `status` event wins once one has arrived: its
/// `now_ms - since_ms` is anchored at [statusReceivedAt] on this device's
/// clock, as the host list does with the fleet feed. Until then the chip
/// shows the state the host list had for [agent] when it was tapped. An
/// unknown state shows no chip, never a guess. [live] false (reconnecting,
/// paused) mutes it.
AgentStateChip? feedStateChip({
  required LanAgent agent,
  FeedStatus? status,
  DateTime? statusReceivedAt,
  bool live = true,
}) {
  if (status == null) return AgentStateChip.forAgent(agent, live: live);
  final state = parseAgentState(status.state);
  if (state == null) return null;
  return AgentStateChip(
    state: state,
    since: statusReceivedAt == null
        ? null
        : stateSinceFrom(
            sinceMs: parseUnixMs(status.sinceMs),
            nowMs: parseUnixMs(status.nowMs),
            receivedAt: statusReceivedAt,
          ),
    live: live,
  );
}

const unpairedOnComputerText = 'This device was unpaired on the computer';

/// The header's connection state: `Live`, `Reconnecting…` or `Paused`.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, required this.connection});
  final FeedConnection connection;

  @override
  Widget build(BuildContext context) {
    final (String label, Color color)? shown = switch (connection) {
      FeedConnection.live => ('Live', AppColors.success),
      FeedConnection.connecting => ('Connecting…', AppColors.warning),
      FeedConnection.reconnecting => ('Reconnecting…', AppColors.warning),
      FeedConnection.paused => ('Paused', AppColors.textSecondary),
      FeedConnection.unauthorized || FeedConnection.notFound => null,
    };
    if (shown == null) return const SizedBox.shrink();
    final (label, color) = shown;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData? icon;
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
            if (icon != null) ...[
              Icon(icon, size: 48, color: Colors.white38),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
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
