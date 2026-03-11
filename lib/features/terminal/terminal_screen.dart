import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/connection_provider.dart';

/// Terminal view using xterm.dart — connects to a backend PTY session.
class TerminalScreen extends ConsumerStatefulWidget {
  final String blockId;

  const TerminalScreen({super.key, required this.blockId});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  // TODO: Replace with xterm.dart Terminal + TerminalView once Flutter SDK available.
  // For now, this is a placeholder that demonstrates the RPC data flow.

  final _outputBuffer = StringBuffer();
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _connectToSession();
  }

  Future<void> _connectToSession() async {
    final client = ref.read(rpcClientProvider);

    // Resync to get existing PTY output.
    await client.controllerResync(widget.blockId);

    // Subscribe to terminal output events.
    client.subscribe('blockfile', scopes: ['block:${widget.blockId}']).listen(
      (event) {
        final data = event['data'];
        if (data != null) {
          setState(() {
            _outputBuffer.write(data);
          });
          _scrollToBottom();
        }
      },
    );
  }

  void _sendInput(String text) {
    final client = ref.read(rpcClientProvider);
    client.sendTerminalInput(
      widget.blockId,
      Uint8List.fromList(utf8.encode(text)),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _outputBuffer.toString()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Terminal output area
          // TODO: Replace with xterm.dart TerminalView widget.
          Expanded(
            child: GestureDetector(
              onTap: () => _inputFocus.requestFocus(),
              child: Container(
                color: Colors.black,
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(
                    _outputBuffer.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: Color(0xFFE0E0E0),
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Special keys toolbar
          _SpecialKeysToolbar(onKey: _sendInput),

          // Text input (bridges to PTY stdin)
          Container(
            color: const Color(0xFF232325),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocus,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Type command...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onSubmitted: (text) {
                      _sendInput('$text\n');
                      _inputController.clear();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, size: 20),
                  onPressed: () {
                    _sendInput('${_inputController.text}\n');
                    _inputController.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Toolbar with special terminal keys (Ctrl, Alt, Tab, Esc, arrows).
class _SpecialKeysToolbar extends StatelessWidget {
  final void Function(String) onKey;

  const _SpecialKeysToolbar({required this.onKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2A2A2D),
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          _KeyButton('Esc', () => onKey('\x1b')),
          _KeyButton('Tab', () => onKey('\t')),
          _KeyButton('Ctrl+C', () => onKey('\x03')),
          _KeyButton('Ctrl+D', () => onKey('\x04')),
          _KeyButton('Ctrl+Z', () => onKey('\x1a')),
          _KeyButton('Ctrl+L', () => onKey('\x0c')),
          _KeyButton(String.fromCharCode(0x2191), () => onKey('\x1b[A')), // Up
          _KeyButton(String.fromCharCode(0x2193), () => onKey('\x1b[B')), // Down
          _KeyButton(String.fromCharCode(0x2190), () => onKey('\x1b[D')), // Left
          _KeyButton(String.fromCharCode(0x2192), () => onKey('\x1b[C')), // Right
          _KeyButton('|', () => onKey('|')),
          _KeyButton('~', () => onKey('~')),
        ],
      ),
    );
  }
}

class _KeyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _KeyButton(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Material(
        color: const Color(0xFF3A3A3D),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: Color(0xFFCCCCCC),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
