import 'package:flutter/material.dart';

import '../../core/discovery/local_api_client.dart';
import '../../core/discovery/models/lan_instance.dart';

class LanAgentScreen extends StatefulWidget {
  const LanAgentScreen({
    super.key,
    required this.instance,
    required this.agent,
  });

  final LanInstance instance;
  final LanAgent agent;

  @override
  State<LanAgentScreen> createState() => _LanAgentScreenState();
}

class _LanAgentScreenState extends State<LanAgentScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _sending = false;
  String? _lastResult;

  late final LocalApiClient _client = LocalApiClient(widget.instance);

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;
    setState(() { _sending = true; _lastResult = null; });
    try {
      await _client.inject(
        targetAgent: widget.agent.name,
        message: message,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() { _lastResult = 'sent'; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _lastResult = 'Send failed — check connection and try again.'; });
    } finally {
      if (mounted) setState(() { _sending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _isRecent(widget.agent.lastSeen);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: isActive ? Colors.greenAccent : Colors.white24,
                ),
                const SizedBox(width: 8),
                Text(widget.agent.name),
              ],
            ),
            Text(
              widget.instance.hostname,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_lastResult != null) _ResultBanner(result: _lastResult!),
          const Spacer(),
          _ComposeBar(
            controller: _controller,
            focusNode: _focusNode,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  bool _isRecent(int? lastSeenMs) {
    if (lastSeenMs == null) return false;
    final dt = DateTime.fromMillisecondsSinceEpoch(lastSeenMs);
    return DateTime.now().difference(dt).inMinutes < 5;
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});
  final String result;

  @override
  Widget build(BuildContext context) {
    final ok = result == 'sent';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: ok ? Colors.green.withAlpha(40) : Colors.red.withAlpha(40),
      child: Text(
        ok ? 'Message injected ✓' : result,
        style: TextStyle(
          color: ok ? Colors.greenAccent : Colors.redAccent,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _ComposeBar extends StatelessWidget {
  const _ComposeBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(20)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Message to agent…',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          sending
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.send),
                  color: Colors.greenAccent,
                  onPressed: onSend,
                ),
        ],
      ),
    );
  }
}
