import 'package:flutter/widgets.dart';

/// The padding for a scrolling list that fills a screen: [base] plus the
/// safe-area insets this part of the screen still has to keep clear of.
///
/// Flutter's `ListView` adds the safe area to its padding only when `padding`
/// is null. A list that sets its own padding drops it: in landscape its cards
/// then run under the notch or the Dynamic Island, and the last one reaches
/// into the curved bottom of the screen, under the home indicator. A
/// `Scaffold` has already taken what its app bar and bottom bar cover out of
/// the body's `MediaQuery`, so this adds only what is left.
EdgeInsets insetListPadding(BuildContext context, EdgeInsets base) =>
    base + MediaQuery.paddingOf(context);
