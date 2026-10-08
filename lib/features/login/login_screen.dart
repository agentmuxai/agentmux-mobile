import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../shared/theme/app_theme.dart';

const muxbusSignInReason =
    'Sign in to see your computers and agents from anywhere, '
    'not just on this network.';
const signInUnavailableText =
    "Signing in to MuxBus isn't available in this version of the app yet. "
    'Computers on this network still work without it.';
const signInNetworkErrorText = "Couldn't reach MuxBus. Check your connection.";
const signInRefusedText = "That account can't sign in to MuxBus.";
const signInStateMismatchText =
    "This sign-in couldn't be checked, so it was stopped. Try again.";
const signInFailedText = 'Sign-in failed. Try again.';

/// What the sign-in page says about [error]; null when it says nothing
/// (the person cancelled).
String? signInErrorText(Object error) {
  if (error is AuthCancelled) return null;
  if (error is AuthUnavailable) return signInUnavailableText;
  if (error is AuthNetworkError) return signInNetworkErrorText;
  if (error is AuthStateMismatch) return signInStateMismatchText;
  if (error is AuthCallbackError) {
    final detail = readableAuthErrorDescription(error.description);
    if (error.accountRefused) {
      return detail == null ? signInRefusedText : '$signInRefusedText\n$detail';
    }
    return detail ?? signInFailedText;
  }
  return signInFailedText;
}

/// The MuxBus sign-in page: "Connect with Google" first, then email, and
/// "Not now". Reached from the discovery screen's "MuxBus Sign in" button and
/// from Settings.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  String? _error;
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    _checkAvailable();
  }

  Future<void> _checkAvailable() async {
    bool? available;
    try {
      available = await ref.read(authRepositoryProvider).signInAvailable();
    } catch (_) {
      available = null;
    }
    // Unknown (offline) leaves the buttons on; a tap then says why.
    if (mounted && available == false) setState(() => _unavailable = true);
  }

  Future<void> _signIn(SignInMethod method) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).signIn(method: method);
      // Signed in: the app's router takes it from here.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = signInErrorText(e);
        if (e is AuthUnavailable) _unavailable = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/discover');
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_busy && !_unavailable;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: _close,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.cloud_outlined,
                    size: 48,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'MuxBus',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    muxbusSignInReason,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_unavailable)
                    const _Message(
                      text: signInUnavailableText,
                      color: AppColors.textSecondary,
                    )
                  else if (_error != null)
                    _Message(text: _error!, color: AppColors.error),
                  if (_busy) ...[
                    const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Finish signing in in the browser…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    key: const ValueKey('connect-google'),
                    onPressed:
                        enabled ? () => _signIn(SignInMethod.google) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1F1F1F),
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const _GoogleMark(),
                    label: const Text('Connect with Google'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('use-email'),
                    onPressed:
                        enabled ? () => _signIn(SignInMethod.email) : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(fontSize: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('Use email'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(onPressed: _close, child: const Text('Not now')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 14),
    ),
  );
}

/// A plain "G" in Google's blue on white, drawn with text, so no image asset
/// or package is needed.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Text(
      'G',
      style: TextStyle(
        color: Color(0xFF4285F4),
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
