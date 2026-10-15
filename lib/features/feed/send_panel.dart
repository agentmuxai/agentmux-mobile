import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/viewer/viewer_client.dart';
import 'feed_theme.dart';
import 'send_controller.dart';

/// What people have typed and not sent, per agent, while the app runs
/// (`SPEC_SEND_FROM_THE_PHONE_2026_10_13.md` 5.5); gone when it closes. The key
/// is `<pairing id>/<agent>`.
final feedDraftsProvider = Provider<Map<String, String>>((_) => {});

/// The words that say why a computer takes no messages from this device,
/// for the menu's "Send a message…"; null when it does (or has not said yet).
String? sendGrantText(SendGrant? grant) => switch (grant) {
      SendGrant.off => 'Sending is off for this device: turn it on in AgentMux › Paired devices on the computer.',
      SendGrant.pairAgain => 'This computer has no key for this device. Pair again to send messages.',
      SendGrant.tooOld => 'Update AgentMux on the computer to send messages from here.',
      SendGrant.allowed || null => null,
    };

/// Under the feed: what was sent and is not in it yet, and the box to type a
/// message in when this device may send. Enter sends; a hardware keyboard's
/// Shift+Enter, or pasted text, makes a new line.
class SendPanel extends ConsumerStatefulWidget {
  const SendPanel({
    super.key,
    required this.controller,
    required this.draftKey,
    required this.canSend,
    required this.agentWorking,
    this.onSent,
  });

  final SendController controller;
  final String draftKey;

  /// False while the feed is not connected: the text stays, Send waits.
  final bool canSend;

  /// The agent is in a turn: say it will read the message at its next step.
  final bool agentWorking;

  /// A message went out: the feed should show the latest.
  final VoidCallback? onSent;

  @override
  ConsumerState<SendPanel> createState() => _SendPanelState();
}

class _SendPanelState extends ConsumerState<SendPanel> {
  late final TextEditingController _text;
  final _focus = FocusNode();

  Map<String, String> get _drafts => ref.read(feedDraftsProvider);

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: _drafts[widget.draftKey] ?? '');
    _text.addListener(_remember);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _remember() {
    if (_text.text.isEmpty) {
      _drafts.remove(widget.draftKey);
    } else {
      _drafts[widget.draftKey] = _text.text;
    }
  }

  bool get _ready => widget.canSend && _text.text.trim().isNotEmpty;

  void _send() {
    if (!_ready) return;
    // What the field held at Enter, to tell a composer that lost keystrokes
    // (the platform field and the controller out of step) from a send bug.
    final value = _text.value;
    AppLogger.log(
      'composer at Enter: ${value.text.length} chars, '
      'composing ${value.composing.isValid ? '${value.composing.start}-${value.composing.end}' : 'none'}',
      name: 'Send',
    );
    if (widget.controller.send(_text.text)) {
      _text.clear();
      widget.onSent?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, _text]),
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in controller.messages)
              _SentRow(
                message: m,
                onRetry: () => controller.retry(m.id),
                onDiscard: () => controller.discard(m.id),
              ),
            if (controller.grant == SendGrant.allowed) _composer(context),
          ],
        );
      },
    );
  }

  Widget _composer(BuildContext context) {
    final tooLong = _tooLong(_text.text);
    return Container(
      decoration: const BoxDecoration(
        color: FeedColors.blockSolid,
        border: Border(top: BorderSide(color: FeedColors.secondary, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(FeedSpace.s3, 6, 4, 6),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.agentWorking)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'The agent is working: it reads this at its next step.',
                  style: TextStyle(fontSize: 12, color: FeedColors.secondary),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    // A hardware keyboard's Enter sends; Shift+Enter is a new line.
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter &&
                          !HardwareKeyboard.instance.isShiftPressed) {
                        _send();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      // The keyboard's Enter is Send, as the spec says.
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) {
                        _send();
                        _focus.requestFocus();
                      },
                      decoration: InputDecoration(
                        hintText: widget.canSend ? 'Message the agent' : 'Reconnecting…',
                        errorText: tooLong ? 'Over $maxMessageBytes bytes' : null,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Send',
                  icon: const Icon(Icons.send),
                  onPressed: _ready && !tooLong ? _send : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static bool _tooLong(String text) => text.length > maxMessageBytes ~/ 4 && _bytes(text) > maxMessageBytes;

  static int _bytes(String text) => text.trimRight().runes.fold<int>(
        0,
        (n, r) => n + (r < 0x80 ? 1 : r < 0x800 ? 2 : r < 0x10000 ? 3 : 4),
      );
}

/// One message not in the feed yet: muted while it goes, with what went wrong
/// and the way to try again when it did not.
class _SentRow extends StatelessWidget {
  const _SentRow({required this.message, required this.onRetry, required this.onDiscard});
  final SentMessage message;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final failed = message.state == SentState.failed;
    return Container(
      color: FeedColors.blockSolid,
      padding: const EdgeInsets.symmetric(horizontal: FeedSpace.s3, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: FeedColors.secondary),
                ),
                Text(
                  failed ? sendFailureText(message) : 'Sending…',
                  style: TextStyle(
                    fontSize: 12,
                    color: failed ? Theme.of(context).colorScheme.error : FeedColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          if (failed) ...[
            TextButton(onPressed: onRetry, child: const Text('Try again')),
            IconButton(
              tooltip: 'Discard',
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDiscard,
            ),
          ],
        ],
      ),
    );
  }
}
