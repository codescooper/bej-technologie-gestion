import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bej_gestion/src/app_session.dart';
import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/repositories/auth_repository.dart';
import 'package:bej_gestion/src/ui/login_page.dart';

/// Authentification + rôles (§6) : comptes, login OK/KO, permissions par rôle,
/// et écran de connexion.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Comptes, login et permissions par rôle', (tester) async {
    final db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
    final auth = AuthRepository(db);

    final comptes = await auth.comptes();
    expect(comptes.length, greaterThanOrEqualTo(4));

    // PIN incorrect -> échec.
    expect((await auth.login(RefIds.userAwaCaissiere, '0000')).reussi, isFalse);

    // Caissier.
    final awa = (await auth.login(RefIds.userAwaCaissiere, '2222')).user;
    expect(awa, isNotNull);
    expect(awa!.roleCode, 'caissier');
    final s = AppSession()..login(awa);
    expect(s.peutEncaisser, true);
    expect(s.peutCaisse, true);
    expect(s.peutAjusterStock, false);
    expect(s.peutValiderRetour, false);
    expect(s.peutDashboard, false);

    // Responsable.
    final ben = (await auth.login(RefIds.userResponsable, '3333')).user;
    expect(ben!.roleCode, 'responsable');
    s.login(ben);
    expect(s.peutAjusterStock, true);
    expect(s.peutValiderRetour, true);
    expect(s.peutDashboard, true);
    expect(s.peutDashboardGlobal, false);

    // Technicien.
    final koffi = (await auth.login(RefIds.userTechnicien, '4444')).user;
    expect(koffi!.roleCode, 'technicien');
    s.login(koffi);
    expect(s.peutEncaisser, false);
    expect(s.peutCaisse, false);
    expect(s.peutModifierDiagnostic, true);

    // Admin.
    final admin = (await auth.login(RefIds.userAdmin, '1111')).user;
    s.login(admin!);
    expect(s.peutDashboardGlobal, true);

    debugPrint('AUTH_OK');
  });

  testWidgets('Écran de connexion : login fixe la session', (tester) async {
    final db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
    final session = AppSession()..logout();
    expect(session.authentifie, false);

    await tester.pumpWidget(MaterialApp(
      home: LoginPage(authRepo: AuthRepository(db), session: session),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Se connecter'), findsOneWidget);

    // Le compte par défaut (1er alphabétique) est l'Administrateur (PIN 1111).
    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.widgetWithText(FilledButton, 'Se connecter'));
    // La vérification PBKDF2 n'est pas instantanée et pumpAndSettle n'attend pas
    // un Future arbitraire : on pompe jusqu'à ce que la session soit connectée.
    for (var i = 0; i < 60 && !session.authentifie; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(session.authentifie, true);
    expect(session.roleCode, 'admin');
  });

  testWidgets('Verrouillage après plusieurs échecs de PIN', (tester) async {
    final db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
    final auth = AuthRepository(db);

    // maxTentatives mauvais PIN consécutifs sur le compte technicien.
    for (var i = 0; i < AuthRepository.maxTentatives; i++) {
      final r = await auth.login(RefIds.userTechnicien, '9999');
      expect(r.reussi, isFalse);
    }
    // Désormais verrouillé : même le bon PIN est refusé temporairement.
    final bon = await auth.login(RefIds.userTechnicien, '4444');
    expect(bon.verrouille, isTrue);
    expect(bon.secondesVerrou, greaterThan(0));
    debugPrint('VERROU_OK secondes=${bon.secondesVerrou}');
  });
}
