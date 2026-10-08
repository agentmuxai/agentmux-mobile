import '../discovery/host_tree.dart';
import 'paired_host.dart';

/// Which of [paired] is [channel]'s pairing, and where its viewer listener
/// is now (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` 13.4).
///
/// Matched by install id when both sides know it, else by hostname and
/// channel name. A cloud-only channel is never matched: it has no LAN
/// endpoint, and its agents keep the cloud screen. [used] holds pairings
/// already given to another channel; each pairing belongs to one channel.
PairingMatch? matchPairing(
  ChannelNode channel,
  List<PairedHost> paired, {
  Set<String> used = const {},
}) {
  if (channel.cloudOnly || paired.isEmpty) return null;
  final via = channel.via;
  // A channel only a sibling reported carries the sibling's instance in
  // [ChannelNode.via]: same machine, so the same address, but that
  // instance's install id and viewer port are the sibling's, not this
  // channel's.
  final own = channelLabel(via) == channel.name;
  final installId = own ? via.installId : null;
  final candidates = [
    for (final p in paired)
      if (!used.contains(p.id)) p,
  ];

  PairedHost? hit;
  if (installId != null) {
    for (final p in candidates) {
      if (p.installId == installId) {
        hit = p;
        break;
      }
    }
  }
  if (hit == null) {
    final hostname = via.hostname.toLowerCase();
    for (final p in candidates) {
      // Two known, different install ids are two installs, whatever the
      // names say.
      if (installId != null && p.installId != null) continue;
      if (p.channel != null &&
          p.channel == channel.name &&
          hostname.isNotEmpty &&
          p.hostname.toLowerCase() == hostname) {
        hit = p;
        break;
      }
    }
  }
  if (hit == null) return null;
  return PairingMatch(
    paired: hit,
    host: via.address.isNotEmpty ? via.address : hit.host,
    port: own ? (via.viewerPort ?? hit.port) : hit.port,
  );
}

/// [hosts] with each channel's pairing filled in.
///
/// A channel read from a pairing ([ChannelNode.pairedId], a paired computer
/// discovery has not found) carries that pairing, at its stored address;
/// every other channel is matched by [matchPairing].
List<HostNode> applyPairings(List<HostNode> hosts, List<PairedHost> paired) {
  if (paired.isEmpty) return hosts;
  final byId = {for (final p in paired) p.id: p};
  final used = <String>{
    for (final h in hosts)
      for (final c in h.channels)
        if (c.pairedId != null && byId.containsKey(c.pairedId)) c.pairedId!,
  };
  ChannelNode pair(ChannelNode c) {
    final own = byId[c.pairedId];
    if (own != null) {
      return c.withPairing(
        PairingMatch(paired: own, host: own.host, port: own.port),
      );
    }
    // Read from a pairing since removed: it is no other pairing's.
    if (c.pairedId != null) return c;
    final m = matchPairing(c, paired, used: used);
    if (m == null) return c;
    used.add(m.paired.id);
    return c.withPairing(m);
  }

  return [
    for (final h in hosts) h.withChannels(h.channels.map(pair).toList()),
  ];
}
