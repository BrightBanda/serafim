import 'package:flutter/widgets.dart';

/// Marks every element below [context] dirty so the whole subtree rebuilds,
/// including `const` widgets and cached pages that would otherwise keep
/// painting with stale colors after the palette changes. Navigation stacks,
/// scroll positions and state are preserved.
void rebuildEverythingBelow(BuildContext context) {
  void mark(Element element) {
    element.markNeedsBuild();
    element.visitChildren(mark);
  }

  (context as Element).visitChildren(mark);
}
