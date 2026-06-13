/// Appareil d'un client (§7). Clé de dédup = IMEI (sinon numéro de série, §2.6).
class Appareil {
  final String id;
  final String clientId;
  final String? type;
  final String? marque;
  final String? modele;
  final String? imei;
  final String? numeroSerie;
  final String? notes;

  Appareil({
    required this.id,
    required this.clientId,
    this.type,
    this.marque,
    this.modele,
    this.imei,
    this.numeroSerie,
    this.notes,
  });

  factory Appareil.fromRow(Map<String, dynamic> r) => Appareil(
        id: r['id'] as String,
        clientId: r['client_id'] as String,
        type: r['type'] as String?,
        marque: r['marque'] as String?,
        modele: r['modele'] as String?,
        imei: r['imei'] as String?,
        numeroSerie: r['numero_serie'] as String?,
        notes: r['notes'] as String?,
      );
}
