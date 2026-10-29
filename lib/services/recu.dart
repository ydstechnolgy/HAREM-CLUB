import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/base_locale.dart';
import '../utils/format.dart';
import 'appareil.dart' as appareil;

/// Reçu d'une note, imprimé sur l'imprimante à tickets (80 mm) du bar.
class Recu {
  Recu._();

  static const _fichierImprimante = 'imprimante.json';

  /// Imprimante choisie sur ce PC (null : demander à chaque fois).
  static Future<Printer?> imprimante() async {
    try {
      final brut = await appareil.lireDonnee(_fichierImprimante);
      if (brut == null) return null;
      final j = jsonDecode(brut) as Map<String, dynamic>;
      return Printer(url: j['url'] as String, name: j['name'] as String?);
    } catch (_) {
      return null;
    }
  }

  static Future<void> oublierImprimante() => appareil.effacerDonnee(_fichierImprimante);

  /// Choisit l'imprimante à tickets une fois pour toutes sur ce PC.
  static Future<Printer?> choisirImprimante(BuildContext context) async {
    if (kIsWeb) return null;
    final p = await Printing.pickPrinter(context: context, title: 'Imprimante à tickets');
    if (p != null) {
      await appareil.ecrireDonnee(_fichierImprimante, jsonEncode({'url': p.url, 'name': p.name}));
    }
    return p;
  }

  /// Fabrique le reçu d'une note à partir de la base locale.
  static Future<Uint8List> pdf(String tabId) async {
    final note = await db.get(
      'SELECT t.*, ct.name AS table_name, m.display_name AS waitress_name '
      'FROM tabs t LEFT JOIN club_tables ct ON ct.id = t.table_id '
      'LEFT JOIN members m ON m.id = t.waitress_id WHERE t.id = ?',
      [tabId],
    );
    final lignes = await db.getAll(
      'SELECT product_name, unit_price, SUM(quantity) AS q FROM tab_items '
      "WHERE tab_id = ? AND status = 'served' GROUP BY product_name, unit_price ORDER BY MIN(requested_at)",
      [tabId],
    );
    final paiements = await db.getAll(
        'SELECT method, SUM(amount) AS a FROM payments WHERE tab_id = ? GROUP BY method', [tabId]);
    final reglages = await db.getOptional('SELECT * FROM settings LIMIT 1');

    final entete = '${reglages?['ticket_header'] ?? 'HAREM CLUB'}';
    final telephone = reglages?['phone'] as String?;
    final pied = '${reglages?['ticket_footer'] ?? 'Merci de votre visite'}';
    final date = DateTime.tryParse('${note['paid_at'] ?? note['requested_at'] ?? ''}')?.toLocal() ?? DateTime.now();
    final numero = note['ticket_number'];

    final petit = pw.TextStyle(fontSize: 8.5);
    final gras = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    pw.Widget ligne(String g, String d, {pw.TextStyle? style}) => pw.Row(children: [
          pw.Expanded(child: pw.Text(g, style: style ?? petit)),
          pw.Text(d, style: style ?? petit),
        ]);

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(5 * PdfPageFormat.mm),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(entete, textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
        if (telephone != null && telephone.isNotEmpty)
          pw.Text(telephone, textAlign: pw.TextAlign.center, style: petit),
        pw.SizedBox(height: 6),
        ligne(numero != null ? 'Reçu n° $numero' : 'Reçu', '${dateCourte(date)} ${_heure(date)}'),
        ligne('${note['table_name'] ?? 'Table'}', 'Serveuse : ${note['waitress_name'] ?? ''}'),
        pw.Divider(thickness: 0.5),
        for (final l in lignes) ...[
          pw.Text('${l['product_name']}', style: gras),
          ligne('  ${entier(l['q'])} x ${milliers(entier(l['unit_price']))}',
              milliers(entier(l['q']) * entier(l['unit_price']))),
        ],
        pw.Divider(thickness: 0.5),
        ligne('TOTAL', fcfa(entier(note['total'])),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        for (final p in paiements)
          ligne(p['method'] == 'mobile_money' ? 'Mobile Money' : 'Espèces', fcfa(entier(p['a']))),
        if (entier(note['total']) > entier(note['paid_amount']))
          ligne('RESTE À PAYER', fcfa(entier(note['total']) - entier(note['paid_amount'])), style: gras),
        pw.SizedBox(height: 10),
        pw.Text(pied, textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic)),
      ]),
    ));
    return doc.save();
  }

  static String _heure(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  /// Imprime le reçu : directement sur l'imprimante choisie, sinon via la fenêtre d'impression.
  static Future<void> imprimer(BuildContext context, String tabId) async {
    final octets = await pdf(tabId);
    final p = kIsWeb ? null : await imprimante();
    if (p != null) {
      final ok = await Printing.directPrintPdf(
          printer: p, format: PdfPageFormat.roll80, name: 'Recu-Harem-Club', onLayout: (_) async => octets);
      if (ok) return;
    }
    await Printing.layoutPdf(name: 'Recu-Harem-Club', format: PdfPageFormat.roll80, onLayout: (_) async => octets);
  }
}
