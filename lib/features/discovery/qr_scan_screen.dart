import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/discovery/discovery_provider.dart';
import '../../shared/theme/app_theme.dart';

/// Scans a QR code encoding `agentmux://connect?host=<ip>&port=<port>&token=<key>`
/// and connects to the LAN instance it describes.
///
/// This is the QR-code fallback for [ManualAddSheet] pairing: same
/// `addManual` call, same loading/error handling pattern, just fed by a
/// camera scan instead of typed text fields.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  // True while we're validating/connecting to a scanned code — guards
  // against onDetect firing again for the same or a subsequent frame.
  bool _connecting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_connecting) return;

    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;

    final parsed = _parseConnectUri(raw);
    if (parsed == null) {
      setState(() {
        _error = 'That QR code isn\'t a valid AgentMux pairing code.';
      });
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });
    await _controller.stop();

    try {
      await ref
          .read(discoveryProvider.notifier)
          .addManual(parsed.host, parsed.port, parsed.token);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Could not connect — check the code and try again.';
        });
        await _controller.start();
      }
    }
  }

  /// Parses `agentmux://connect?host=<ip>&port=<port>&token=<key>`.
  /// Returns null if host, port, or token is missing/invalid.
  ({String host, int port, String token})? _parseConnectUri(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    final host = uri.queryParameters['host'];
    final portRaw = uri.queryParameters['port'];
    final token = uri.queryParameters['token'];
    if (host == null || host.isEmpty) return null;
    if (token == null || token.isEmpty) return null;
    if (portRaw == null || portRaw.isEmpty) return null;

    final port = int.tryParse(portRaw);
    if (port == null || port < 1 || port > 65535) return null;

    return (host: host, port: port, token: token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR code'),
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return switch (state.torchState) {
                  TorchState.on => const Icon(Icons.flash_on),
                  TorchState.off => const Icon(Icons.flash_off),
                  TorchState.auto => const Icon(Icons.flash_auto),
                  TorchState.unavailable => const Icon(Icons.flash_off),
                };
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) =>
                _CameraErrorView(error: error),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Point your camera at the QR code shown in\nAgentMux → Settings on your desktop.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 13),
                    ),
                  ],
                  if (_connecting) ...[
                    const SizedBox(height: 16),
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off, size: 48, color: Colors.white38),
          const SizedBox(height: 16),
          Text(
            'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

void showQrScanScreen(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const QrScanScreen()),
  );
}
