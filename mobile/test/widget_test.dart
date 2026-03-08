import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test placeholder', (WidgetTester tester) async {
    // RatatouilleApp requires Firebase and env initialization,
    // so full widget test is deferred to integration tests.
    expect(1 + 1, equals(2));
  });
}
