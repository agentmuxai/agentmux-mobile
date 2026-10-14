import 'tool_meta.dart';
import 'transcript.dart';

/// Whether each tool call's preview is open, by the desktop's rules
/// (`virtualization/disclosure.ts`;
/// `SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §6.2):
///
/// - a running call is open;
/// - a call that finished while on screen is held open until it scrolls off
///   the top;
/// - a content-first call (WebSearch) is open once finished;
/// - everything else is closed;
/// - a tap opens a closed call (a pin) or closes an open one.
///
/// Keyed by item key, so it belongs to one transcript: [clear] it with a
/// fresh snapshot.
class ToolDisclosure {
  final _pinned = <int>{};
  final _closed = <int>{};
  final _held = <int>{};

  bool isOpen(ToolCallItem tool) {
    final k = tool.key;
    if (_closed.contains(k)) return false;
    if (_pinned.contains(k)) return true;
    if (tool.state == ToolState.running && tool.name != 'AskUserQuestion') return true;
    if (isContentFirst(tool)) return true;
    return _held.contains(k) && !isDismissed(tool.state);
  }

  void toggle(ToolCallItem tool) {
    final k = tool.key;
    if (isOpen(tool)) {
      _pinned.remove(k);
      _held.remove(k);
      _closed.add(k);
    } else {
      _closed.remove(k);
      _pinned.add(k);
    }
  }

  /// [tool] finished while on screen: keep it open for now.
  void hold(int key) => _held.add(key);

  /// A held call scrolled off: it closes, unless pinned.
  bool release(int key) => _held.remove(key);

  Iterable<int> get held => _held;

  void clear() {
    _pinned.clear();
    _closed.clear();
    _held.clear();
  }
}
