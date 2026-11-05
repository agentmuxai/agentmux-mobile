import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/discovery/discovery_provider.dart';
import '../../core/discovery/models/lan_instance.dart';
import '../../core/fleet/fleet_store.dart';

/// What the bottom status line of the discovery screen says, from the
/// discovery result: how the computers are reached, how many there are, and
/// how many agents are working or waiting for the person.
class FleetStatus {
  const FleetStatus({
    required this.connection,
    required this.computers,
    required this.working,
    required this.waiting,
    this.live = false,
  });

  /// "LAN", "Cloud", "LAN + Cloud", or null while nothing is known.
  final String? connection;
  final int computers;
  final int working;
  final int waiting;

  /// Whether at least one computer answered on this network or the cloud list.
  final bool live;

  static const searching = FleetStatus(
    connection: null,
    computers: 0,
    working: 0,
    waiting: 0,
  );

  /// The left half: "LAN · 3 computers". [short] drops the noun for a narrow
  /// screen.
  String left({bool short = false}) {
    if (connection == null) return 'Searching…';
    if (computers == 0) return connection!;
    final noun = short ? '' : (computers == 1 ? ' computer' : ' computers');
    return '$connection · $computers$noun';
  }

  /// The right half: "2 working · 1 needs you"; empty when no agent is.
  /// [short] keeps one count for a narrow screen, the one that asks something
  /// of the person ("1 needs you") before the one that does not.
  String right({bool short = false}) {
    if (short && waiting > 0) return '$waiting needs you';
    final parts = [
      if (working > 0) '$working working',
      if (waiting > 0 && !short) '$waiting needs you',
    ];
    return parts.join(' · ');
  }

  /// One sentence for a screen reader (the line is read as one).
  String get spoken {
    final noun = computers == 1 ? '1 computer' : '$computers computers';
    final l = switch ((connection, computers)) {
      (null, _) => 'Searching for computers',
      (final c?, 0) => c,
      (final c?, _) => '$c, $noun',
    };
    final r = right();
    return r.isEmpty ? l : '$l, $r';
  }
}

FleetStatus summarizeFleet(DiscoveryState state) {
  switch (state) {
    case DiscoveryScanning():
      return FleetStatus.searching;
    case DiscoveryEmpty():
      return const FleetStatus(
        connection: 'No computers',
        computers: 0,
        working: 0,
        waiting: 0,
      );
    case DiscoveryResults(:final hosts):
      // Only what answers now counts: a stale or gone channel keeps its last
      // agents, and a computer that stopped answering is not "working".
      final routes = <ChannelRoute>{};
      var computers = 0;
      var working = 0;
      var waiting = 0;
      for (final host in hosts) {
        var answering = false;
        for (final channel in host.channels) {
          if (channel.presence != Presence.live) continue;
          answering = true;
          routes.add(channel.route);
          for (final agent in channel.agents) {
            if (agent.state == AgentState.working) working++;
            if (agent.state == AgentState.waiting) waiting++;
          }
        }
        if (answering) computers++;
      }
      return FleetStatus(
        connection: computers == 0 ? 'Offline' : _connection(routes),
        computers: computers,
        working: working,
        waiting: waiting,
        live: computers > 0,
      );
  }
}

/// How the computers are reached, worded like the cards' route badges: "LAN",
/// "Direct", "Cloud", or those joined ("LAN + Cloud"). A channel seen both
/// ways counts for both.
String _connection(Set<ChannelRoute> routes) {
  final lan =
      routes.contains(ChannelRoute.lan) ||
      routes.contains(ChannelRoute.lanAndCloud);
  final cloud =
      routes.contains(ChannelRoute.cloud) ||
      routes.contains(ChannelRoute.lanAndCloud);
  final direct = routes.contains(ChannelRoute.direct);
  return [if (lan) 'LAN', if (direct) 'Direct', if (cloud) 'Cloud'].join(' + ');
}

/// The status line's data, kept current with discovery.
final fleetStatusProvider = Provider<FleetStatus>(
  (ref) => summarizeFleet(ref.watch(discoveryProvider)),
);
