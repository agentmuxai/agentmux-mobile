import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/discovery/models/lan_instance.dart';
import '../../shared/widgets/ascii_spinner.dart';
import 'feed_theme.dart';
import 'messages.dart';
import 'tool_meta.dart';
import 'transcript.dart';

/// The row at the bottom of the feed, as the desktop's working row
/// (`components/AgentFooter.tsx`, `status/present-status.ts`;
/// `SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §8): while a turn
/// runs, a spinner, what the agent is doing, and "↓ 2.4k tokens · 1m 5s";
/// after it, "✓ Worked · 42s · 2.4k tokens". Nothing when neither applies.
class WorkingRow extends StatefulWidget {
  const WorkingRow({
    super.key,
    required this.turn,
    this.runningTool,
    this.compacting = false,
    this.state,
    this.since,
  });

  final TurnInfo turn;

  /// The call running now, if any.
  final ToolCallItem? runningTool;
  final bool compacting;

  /// The agent's state from the feed's `status` events; null until one.
  final AgentState? state;

  /// How long it has been in [state].
  final StateSince? since;

  @override
  State<WorkingRow> createState() => _WorkingRowState();
}

/// Whether the row shows a running turn: the transcript says one is open,
/// and the agent's own state, when known, doesn't say it stopped.
bool workingRowLive(TurnInfo turn, AgentState? state) =>
    turn.open && (state == null || state == AgentState.working || state == AgentState.waiting);

class _WorkingRowState extends State<WorkingRow> {
  Timer? _timer;
  int _frame = 0;

  bool get _live => workingRowLive(widget.turn, widget.state);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WorkingRow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Ticks only while a turn runs: the spinner and the elapsed time.
  void _sync() {
    if (_live && _timer == null) {
      _timer = Timer.periodic(spinnerFrameTime, (_) {
        if (mounted) setState(() => _frame++);
      });
    } else if (!_live) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = feedProse.copyWith(fontSize: 12.5, color: FeedColors.secondary);
    if (_live) {
      final now = clock.now();
      final elapsed = widget.since?.elapsed(now) ??
          (widget.turn.startedAt == null ? null : now.difference(widget.turn.startedAt!));
      final tokens = widget.turn.outputTokens;
      final right = [
        if (tokens > 0) '${tokenArrow(widget.turn, widget.runningTool)} ${formatTokens(tokens)} tokens',
        if (elapsed != null && !elapsed.isNegative) formatElapsed(elapsed),
      ].join(' · ');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: FeedSpace.s1),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Text(
                spinnerFrames[_frame % spinnerFrames.length],
                style: style.copyWith(color: FeedColors.accent),
              ),
            ),
            Expanded(
              child: Text(
                workingText(
                  widget.turn,
                  runningTool: widget.runningTool,
                  compacting: widget.compacting,
                  waiting: widget.state == AgentState.waiting,
                  now: now,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style.copyWith(color: FeedColors.text),
              ),
            ),
            if (right.isNotEmpty) Text(right, style: style),
          ],
        ),
      );
    }
    final last = widget.turn.last;
    if (widget.turn.open || last == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FeedSpace.s1),
      child: Text(
        [
          '✓ Worked',
          if (last.durationMs != null) formatElapsed(Duration(milliseconds: last.durationMs!)),
          if (last.outputTokens != null) '${formatTokens(last.outputTokens!)} tokens',
        ].join(' · '),
        style: style,
      ),
    );
  }
}

/// "↑" while a request is in flight; "↓" while the model streams or a tool
/// runs, as the desktop marks them.
String tokenArrow(TurnInfo turn, ToolCallItem? runningTool) =>
    turn.phase == TurnPhase.requesting && runningTool == null ? '↑' : '↓';

/// What the agent is doing, in the desktop's words, most urgent first.
String workingText(
  TurnInfo turn, {
  ToolCallItem? runningTool,
  bool compacting = false,
  bool waiting = false,
  required DateTime now,
}) {
  final tool = runningTool;
  if (waiting || tool?.name == 'AskUserQuestion') return 'Waiting for your answer on the computer';
  if (compacting) return 'Compacting…';
  if (turn.rateLimited) {
    final at = turn.retryAt;
    final left = at?.difference(now);
    return left != null && !left.isNegative
        ? 'Rate limited — retrying in ${formatElapsed(left)}'
        : 'Rate limited — retrying…';
  }
  if (tool != null) {
    final detail = toolDetail(tool);
    final label = toolLabel(tool, detail) ?? '';
    // A subagent's running step says more than its Agent call does.
    final step = Transcript.runningStep(tool);
    final stepText = step == null
        ? ''
        : [toolLabel(step, toolDetail(step)) ?? '', toolDetail(step)].where((s) => s.isNotEmpty).join(' · ');
    final head = [label, detail, stepText].where((s) => s.isNotEmpty).join(' · ');
    final started = tool.receivedAt;
    final age = started == null ? null : now.difference(started);
    return age != null && age >= const Duration(seconds: 10) ? '$head · ${formatElapsed(age)}' : head;
  }
  return switch (turn.phase) {
    TurnPhase.thinking => 'Thinking',
    TurnPhase.writing => 'Writing the reply',
    TurnPhase.composing => 'Preparing the next step',
    TurnPhase.requesting => 'Working…',
  };
}

/// `42s`, `1m 5s`, `1h 2m`.
String formatElapsed(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
  return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
}
