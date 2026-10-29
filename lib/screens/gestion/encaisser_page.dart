import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/actions.dart';
import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../services/recu.dart';
import '../../theme/harem_theme.dart';
import '../../utils/format.dart';
import '../../widgets/commun.dart';

/// Notes envoyées par les serveuses avec « Encaisser ».
class EncaisserPage extends StatelessWidget {
  const EncaisserPage({super.key, required this.membre});
  final Membre membre;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: Requetes.notesDeLaSoiree(etats: const ['to_pay']),
      builder: (context, snap) {
        final notes = snap.data ?? const [];
        if (snap.hasData && notes.isEmpty) {
          return const Vide('Aucune note à encaisser.\nQuand une serveuse appuie sur « Encaisser », la note arrive ici.',
              icone: Icons.point_of_sale);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: notes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final n = notes[i];
            final reste = entier(n['total']) - entier(n['paid_amount']);
            return Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), side: const BorderSide(color: HC.or, width: 1.5)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                title: Text('${n['table_name'] ?? 'Table'}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                subtitle: Text('Serveuse : ${n['waitress_name'] ?? ''}'
                    '${entier(n['paid_amount']) > 0 ? ' · déjà payé ${fcfa(entier(n['paid_amount']))}' : ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(fcfa(reste), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: HC.or)),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => encaisserNote(context, membre, n['id'] as String),
                    child: const Text('Encaisser'),
                  ),
                ]),
                onTap: () => encaisserNote(context, membre, n['id'] as String),
              ),
            );
          },
        );
      },
    );
  }
}

/// Fenêtre d'encaissement d'une note (paiement en une ou plusieurs fois).
Future<void> encaisserNote(BuildContext context, Membre membre, String tabId) {
  return showDialog<void>(
    context: context,
    builder: (_) => _Encaissement(membre: membre, tabId: tabId),
  );
}

class _Encaissement extends StatefulWidget {
  const _Encaissement({required this.membre, required this.tabId});
  final Membre membre;
  final String tabId;

  @override
  State<_Encaissement> createState() => _EncaissementState();
}

class _EncaissementState extends State<_Encaissement> {
  final _montant = TextEditingController();
  final _donne = TextEditingController();
  String _methode = 'cash';
  bool _envoi = false;

  @override
  void dispose() {
    _montant.dispose();
    _donne.dispose();
    super.dispose();
  }

  Future<void> _valider(int reste) async {
    final montant = _montant.text.trim().isEmpty ? reste : lireNombre(_montant);
    setState(() => _envoi = true);
    try {
      final nouveauReste = await Club.encaisser(widget.membre, widget.tabId, _methode, montant);
      if (!mounted) return;
      if (nouveauReste == 0) {
        await _imprimerQuandPret();
        if (mounted) Navigator.pop(context);
      } else {
        _montant.clear();
        _donne.clear();
        info(context, 'Paiement enregistré. Reste ${fcfa(nouveauReste)} à payer.');
      }
    } catch (e) {
      if (mounted) erreur(context, e);
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// Attend quelques secondes le numéro du reçu donné par le serveur, puis imprime.
  Future<void> _imprimerQuandPret() async {
    for (var i = 0; i < 8; i++) {
      final r = await db.getOptional('SELECT ticket_number FROM tabs WHERE id = ?', [widget.tabId]);
      if (r?['ticket_number'] != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;
    try {
      await Recu.imprimer(context, widget.tabId);
    } catch (e) {
      if (mounted) erreur(context, Exception('Reçu non imprimé : $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: Requetes.note(widget.tabId),
      builder: (context, snap) {
        final note = (snap.data ?? const []).firstOrNull;
        if (note == null) return const AlertDialog(content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())));
        final total = entier(note['total']);
        final paye = entier(note['paid_amount']);
        final reste = total - paye;
        final donne = lireNombre(_donne);
        final montant = _montant.text.trim().isEmpty ? reste : lireNombre(_montant);
        final monnaie = _methode == 'cash' && donne > montant ? donne - montant : 0;
        return AlertDialog(
          title: Text('Encaisser · ${note['table_name'] ?? 'Table'}'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                StreamBuilder<Lignes>(
                  stream: db.watch(
                    'SELECT product_name, unit_price, SUM(quantity) AS q FROM tab_items '
                    "WHERE tab_id = ? AND status = 'served' GROUP BY product_name, unit_price ORDER BY MIN(requested_at)",
                    parameters: [widget.tabId],
                  ),
                  builder: (context, s) => Column(children: [
                    for (final l in s.data ?? const <Map<String, dynamic>>[])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Text('${entier(l['q'])} × ', style: const TextStyle(fontWeight: FontWeight.w800)),
                          Expanded(child: Text('${l['product_name']}')),
                          Text(fcfa(entier(l['q']) * entier(l['unit_price']))),
                        ]),
                      ),
                  ]),
                ),
                const Divider(height: 24),
                _ligne('Total', fcfa(total), gras: true),
                if (paye > 0) _ligne('Déjà payé', fcfa(paye)),
                _ligne('Reste à payer', fcfa(reste), gras: true, couleur: HC.or, taille: 22),
                if (note['status'] == 'paid') ...[
                  const SizedBox(height: 16),
                  const Pastille('Note encaissée', couleur: HC.vert, fond: HC.fondVert),
                ],
                if (note['status'] == 'to_pay') ...[
                  const SizedBox(height: 20),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'cash', label: Text('Espèces'), icon: Icon(Icons.payments_outlined)),
                      ButtonSegment(value: 'mobile_money', label: Text('Mobile Money'), icon: Icon(Icons.phone_android)),
                    ],
                    selected: {_methode},
                    onSelectionChanged: (s) => setState(() => _methode = s.first),
                  ),
                  const SizedBox(height: 16),
                  ChampNombre(
                    controller: _montant,
                    label: 'Montant de ce paiement (vide = tout le reste : ${milliers(reste)})',
                    suffixe: 'FCFA',
                    onSubmitted: (_) => _valider(reste),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  const Text('Pour un paiement en plusieurs fois, entrez seulement la partie payée maintenant.',
                      style: TextStyle(color: HC.gris, fontSize: 12.5)),
                  if (_methode == 'cash') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _donne,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Billets donnés par le client (facultatif)', suffixText: 'FCFA'),
                      onChanged: (_) => setState(() {}),
                    ),
                    if (monnaie > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _ligne('Monnaie à rendre', fcfa(monnaie), gras: true, couleur: HC.vert),
                      ),
                  ],
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Recu.imprimer(context, widget.tabId),
              child: const Text('Imprimer la note'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
            if (note['status'] == 'to_pay')
              FilledButton(
                onPressed: _envoi ? null : () => _valider(reste),
                child: Text(montant >= reste ? 'Encaisser ${fcfa(reste)}' : 'Encaisser ${fcfa(montant)}'),
              ),
          ],
        );
      },
    );
  }

  Widget _ligne(String g, String d, {bool gras = false, Color? couleur, double taille = 16}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(g, style: TextStyle(fontSize: 15, color: gras ? HC.texte : HC.gris))),
          Text(d, style: TextStyle(fontSize: taille, fontWeight: gras ? FontWeight.w800 : FontWeight.w500, color: couleur)),
        ]),
      );
}
