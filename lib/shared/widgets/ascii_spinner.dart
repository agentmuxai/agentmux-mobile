import 'dart:async';

import 'package:flutter/material.dart';

/// The frames of the app's spinner, in braille: the feed's working row and
/// the working chip turn through the same ones.
const spinnerFrames = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];

/// How long each frame stays.
const spinnerFrameTime = Duration(milliseconds: 120);

/// What shows when it is not turning: every dot lit.
const spinnerStill = '⠿';

/// A working agent's mark: a braille spinner that turns while [animate], a
/// still glyph when not (the platform asks for no animations, or the state is
/// not current). It repaints about 8 times a second, only itself, where the
/// fade it replaced woke every frame.
class AsciiSpinner extends StatefulWidget {
  const AsciiSpinner({
    super.key,
    required this.color,
    required this.animate,
    this.size = 12,
  });

  final Color color;
  final bool animate;
  final double size;

  @override
  State<AsciiSpinner> createState() => _AsciiSpinnerState();
}

class _AsciiSpinnerState extends State<AsciiSpinner> {
  Timer? _timer;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AsciiSpinner old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.animate && _timer == null) {
      _timer = Timer.periodic(spinnerFrameTime, (_) {
        if (mounted) setState(() => _frame++);
      });
    } else if (!widget.animate) {
      _timer?.cancel();
      _timer = null;
      _frame = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        // A glyph that changes 8 times a second is not for a screen reader to
        // read out: the chip's label already says the agent is working.
        child: ExcludeSemantics(
          child: Text(
            widget.animate ? spinnerFrames[_frame % spinnerFrames.length] : spinnerStill,
            style: TextStyle(color: widget.color, fontSize: widget.size, height: 1),
          ),
        ),
      );
}
