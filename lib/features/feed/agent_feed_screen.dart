import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/models/lan_instance.dart';
import '../../core/discovery/peer_fields.dart';
import '../../core/fleet/fleet_store.dart';
import '../../core/viewer/device_key_store.dart';
import '../../core/viewer/paired_host.dart';
import '../../core/viewer/paired_hosts_repository.dart';
import '../../core/viewer/pairing_service.dart';
import '../../core/viewer/viewer_client.dart';
import '../../core/viewer/feed_events.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/agent_state_chip.dart';
import '../../shared/widgets/tag_chip.dart';
import '../discovery/qr_scan_screen.dart';
import 'feed_controller.dart';
import 'send_controller.dart';
import 'send_panel.dart';
import 'feed_theme.dart';
import 'feed_disclosure.dart';
import 'tool_meta.dart';
import 'transcript.dart';
import 'transcript_view.dart';
import 'working_row.dart';

/// One agent's pane, live and read-only, over the pinned connection of a
/// paired computer (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` 6.2).
///
/// A computer that takes messages from this device gets a composer under the
/// feed; one that does not says why in the menu's "Send a message…".
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

  /// The discovered channel the agent was tapped in.
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

  /// Which rows are open (the desktop's rules).
  final _disclosure = FeedDisclosure();

  /// The jekts already shown, to see which just arrived.
  final _jekts = <int>{};

  /// Each tool call's state at the last update, to see which just finished.
  final _seen = <int, ToolState>{};

  /// Keys on the rows of running and held calls, to tell whether they are
  /// on screen.
  final _anchors = <int, GlobalKey>{};
  final _listKey = GlobalKey();

  /// Where each held row's bottom last was in the list's content: the
  /// scroll offset at which it leaves the top.
  final _heldBottom = <int, double>{};

  /// The transcript the state above belongs to. A snapshot or reset makes a
  /// new transcript whose item keys start again at 0, so it is dropped with
  /// the old one rather than opening unrelated tool calls.
  Transcript? _disclosureFor;

  /// Sends this agent messages; null while the pairing is refused.
  SendController? _send;

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
    _send = SendController(
      clientFor: ref.read(viewerClientFactoryProvider),
      pairing: _pairing,
      agent: widget.agent.name,
      keys: ref.read(deviceKeyStoreProvider),
      onUnauthorized: () => unawaited(
        ref.read(pairedHostsProvider.notifier).markInvalid(paired.id),
      ),
    );
    _send!.addListener(_onSend);
    unawaited(_send!.checkGrant());
    feed.start();
  }

  void _disconnect() {
    _send?.dispose();
    _send = null;
    _feed
      ?..removeListener(_onFeed)
      ..dispose();
    _feed = null;
    _client?.close();
    _client = null;
  }

  /// The grant or what was sent changed: the menu follows the grant.
  void _onSend() {
    if (mounted) setState(() {});
  }

  FeedConnection? _lastConnection;

  void _onFeed() {
    if (!mounted) return;
    final transcript = _feed?.transcript;
    // What this phone sent is no longer "Sending…" once the feed shows it.
    if (transcript != null && _send?.messages.isNotEmpty == true) {
      _send!.shown(transcript.hasPhoneMessage);
    }
    // Back from a lost connection: the computer's answer on sending may have
    // changed (it was switched on, or this device was paired again).
    final connection = _feed?.connection;
    if (connection == FeedConnection.live && _lastConnection != FeedConnection.live && _send?.grant != SendGrant.allowed) {
      unawaited(_send?.checkGrant());
    }
    _lastConnection = connection;
    _trackTools(transcript);
    setState(() {});
    if (_follow) _scrollToEndAfterFrame();
  }

  /// Holds open a call that finished on screen; the layout is still the one
  /// it was drawn in while running.
  void _trackTools(Transcript? transcript) {
    if (!identical(transcript, _disclosureFor)) {
      _disclosure.clear();
      _seen.clear();
      _anchors.clear();
      _heldBottom.clear();
      _jekts.clear();
      _disclosureFor = transcript;
      if (transcript == null) return;
      for (final item in transcript.items) {
        if (item is ToolCallItem) _seen[item.key] = item.state;
        if (item is JektItem) _jekts.add(item.key);
      }
      return;
    }
    if (transcript == null) return;
    final live = <int>{};
    for (final item in transcript.items) {
      // A jekt that arrives while the latest output is in view is held open
      // until it scrolls off, as on the desktop.
      if (item is JektItem && _jekts.add(item.key) && _follow) {
        _disclosure.hold(item.key);
      }
      if (item is! ToolCallItem) continue;
      live.add(item.key);
      final before = _seen[item.key];
      _seen[item.key] = item.state;
      if (before == ToolState.running &&
          item.state != ToolState.running &&
          !isDismissed(item.state) &&
          _onScreen(item.key)) {
        _disclosure.hold(item.key);
        _heldBottom.remove(item.key);
      }
    }
    _seen.removeWhere((k, _) => !live.contains(k));
    _anchors.removeWhere((k, _) =>
        (!live.contains(k) && !_jekts.contains(k)) ||
        (_seen[k] != ToolState.running && !_disclosure.held.contains(k)));
    _heldBottom.removeWhere((k, _) => !_disclosure.held.contains(k));
  }

  /// Where row [key] is against the list's viewport: null when not laid out.
  ({double top, double bottom, double height})? _rowBox(int key) {
    final row = _anchors[key]?.currentContext?.findRenderObject();
    final list = _listKey.currentContext?.findRenderObject();
    if (row is! RenderBox || list is! RenderBox || !row.attached || !list.attached) {
      return null;
    }
    final top = row.localToGlobal(Offset.zero, ancestor: list).dy;
    return (top: top, bottom: top + row.size.height, height: list.size.height);
  }

  /// Where row [key]'s bottom is in the list's content (the scroll offset at
  /// which it leaves the top), or null when it isn't laid out.
  double? _rowContentBottom(int key) {
    final row = _anchors[key]?.currentContext?.findRenderObject();
    if (row is! RenderBox || !row.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(row);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(row, 0).offset + row.size.height;
  }

  bool _onScreen(int key) {
    final b = _rowBox(key);
    return b != null && b.bottom > 0 && b.top < b.height;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final atEnd = p.pixels >= p.maxScrollExtent - 48;
    // A held row closes once it scrolls off the top, not the bottom. The
    // list drops rows past either edge, so its place is kept in content
    // terms, which don't depend on the scroll offset. (A scroll
    // notification comes before the list is laid out at the new offset, so
    // a row's place in the viewport is a frame behind the offset.)
    final gone = <int>[];
    for (final k in _disclosure.held) {
      final contentBottom = _rowContentBottom(k) ?? _heldBottom[k];
      if (contentBottom == null) continue;
      _heldBottom[k] = contentBottom;
      if (contentBottom - p.pixels < 0) gone.add(k);
    }
    for (final k in gone) {
      _disclosure.release(k);
      _heldBottom.remove(k);
    }
    if (atEnd != _follow || gone.isNotEmpty) setState(() => _follow = atEnd);
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
          // Only when the computer has said it takes no messages from this
          // device: the menu then says why.
          if (_menuSend)
            PopupMenuButton<_FeedMenu>(
              tooltip: 'More',
              onSelected: (action) => switch (action) {
                _FeedMenu.sendMessage => _sendFromMenu(),
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
      body: Column(
        children: [
          Expanded(child: _body(connection, feed?.transcript)),
          if (_send != null && !_pairing.paired.invalid)
            SendPanel(
              controller: _send!,
              draftKey: '${_pairing.paired.id}/${widget.agent.name}',
              canSend: connection == FeedConnection.live,
              agentWorking: parseAgentState(feed?.status?.state) == AgentState.working,
              onSent: _jumpToLatest,
            ),
        ],
      ),
    );
  }

  /// Whether the header has a "Send a message…" menu: when the computer has
  /// said it takes none from this device, so the menu can say why. With the
  /// composer there is no menu.
  bool get _menuSend => sendGrantText(_send?.grant) != null;

  void _sendFromMenu() {
    final grant = _send?.grant;
    final why = sendGrantText(grant);
    if (why == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(why),
      action: grant == SendGrant.pairAgain
          ? SnackBarAction(label: 'Pair again', onPressed: _pairAgain)
          : null,
    ));
  }

  /// The row at the bottom: what the agent is doing, or how the last turn
  /// went. The agent's state comes from the feed's `status` events, timed
  /// on this device's clock as the header's chip is.
  Widget _workingRow(Transcript transcript) {
    final feed = _feed;
    final status = feed?.status;
    final receivedAt = feed?.statusReceivedAt;
    final state = status == null ? null : parseAgentState(status.state);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FeedSpace.s3),
      child: WorkingRow(
        turn: transcript.turn,
        runningTool: transcript.runningTool,
        compacting: transcript.compacting,
        state: state,
        connected: feed?.connection == FeedConnection.live,
        since: status == null || receivedAt == null
            ? null
            : stateSinceFrom(
                sinceMs: parseUnixMs(status.sinceMs),
                nowMs: parseUnixMs(status.nowMs),
                receivedAt: receivedAt,
              ),
      ),
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
    if (!identical(transcript, _disclosureFor)) _trackTools(transcript);
    final items = transcript.items;
    if (items.isEmpty) {
      return const _Message(icon: null, title: 'Nothing here yet.', detail: null);
    }
    return Stack(
      children: [
        ListView.builder(
          key: _listKey,
          controller: _scroll,
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          // The working row comes last.
          itemCount: items.length + 1,
          itemBuilder: (_, i) {
            if (i == items.length) return _workingRow(transcript);
            final item = items[i];
            if (!FeedDisclosure.opens(item)) {
              return TranscriptItemView(key: ValueKey(item.key), item: item);
            }
            final anchor = (item is ToolCallItem && item.state == ToolState.running) ||
                    _disclosure.held.contains(item.key)
                ? _anchors.putIfAbsent(item.key, GlobalKey.new)
                : null;
            return KeyedSubtree(
              key: ValueKey(item.key),
              child: TranscriptItemView(
                key: anchor,
                item: item,
                expanded: _disclosure.isOpen(item),
                onToggle: () => setState(() => _disclosure.toggle(item)),
              ),
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
