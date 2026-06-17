import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'format.dart';

/// Orange BEJ (habillage des étiquettes). Le QR lui-même reste FONCÉ pour une
/// lecture fiable ; l'orange sert au cadre, au logo et au texte de marque.
const PdfColor kOrangeBej = PdfColor.fromInt(0xFFFF6F00);

/// Support d'impression choisi par l'utilisateur (selon son matériel).
enum FormatEtiquette { plancheA4, rouleauEtiquette, thermique57 }

String formatEtiquetteLabel(FormatEtiquette f) {
  switch (f) {
    case FormatEtiquette.plancheA4:
      return 'Planche A4 (couleur)';
    case FormatEtiquette.rouleauEtiquette:
      return "Rouleau d'étiquettes";
    case FormatEtiquette.thermique57:
      return 'Rouleau thermique 57 mm';
  }
}

/// Une étiquette à imprimer. `code` = payload encodé dans le QR (scanné) ;
/// `codeClair` = valeur lisible imprimée SOUS le QR (saisie manuelle de secours).
class EtiquetteLabel {
  final String code;
  final String codeClair;
  final String titre;
  final String? sousTitre;
  EtiquetteLabel({
    required this.code,
    required this.codeClair,
    required this.titre,
    this.sousTitre,
  });

  /// Étiquette VENTE : QR = payload `BEJ-P-<id>` ; code en clair = code-barres
  /// (typeable) s'il existe, sinon le payload ; titre = nom, sous-titre = prix.
  factory EtiquetteLabel.vente({
    required String payload,
    String? codeBarres,
    required String nom,
    required num prix,
  }) =>
      EtiquetteLabel(
        code: payload,
        codeClair:
            (codeBarres != null && codeBarres.isNotEmpty) ? codeBarres : payload,
        titre: nom,
        sousTitre: fcfa(prix),
      );

  /// Étiquette RÉPARATION : sticker vierge, QR = code en clair = `BEJ-R-<…>`.
  factory EtiquetteLabel.reparation({required String code}) => EtiquetteLabel(
        code: code,
        codeClair: code,
        titre: 'Réparation',
      );
}

/// Carte verticale (planche A4 + rouleau thermique) : marque, QR foncé, code en
/// clair sous le QR, puis titre / sous-titre.
pw.Widget _carteVerticale(
  EtiquetteLabel l, {
  required PdfColor accent,
  required double qrSize,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(4),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: accent, width: 0.8),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text('BEJ TECHNOLOGIE',
            style: pw.TextStyle(
                fontSize: 7, fontWeight: pw.FontWeight.bold, color: accent)),
        pw.SizedBox(height: 3),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: l.code,
          width: qrSize,
          height: qrSize,
          color: PdfColors.black, // QR foncé = lecture fiable
          drawText: false,
        ),
        pw.SizedBox(height: 2),
        pw.Text(l.codeClair,
            style: pw.TextStyle(font: pw.Font.courier(), fontSize: 7)),
        if (l.titre.isNotEmpty)
          pw.Text(l.titre,
              maxLines: 2,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8)),
        if (l.sousTitre != null)
          pw.Text(l.sousTitre!,
              style:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

/// Carte horizontale (rouleau d'étiquettes ~50×30 mm) : QR à gauche, infos à droite.
pw.Widget _carteHorizontale(EtiquetteLabel l, {required PdfColor accent}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.BarcodeWidget(
        barcode: pw.Barcode.qrCode(),
        data: l.code,
        width: 22 * PdfPageFormat.mm,
        height: 22 * PdfPageFormat.mm,
        color: PdfColors.black,
        drawText: false,
      ),
      pw.SizedBox(width: 4),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.center,
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text('BEJ TECHNOLOGIE',
                style: pw.TextStyle(
                    fontSize: 6, fontWeight: pw.FontWeight.bold, color: accent)),
            pw.Text(l.codeClair,
                style: pw.TextStyle(font: pw.Font.courier(), fontSize: 7)),
            if (l.titre.isNotEmpty)
              pw.Text(l.titre,
                  maxLines: 2, style: const pw.TextStyle(fontSize: 7)),
            if (l.sousTitre != null)
              pw.Text(l.sousTitre!,
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    ],
  );
}

void _ajouterPlancheA4(pw.Document doc, List<EtiquetteLabel> labels) {
  const cols = 3;
  final cellW = 62 * PdfPageFormat.mm;
  final rows = <pw.Widget>[];
  for (var i = 0; i < labels.length; i += cols) {
    final fin = (i + cols) > labels.length ? labels.length : i + cols;
    final slice = labels.sublist(i, fin);
    final cells = <pw.Widget>[];
    for (final l in slice) {
      cells.add(pw.Container(
        width: cellW,
        margin: const pw.EdgeInsets.all(4),
        child: _carteVerticale(l, accent: kOrangeBej, qrSize: 34 * PdfPageFormat.mm),
      ));
    }
    for (var k = slice.length; k < cols; k++) {
      cells.add(pw.Container(width: cellW, margin: const pw.EdgeInsets.all(4)));
    }
    rows.add(pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start, children: cells));
  }
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.copyWith(
      marginTop: 8 * PdfPageFormat.mm,
      marginBottom: 8 * PdfPageFormat.mm,
      marginLeft: 6 * PdfPageFormat.mm,
      marginRight: 6 * PdfPageFormat.mm,
    ),
    build: (ctx) => rows,
  ));
}

/// Construit le PDF d'une planche/série d'étiquettes QR (testable). Renvoie les
/// octets. QR foncé + habillage orange (sauf thermique, monochrome).
Future<Uint8List> construireEtiquettesPdf(
    List<EtiquetteLabel> labels, FormatEtiquette format) async {
  final doc = pw.Document();

  if (labels.isEmpty) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Center(child: pw.Text('Aucune étiquette à imprimer.')),
    ));
    return doc.save();
  }

  switch (format) {
    case FormatEtiquette.plancheA4:
      _ajouterPlancheA4(doc, labels);
      break;
    case FormatEtiquette.rouleauEtiquette:
      final pf = PdfPageFormat(
        50 * PdfPageFormat.mm,
        30 * PdfPageFormat.mm,
        marginAll: 2 * PdfPageFormat.mm,
      );
      for (final l in labels) {
        doc.addPage(pw.Page(
          pageFormat: pf,
          build: (_) => _carteHorizontale(l, accent: kOrangeBej),
        ));
      }
      break;
    case FormatEtiquette.thermique57:
      final pf = PdfPageFormat.roll57.copyWith(
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 4 * PdfPageFormat.mm,
        marginLeft: 4 * PdfPageFormat.mm,
        marginRight: 4 * PdfPageFormat.mm,
      );
      for (final l in labels) {
        doc.addPage(pw.Page(
          pageFormat: pf,
          build: (_) => pw.Center(
            child: _carteVerticale(l,
                accent: PdfColors.black, qrSize: 38 * PdfPageFormat.mm),
          ),
        ));
      }
      break;
  }
  return doc.save();
}

/// Ouvre le dialogue d'impression avec la planche/série d'étiquettes.
Future<void> imprimerEtiquettes(
    List<EtiquetteLabel> labels, FormatEtiquette format) async {
  await Printing.layoutPdf(
      onLayout: (_) => construireEtiquettesPdf(labels, format));
}
