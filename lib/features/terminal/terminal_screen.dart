import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/viewer/paired_host.dart';
import '../../core/viewer/paired_hosts_repository.dart';
import '../../core/viewer/pairing_service.dart';
import '../../core/viewer/viewer_client.dart';
import '../../shared/theme/app_theme.dart';
import 'terminal_feed_controller.dart';

/// One terminal of a paired computer, live and read-only
/// (`docs/reports/REPORT_PANE_LIST_TERMINALS_AND_FROZEN_FEED_2026_10_12.md`
/// §2.5, phase B). It renders at the size the desktop gave the PTY and
/// scrolls sideways when that is wider than the screen; nothing typed here
/// reaches the terminal, and it is never resized from here. The stream stops
/// in the background and resumes where it left off.
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({
    super.key,
    required this.pairing,
    required this.blockId,
    required this.label,
  });

  final PairingMatch pairing;
  final String blockId;
  final String label;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  ViewerClient? _client;
  TerminalFeedController? _controller;
  AppLifecycleListener? _lifecycle;

  static const _style = TerminalStyle(fontSize: 12);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: () => _controller?.pause(),
      onResume: () => _controller?.resume(),
    );
    _connect();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _controller
      ?..removeListener(_onChange)
      ..dispose();
    _client?.close();
    super.dispose();
  }

  void _connect() {
    final paired = widget.pairing.paired;
    if (paired.invalid) return;
    final client = ref.read(viewerClientFactoryProvider)(
      host: widget.pairing.host,
      port: widget.pairing.port,
      fingerprint: paired.fingerprint,
      token: paired.token,
    );
    final controller = TerminalFeedController(
      source: ({lastEventId}) =>
          client.terminalFeed(widget.blockId, lastEventId: lastEventId),
      onUnauthorized: () => unawaited(
        ref.read(pairedHostsProvider.notifier).markInvalid(paired.id),
      ),
    )..addListener(_onChange);
    _client = client;
    _controller = controller;
    controller.start();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final connection = widget.pairing.paired.invalid
        ? TerminalConnection.unauthorized
        : (controller?.connection ?? TerminalConnection.connecting);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label, overflow: TextOverflow.ellipsis),
            Text(
              widget.pairing.paired.hostname,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
        actions: [_ConnectionLabel(connection: connection)],
      ),
      body: _body(connection, controller),
    );
  }

  Widget _body(TerminalConnection connection, TerminalFeedController? controller) {
    final (String, String)? ended = switch (connection) {
      TerminalConnection.unauthorized => (
          'This device was unpaired on the computer',
          'Pair again to watch its terminals.',
        ),
      TerminalConnection.notFound => (
          'This terminal can\'t be watched',
          'It was closed on the computer, or it belongs to an agent hidden '
              'from paired devices.',
        ),
      TerminalConnection.notShared => (
          'This computer doesn\'t share its terminals',
          'On the computer, turn on Settings › Devices › Share terminals with '
              'paired devices.',
        ),
      _ => null,
    };
    if (ended != null) return _Message(title: ended.$1, detail: ended.$2);
    final terminal = controller?.terminal;
    if (terminal == null) {
      return _Message(
        title: connection == TerminalConnection.reconnecting
            ? 'Can\'t reach the computer. Retrying…'
            : 'Connecting…',
      );
    }
    final cols = controller?.size?.$2 ?? terminal.viewWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = EdgeInsets.all(8);
        final cell = terminalCellSize(_style, MediaQuery.textScalerOf(context));
        final width = max(constraints.maxWidth, cols * cell.width + padding.horizontal + 2);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: TerminalView(
              terminal,
              // A new snapshot is a new terminal.
              key: ObjectKey(terminal),
              textStyle: _style,
              padding: padding,
              readOnly: true,
              hardwareKeyboardOnly: true,
              autoResize: false,
            ),
          ),
        );
      },
    );
  }
}

/// The size of one character cell in [style], measured as xterm's painter
/// measures it.
Size terminalCellSize(TerminalStyle style, TextScaler scaler) {
  const sample = 'mmmmmmmmmm';
  final painter = TextPainter(
    text: TextSpan(text: sample, style: style.toTextStyle()),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  final size = Size(painter.width / sample.length, painter.height);
  painter.dispose();
  return size;
}

class _ConnectionLabel extends StatelessWidget {
  const _ConnectionLabel({required this.connection});
  final TerminalConnection connection;

  @override
  Widget build(BuildContext context) {
    final (String, Color)? shown = switch (connection) {
      TerminalConnection.live => ('Live', AppColors.success),
      TerminalConnection.connecting => ('Connecting…', AppColors.warning),
      TerminalConnection.reconnecting => ('Reconnecting…', AppColors.warning),
      TerminalConnection.paused => ('Paused', AppColors.textSecondary),
      _ => null,
    };
    if (shown == null) return const SizedBox.shrink();
    final (label, color) = shown;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, this.detail});
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
