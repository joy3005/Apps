import 'package:flutter_test/flutter_test.dart';
import 'package:jeyam_dairy/main.dart'; // Ensure this matches your project name

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const JeyamDairyApp());
  });
}
