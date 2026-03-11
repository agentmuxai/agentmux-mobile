import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/connection_provider.dart';

/// AI Agent chat view — streaming responses, tool approval, history.
class AgentScreen extends ConsumerStatefulWidget {
  final String blockId;

  const AgentScreen({super.key, required this.blockId});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  final _messages = <_ChatMessage>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _subscribeToEvents();
  }

  Future<void> _loadChatHistory() async {
    final client = ref.read(rpcClientProvider);
    try {
      final history = await client.getAiChat(widget.blockId);
      setState(() {
        _messages.addAll(history.map((m) {
          final map = m as Map<String, dynamic>;
          return _ChatMessage(
            role: map['role'] as String? ?? 'assistant',
            content: map['content'] as String? ?? '',
          );
        }));
      });
      _scrollToBottom();
    } catch (_) {
      // No history or block not found — start fresh.
    }
  }

  void _subscribeToEvents() {
    final client = ref.read(rpcClientProvider);
    client
        .subscribe('blockfile', scopes: ['block:${widget.blockId}'])
        .listen((event) {
      // Handle streaming AI response tokens.
      final data = event['data'];
      if (data != null) {
        setState(() {
          if (_messages.isEmpty || _messages.last.role != 'assistant') {
            _messages.add(_ChatMessage(role: 'assistant', content: ''));
          }
          _messages.last = _ChatMessage(
            role: 'assistant',
            content: _messages.last.content + (data as String),
          );
        });
        _scrollToBottom();
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_ChatMessage(role: 'user', content: text));
      _isStreaming = true;
    });
    _inputController.clear();
    _scrollToBottom();

    final client = ref.read(rpcClientProvider);
    try {
      await client.sendAiMessage({
        'blockid': widget.blockId,
        'message': text,
      });
    } catch (e) {
      setState(() {
        _messages
            .add(_ChatMessage(role: 'error', content: 'Failed to send: $e'));
        _isStreaming = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent'),
        actions: [
          if (_isStreaming)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _EmptyAgentState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _MessageBubble(message: _messages[index]),
                  ),
          ),
          _InputBar(
            controller: _inputController,
            onSend: _sendMessage,
            isStreaming: _isStreaming,
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  final String role;
  String content;

  _ChatMessage({required this.role, required this.content});
}

class _EmptyAgentState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome,
              size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text('Start a conversation',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Ask the AI agent anything',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isError = message.role == 'error';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isError
              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.15)
              : isUser
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                  : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          message.content,
          style: TextStyle(
            color: isError
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.onSurface,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isStreaming;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.isStreaming,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 4,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Message...',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => onSend(),
              textInputAction: TextInputAction.send,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: isStreaming ? null : onSend,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
