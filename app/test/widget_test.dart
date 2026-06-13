// Test de fumée minimal. Le parcours applicatif réel (qui nécessite un vrai
// client PowerSync web + le backend) est couvert par les tests d'intégration
// dans `integration_test/` via `flutter drive`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Sanity — un widget se rend', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Text('BEJ')),
    ));
    expect(find.text('BEJ'), findsOneWidget);
  });
}
