import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/discovery/models/lan_instance.dart';
import '../theme/app_theme.dart';
import 'tag_chip.dart';

/// A cloud state older than this says how old it is
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` section 3.3).
const cloudStateStaleAfter = Duration(seconds: 60);

/// What an agent is doing, as a chip at the right of its row
/// (`SPEC_AGENT_STATUS_AND_LIVE_PANE_FEED_2026_10_07.md` sections 3.1 and
/// 6.3): `working 3m` in green with a pulsing dot, `needs you` in amber,
/// `idle` in grey, `stopped` as a grey outline, `error` in red. The word
/// carries the meaning; the colour only reinforces it. An agent with no state
/// gets no chip at all ([forAgent] returns null), never a guess.
///
/// [since] (LAN) gives a working agent's duration, counted on this device's
/// clock from the desktop's own figure. [asOf] (cloud) is when the relay
/// received the record; past [cloudStateStaleAfter] the chip says
/// `as of 2m ago` and is muted. [live] false (the channel has gone quiet)
/// mutes the chip and drops the duration, which would otherwise keep counting
/// with nothing behind it.
class AgentStateChip extends StatefulWidget {
  const AgentStateChip({
    super.key,
    required this.state,
    this.since,
    this.asOf,
    this.live = true,
  });

  final AgentState state;
  final StateSince? since;
  final DateTime? asOf;
  final bool live;

  /// The chip for [agent], or null when it has no state.
  static AgentStateChip? forAgent(
    LanAgent agent, {
    bool live = true,
    Key? key,
  }) {
    final state = agent.state;
    if (state == null) return null;
    return AgentStateChip(
      key: key,
      state: state,
      since: agent.stateSince,
      asOf: agent.stateAsOf,
      live: live,
    );
  }

  @override
  State<AgentStateChip> createState() => _AgentStateChipState();
}

class _AgentStateChipState extends State<AgentStateChip> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = clock.now();
    final view = AgentStateView.of(
      widget.state,
      since: widget.since,
      asOf: widget.asOf,
      live: widget.live,
      now: now,
    );
    // Rebuild when the label next changes, not on every frame.
    _timer?.cancel();
    final next = view.nextChange;
    _timer =
        next == null
            ? null
            : Timer(next, () {
              if (mounted) setState(() {});
            });

    final color = agentStateColor(widget.state);
    final animate =
        !view.muted &&
        widget.state == AgentState.working &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final chip = TagChip(
      label: view.label,
      color: color,
      filled: widget.state != AgentState.stopped,
      tooltip: view.tooltip,
      leading:
          widget.state == AgentState.working
              ? _Dot(color: color, animate: animate)
              : null,
    );
    return view.muted ? Opacity(opacity: 0.55, child: chip) : chip;
  }
}

/// What the chip says, worked out from the state and the time; pure, so the
/// wording is tested without a widget.
class AgentStateView {
  const AgentStateView({
    required this.label,
    required this.tooltip,
    required this.muted,
    this.nextChange,
  });

  final String label;
  final String tooltip;

  /// The state is not current: the channel went quiet, or the cloud record is
  /// older than [cloudStateStaleAfter].
  final bool muted;

  /// How long until [label] changes, if it ever does on its own.
  final Duration? nextChange;

  factory AgentStateView.of(
    AgentState state, {
    StateSince? since,
    DateTime? asOf,
    bool live = true,
    required DateTime now,
  }) {
    final age = asOf == null ? null : _nonNegative(now.difference(asOf));
    final stale = age != null && age >= cloudStateStaleAfter;
    final changes = <Duration>[];

    var label = switch (state) {
      AgentState.working => 'working',
      AgentState.waiting => 'needs you',
      AgentState.idle => 'idle',
      AgentState.stopped => 'stopped',
      AgentState.error => 'error',
    };
    var tooltip = switch (state) {
      AgentState.working => 'Working on a turn',
      AgentState.waiting => 'A question is waiting for you on the desktop',
      AgentState.idle => 'Running, not working on anything',
      AgentState.stopped => 'Not running: it exited',
      AgentState.error => 'Not running: it exited with an error',
    };

    if (state == AgentState.working && since != null && live && !stale) {
      final elapsed = since.elapsed(now);
      label = '$label ${formatStateDuration(elapsed)}';
      tooltip = '$tooltip for ${formatStateDuration(elapsed)}';
      changes.add(_untilNextStep(elapsed));
    }
    if (age != null) {
      if (stale) {
        final ago = '${formatStateDuration(age)} ago';
        label = '$label, as of $ago';
        tooltip = '$tooltip (last reported $ago)';
        changes.add(_untilNextStep(age));
      } else {
        changes.add(cloudStateStaleAfter - age);
      }
    }
    return AgentStateView(
      label: label,
      tooltip: tooltip,
      muted: !live || stale,
      nextChange: changes.isEmpty ? null : changes.reduce(_shorter),
    );
  }

  static Duration _nonNegative(Duration d) => d.isNegative ? Duration.zero : d;

  static Duration _shorter(Duration a, Duration b) => a < b ? a : b;

  /// Time until [formatStateDuration] of a duration growing from [d] changes.
  static Duration _untilNextStep(Duration d) {
    final Duration step;
    if (d < const Duration(hours: 1)) {
      step = const Duration(minutes: 1);
    } else if (d < const Duration(days: 1)) {
      step = const Duration(hours: 1);
    } else {
      step = const Duration(days: 1);
    }
    final into = d.inMicroseconds % step.inMicroseconds;
    return Duration(microseconds: step.inMicroseconds - into);
  }
}

/// `<1m`, `3m`, `2h`, `4d`: short enough for a chip on a narrow screen.
String formatStateDuration(Duration d) {
  if (d < const Duration(minutes: 1)) return '<1m';
  if (d < const Duration(hours: 1)) return '${d.inMinutes}m';
  if (d < const Duration(days: 1)) return '${d.inHours}h';
  return '${d.inDays}d';
}

Color agentStateColor(AgentState state) => switch (state) {
  AgentState.working => AppColors.success,
  AgentState.waiting => AppColors.warning,
  AgentState.idle || AgentState.stopped => AppColors.textSecondary,
  AgentState.error => AppColors.error,
};

/// The working chip's dot: it pulses while the agent works, unless the
/// platform asks for no animations or the state is not current.
class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.animate});
  final Color color;
  final bool animate;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.3,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Dot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _sync();
  }

  void _sync() {
    if (widget.animate) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}
