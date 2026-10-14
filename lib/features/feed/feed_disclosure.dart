import 'tool_meta.dart';
import 'transcript.dart';

/// Whether each row that opens is open, by the desktop's rules
/// (`virtualization/disclosure.ts`;
/// `SPEC_FEED_RENDERS_LIKE_THE_DESKTOP_PANE_2026_10_13.md` §6.2, §7):
///
/// - a running tool call is open;
/// - a tool call that finished while on screen, or a jekt that arrived on
///   screen, is held open until it scrolls off the top;
/// - a content-first call (WebSearch) and a sensitive jekt are open;
/// - everything else is closed (reminders, context, other jekts);
/// - a tap opens a closed row (a pin) or closes an open one.
///
/// Keyed by item key, so it belongs to one transcript: [clear] it with a
/// fresh snapshot.
class FeedDisclosure {
  final _pinned = <int>{};
  final _closed = <int>{};
  final _held = <int>{};

  /// Whether [item] is a row that opens at all.
  static bool opens(TranscriptItem item) =>
      item is ToolCallItem || item is JektItem || item is ContextItem || item is DeliveryItem;

  bool isOpen(TranscriptItem item) {
    final k = item.key;
    if (_closed.contains(k)) return false;
    if (_pinned.contains(k)) return true;
    return switch (item) {
      final ToolCallItem t => (t.state == ToolState.running && t.name != 'AskUserQuestion') ||
          isContentFirst(t) ||
          (_held.contains(k) && !isDismissed(t.state)),
      JektItem(:final jekt) => jekt.sensitive || _held.contains(k),
      _ => false,
    };
  }

  void toggle(TranscriptItem item) {
    final k = item.key;
    if (isOpen(item)) {
      _pinned.remove(k);
      _held.remove(k);
      _closed.add(k);
    } else {
      _closed.remove(k);
      _pinned.add(k);
    }
  }

  /// [key]'s row finished or arrived on screen: keep it open for now.
  void hold(int key) => _held.add(key);

  /// A held row scrolled off: it closes, unless pinned.
  bool release(int key) => _held.remove(key);

  Iterable<int> get held => _held;

  void clear() {
    _pinned.clear();
    _closed.clear();
    _held.clear();
  }
}
