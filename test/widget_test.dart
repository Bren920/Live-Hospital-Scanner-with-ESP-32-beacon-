// Basic smoke test for Hospital Scanner app.

import 'package:flutter_test/flutter_test.dart';

import 'package:hospital_scanner/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const HospitalScannerApp());

    // Verify the main heading is present.
    expect(find.text('Equipment Tracker'), findsOneWidget);
  });
}
