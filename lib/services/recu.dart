import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/base_locale.dart';
import '../theme/harem_theme.dart';
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
      'SELECT t.*, ct.name AS table_name FROM tabs t '
      'LEFT JOIN club_tables ct ON ct.id = t.table_id WHERE t.id = ?',
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
      pageFormat: PdfPageFormat.roll57,
      margin: const pw.EdgeInsets.all(3 * PdfPageFormat.mm),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(entete, textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
        if (telephone != null && telephone.isNotEmpty)
          pw.Text(telephone, textAlign: pw.TextAlign.center, style: petit),
        pw.SizedBox(height: 6),
        ligne(numero != null ? 'Reçu n° $numero' : 'Reçu', '${dateCourte(date)} ${_heure(date)}'),
        pw.Text('${note['table_name'] ?? 'Table'}', style: gras),
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
          printer: p, format: PdfPageFormat.roll57, name: 'Recu-Harem-Club', onLayout: (_) async => octets);
      if (ok) return;
    }
    await Printing.layoutPdf(name: 'Recu-Harem-Club', format: PdfPageFormat.roll57, onLayout: (_) async => octets);
  }

  // ---------------------------------------------------------------- WhatsApp

  /// Le reçu en texte, prêt pour WhatsApp (le *gras* est compris par WhatsApp).
  static Future<String> texte(String tabId) async {
    final note = await db.get(
      'SELECT t.*, ct.name AS table_name FROM tabs t LEFT JOIN club_tables ct ON ct.id = t.table_id WHERE t.id = ?',
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
    final date = DateTime.tryParse('${note['paid_at'] ?? note['requested_at'] ?? ''}')?.toLocal() ?? DateTime.now();
    final total = entier(note['total']);
    final reste = total - entier(note['paid_amount']);

    final b = StringBuffer()
      ..writeln('*${reglages?['ticket_header'] ?? 'HAREM CLUB'}*')
      ..writeln(note['ticket_number'] != null ? 'Reçu n° ${note['ticket_number']}' : 'Note')
      ..writeln('${note['table_name'] ?? 'Table'} · ${dateCourte(date)} ${_heure(date)}')
      ..writeln();
    for (final l in lignes) {
      b.writeln('${entier(l['q'])} × ${l['product_name']} : ${fcfa(entier(l['q']) * entier(l['unit_price']))}');
    }
    b
      ..writeln()
      ..writeln('*TOTAL : ${fcfa(total)}*');
    for (final p in paiements) {
      b.writeln('${p['method'] == 'mobile_money' ? 'Mobile Money' : 'Espèces'} : ${fcfa(entier(p['a']))}');
    }
    if (reste > 0) b.writeln('*Reste à payer : ${fcfa(reste)}*');
    final tel = reglages?['phone'] as String?;
    b.writeln();
    if (tel != null && tel.isNotEmpty) b.writeln('Contact : $tel');
    b.write('${reglages?['ticket_footer'] ?? 'Merci de votre visite'}');
    return b.toString();
  }

  /// Numéro saisi → format international (8 chiffres du Togo → 228…).
  static String? numeroWhatsApp(String saisi) {
    var n = saisi.replaceAll(RegExp(r'[^0-9]'), '');
    if (n.startsWith('00')) n = n.substring(2);
    if (n.length == 8) n = '228$n';
    return n.length >= 10 ? n : null;
  }

  /// Demande le numéro du client puis ouvre WhatsApp avec le reçu prêt à envoyer.
  static Future<void> envoyerWhatsApp(BuildContext context, String tabId) async {
    final ctrl = TextEditingController();
    final numero = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Envoyer le reçu par WhatsApp'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Numéro WhatsApp du client',
              hintText: 'ex. 90 12 34 56',
              helperText: 'Numéro du Togo sur 8 chiffres, ou avec l\'indicatif (+229…).',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            icon: const Icon(Icons.send),
            label: const Text('Ouvrir WhatsApp'),
          ),
        ],
      ),
    );
    if (numero == null || !context.mounted) return;
    final n = numeroWhatsApp(numero);
    if (n == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: HC.fondRouge, content: Text('Numéro incomplet. Exemple : 90 12 34 56')));
      return;
    }
    final message = await texte(tabId);
    final lien = Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(message)}');
    final ok = await launchUrl(lien, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: HC.fondRouge, content: Text('WhatsApp n\'a pas pu s\'ouvrir sur cet appareil.')));
    }
  }
}
