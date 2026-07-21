// Smoke test — verifies the app boots to the splash screen without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cypherfy/app.dart';

void main() {
  testWidgets('App builds and shows the splash lock icon',
      (WidgetTester tester) async {
    // Riverpod requires a ProviderScope at the root.
    await tester.pumpWidget(ProviderScope(child: CypherFyApp()));
    await tester.pump();

    // The splash screen renders a lock icon.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });
}
