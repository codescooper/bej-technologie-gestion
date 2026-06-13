import 'package:integration_test/integration_test_driver.dart';

/// Driver standard pour exécuter les tests `integration_test/` via
/// `flutter drive` (cible web + chromedriver).
Future<void> main() => integrationDriver();
