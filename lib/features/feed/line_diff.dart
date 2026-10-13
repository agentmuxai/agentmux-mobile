/// A line diff for an Edit's preview: `old_string` → `new_string`.
enum DiffOp { same, removed, added }

class DiffLine {
  const DiffLine(this.op, this.text);
  final DiffOp op;
  final String text;
}

/// The lines of [before] and [after], each kept, removed or added, by their
/// longest common subsequence. Past [maxCells] (lines × lines) the diff is
/// every old line removed, then every new line added.
List<DiffLine> lineDiff(String before, String after, {int maxCells = 1000000}) {
  final a = before.isEmpty ? const <String>[] : before.split('\n');
  final b = after.isEmpty ? const <String>[] : after.split('\n');
  // Common head and tail first: an edit usually touches the middle.
  var head = 0;
  while (head < a.length && head < b.length && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < a.length - head &&
      tail < b.length - head &&
      a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
    tail++;
  }
  final x = a.sublist(head, a.length - tail);
  final y = b.sublist(head, b.length - tail);
  final out = <DiffLine>[
    for (final l in a.take(head)) DiffLine(DiffOp.same, l),
  ];
  if (x.length * y.length > maxCells) {
    out
      ..addAll(x.map((l) => DiffLine(DiffOp.removed, l)))
      ..addAll(y.map((l) => DiffLine(DiffOp.added, l)));
  } else {
    out.addAll(_lcs(x, y));
  }
  out.addAll(a.sublist(a.length - tail).map((l) => DiffLine(DiffOp.same, l)));
  return out;
}

List<DiffLine> _lcs(List<String> x, List<String> y) {
  final n = x.length;
  final m = y.length;
  // len[i][j]: the LCS of x[i..] and y[j..].
  final len = List.generate(n + 1, (_) => List.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      len[i][j] = x[i] == y[j]
          ? len[i + 1][j + 1] + 1
          : (len[i + 1][j] >= len[i][j + 1] ? len[i + 1][j] : len[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (x[i] == y[j]) {
      out.add(DiffLine(DiffOp.same, x[i]));
      i++;
      j++;
    } else if (len[i + 1][j] >= len[i][j + 1]) {
      out.add(DiffLine(DiffOp.removed, x[i++]));
    } else {
      out.add(DiffLine(DiffOp.added, y[j++]));
    }
  }
  while (i < n) {
    out.add(DiffLine(DiffOp.removed, x[i++]));
  }
  while (j < m) {
    out.add(DiffLine(DiffOp.added, y[j++]));
  }
  return out;
}
