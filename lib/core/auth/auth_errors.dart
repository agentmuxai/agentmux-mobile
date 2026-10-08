/// Why signing in to MuxBus did not finish. The sign-in page turns each kind
/// into plain words; none of them carries a token, a code or a URL.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => 'AuthException: $message';
}

/// The person closed the browser or pressed cancel. Not an error to show.
class AuthCancelled extends AuthException {
  AuthCancelled() : super('Sign-in cancelled');
}

/// This build has no sign-in settings: neither `--dart-define` nor the cloud
/// discovery document names a client for the app.
class AuthUnavailable extends AuthException {
  AuthUnavailable() : super('Sign-in is not available for this build');
}

/// MuxBus (the relay or the sign-in service) could not be reached.
class AuthNetworkError extends AuthException {
  AuthNetworkError() : super('Could not reach MuxBus');
}

/// The callback's `state` is not the one this sign-in sent, so the callback
/// may not belong to it. Refused.
class AuthStateMismatch extends AuthException {
  AuthStateMismatch() : super('The sign-in callback did not match');
}

/// The sign-in service answered the callback with `error` (and maybe
/// `error_description`).
class AuthCallbackError extends AuthException {
  AuthCallbackError(this.error, this.description)
    : super('The sign-in service refused: $error');

  final String error;
  final String? description;

  /// The account itself was turned away (access denied, or a sign-up or
  /// sign-in check on the service refused it), as opposed to a fault.
  bool get accountRefused =>
      error == 'access_denied' ||
      RegExp(
        r'^Pre\w+ failed with error',
        caseSensitive: false,
      ).hasMatch(description ?? '');
}

/// [raw] (a callback's `error_description`) as a short sentence, or null
/// when it says nothing. Drops the "PreSignUp failed with error" style prefix
/// the sign-in service puts before a check's own message.
String? readableAuthErrorDescription(String? raw) {
  if (raw == null) return null;
  var s =
      raw
          .replaceFirst(
            RegExp(r'^\s*\w+ failed with error\s*', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
  if (s.isEmpty) return null;
  if (s.length > 200) s = '${s.substring(0, 199).trimRight()}…';
  if (!RegExp(r'[.!?…]$').hasMatch(s)) s = '$s.';
  return s[0].toUpperCase() + s.substring(1);
}
