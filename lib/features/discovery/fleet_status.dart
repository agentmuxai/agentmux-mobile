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
  String get right {
    final parts = [
      if (working > 0) '$working working',
      if (waiting > 0) '$waiting needs you',
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
    return right.isEmpty ? l : '$l, $right';
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
      var lan = false;
      var cloud = false;
      var live = false;
      var working = 0;
      var waiting = 0;
      for (final host in hosts) {
        for (final channel in host.channels) {
          if (channel.route == ChannelRoute.cloud) {
            cloud = true;
          } else {
            lan = true;
          }
          if (channel.presence == Presence.live) live = true;
          for (final agent in channel.agents) {
            if (agent.state == AgentState.working) working++;
            if (agent.state == AgentState.waiting) waiting++;
          }
        }
      }
      return FleetStatus(
        connection: lan && cloud ? 'LAN + Cloud' : (cloud ? 'Cloud' : 'LAN'),
        computers: hosts.length,
        working: working,
        waiting: waiting,
        live: live,
      );
  }
}

/// The status line's data, kept current with discovery.
final fleetStatusProvider = Provider<FleetStatus>(
  (ref) => summarizeFleet(ref.watch(discoveryProvider)),
);
