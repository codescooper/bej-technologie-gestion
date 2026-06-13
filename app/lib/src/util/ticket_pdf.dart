import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'format.dart';

/// Une ligne du ticket de caisse.
class TicketLigne {
  final String nom;
  final int qte;
  final num prixUnitaire;
  final num sousTotal;
  TicketLigne(this.nom, this.qte, this.prixUnitaire, this.sousTotal);
}

/// Données d'un ticket de vente (reçu imprimable, §8).
class TicketData {
  final String magasin;
  final String ref;
  final DateTime date;
  final String? client;
  final List<TicketLigne> lignes;
  final num sousTotal;
  final num remise;
  final num jetons;
  final num avoir;
  final num total;
  final List<({String methode, num montant})> paiements;
  final int jetonsGagnes;

  TicketData({
    required this.magasin,
    required this.ref,
    required this.date,
    this.client,
    required this.lignes,
    required this.sousTotal,
    required this.remise,
    required this.jetons,
    required this.avoir,
    required this.total,
    required this.paiements,
    required this.jetonsGagnes,
  });
}

/// Libellé lisible d'un moyen de paiement.
String methodeLabel(String m) =>
    const {
      'cash': 'Espèces',
      'wave': 'Wave',
      'orange_money': 'Orange Money',
      'mtn_momo': 'MTN MoMo',
    }[m] ??
    m;

String _fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Construit le PDF du ticket (rouleau 57 mm, hauteur dynamique). Renvoie les
/// octets — testable sans dialogue d'impression.
Future<Uint8List> construireTicketPdf(TicketData t) async {
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll57.copyWith(
        marginTop: 6 * PdfPageFormat.mm,
        marginBottom: 6 * PdfPageFormat.mm,
        marginLeft: 4 * PdfPageFormat.mm,
        marginRight: 4 * PdfPageFormat.mm,
      ),
      build: (ctx) {
        pw.Widget row(String l, String v, {bool bold = false}) {
          final st = pw.TextStyle(
              fontSize: bold ? 10 : 8,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [pw.Text(l, style: st), pw.Text(v, style: st)],
          );
        }

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
                child: pw.Text('BEJ TECHNOLOGIE',
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold))),
            pw.Center(
                child: pw.Text(t.magasin, style: const pw.TextStyle(fontSize: 9))),
            pw.SizedBox(height: 6),
            pw.Text('Reçu : ${t.ref.length >= 8 ? t.ref.substring(0, 8) : t.ref}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.Text('Date : ${_fmtDate(t.date)}',
                style: const pw.TextStyle(fontSize: 8)),
            if (t.client != null)
              pw.Text('Client : ${t.client}',
                  style: const pw.TextStyle(fontSize: 8)),
            pw.Divider(thickness: 0.5),
            ...t.lignes.map((l) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(l.nom, style: const pw.TextStyle(fontSize: 9)),
                      row('${l.qte} x ${fcfa(l.prixUnitaire)}', fcfa(l.sousTotal)),
                    ],
                  ),
                )),
            pw.Divider(thickness: 0.5),
            row('Sous-total', fcfa(t.sousTotal)),
            if (t.remise > 0) row('Remise', '-${fcfa(t.remise)}'),
            if (t.jetons > 0) row('Jetons', '-${fcfa(t.jetons)}'),
            if (t.avoir > 0) row('Avoir', '-${fcfa(t.avoir)}'),
            pw.SizedBox(height: 2),
            row('TOTAL', fcfa(t.total), bold: true),
            pw.Divider(thickness: 0.5),
            ...t.paiements
                .map((p) => row(methodeLabel(p.methode), fcfa(p.montant))),
            if (t.jetonsGagnes > 0) ...[
              pw.SizedBox(height: 2),
              pw.Text('+ ${t.jetonsGagnes} jetons gagnés',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
            pw.SizedBox(height: 8),
            pw.Center(
                child: pw.Text('Merci de votre visite !',
                    style: const pw.TextStyle(fontSize: 9))),
            pw.Center(
                child: pw.Text('Reçu interne — non fiscal',
                    style: pw.TextStyle(
                        fontSize: 7, color: PdfColors.grey700))),
          ],
        );
      },
    ),
  );
  return doc.save();
}

/// Ouvre le dialogue d'impression du navigateur avec le ticket.
Future<void> imprimerTicket(TicketData t) async {
  await Printing.layoutPdf(onLayout: (format) => construireTicketPdf(t));
}
