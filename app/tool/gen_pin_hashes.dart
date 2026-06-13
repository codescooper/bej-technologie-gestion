// Outil de développement : précalcule les empreintes PBKDF2 des PIN de seed.
// Lancer depuis le dossier app :  dart run tool/gen_pin_hashes.dart
// Coller les lignes <id>|<empreinte> dans bootstrap.dart et 008_pins.sql.
import 'package:bej_gestion/src/util/pin_hash.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';

void main() {
  final users = <List<String>>[
    [RefIds.userAdmin, '1111'],
    [RefIds.userAwaCaissiere, '2222'],
    [RefIds.userResponsable, '3333'],
    [RefIds.userTechnicien, '4444'],
  ];
  for (final u in users) {
    print('${u[0]}|${PinHash.hash(u[1], u[0])}');
  }
}
