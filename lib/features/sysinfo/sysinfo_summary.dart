import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/viewer/paired_hosts_repository.dart';
import '../../core/viewer/pairing_service.dart';
import '../../core/viewer/sysinfo_events.dart';
import '../../core/viewer/viewer_client.dart';
import '../discovery/channel_terminals.dart' show PanesKey;

/// What the channel list says on a paired computer's Sysinfo row.
sealed class SysinfoSummary {
  const SysinfoSummary();
}

class SysinfoNow extends SysinfoSummary {
  const SysinfoNow(this.sample);

  /// Null before the computer's first sample.
  final SysinfoSample? sample;
}

/// The computer's AgentMux has no Sysinfo route (404).
class SysinfoTooOld extends SysinfoSummary {
  const SysinfoTooOld();
}

class SysinfoUnreachable extends SysinfoSummary {
  const SysinfoUnreachable();
}

/// A paired computer's latest CPU and memory, for its Sysinfo row
/// (`PLAN_CHANNEL_AS_ONE_LIST_2026_10_13.md` step 3b). Read when the row
/// shows, and again on refresh.
final channelSysinfoProvider =
    FutureProvider.autoDispose.family<SysinfoSummary, PanesKey>((ref, key) async {
  final hosts = ref.read(pairedHostsProvider);
  final paired = hosts.where((h) => h.id == key.pairId).firstOrNull;
  if (paired == null || paired.invalid) return const SysinfoUnreachable();
  final client = ref.read(viewerClientFactoryProvider)(
    host: key.host,
    port: key.port,
    fingerprint: paired.fingerprint,
    token: paired.token,
  );
  try {
    return SysinfoNow(await client.sysinfo());
  } on ViewerNotFound {
    return const SysinfoTooOld();
  } catch (_) {
    // A refused pairing is the terminals' fetch's to report: one place.
    return const SysinfoUnreachable();
  } finally {
    client.close();
  }
});

/// "CPU 23% · RAM 61%".
String sysinfoSummaryText(SysinfoSummary? s) => switch (s) {
      null => '',
      SysinfoNow(:final sample) when sample == null => 'No sample yet',
      SysinfoNow(:final sample) => [
          if (sample!.cpu != null) 'CPU ${sample.cpu!.round()}%',
          if (sample.memPercent != null) 'RAM ${sample.memPercent!.round()}%',
        ].join(' · '),
      SysinfoTooOld() => 'Needs a newer AgentMux',
      SysinfoUnreachable() => "Can't reach it",
    };
