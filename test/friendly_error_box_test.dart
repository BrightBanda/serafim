import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/friendly_error_box.dart';

void main() {
  testWidgets('a crashed widget is replaced by a plain, human message', (
    tester,
  ) async {
    // Rendered with no Theme/Directionality above it, as it would be when a
    // widget near the top of the tree fails.
    await tester.pumpWidget(const FriendlyErrorBox());
    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
