import 'package:flutter/material.dart';

import '../../data/actions.dart';
import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../services/recu.dart';
import '../../theme/harem_theme.dart';
import '../../utils/format.dart';
import '../../widgets/commun.dart';
import '../commun/commande.dart';
import '../serveuse/choix_table.dart';
import 'encaisser_page.dart';

/// Toutes les notes de la soirée : en cours, à encaisser, encaissées.
class NotesPage extends StatelessWidget {
  const NotesPage({super.key, required this.membre});
  final Membre membre;

  Future<void> _ouvrirTable(BuildContext context) async {
    final soiree = await Club.soireeOuverteId();
    if (!context.mounted) return;
    if (soiree == null) {
      erreur(context, Exception('Ouvrez d\'abord la soirée (Soirée et caisse > Ouvrir la soirée).'));
      return;
    }
    final tabId = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => ChoixTable(membre: membre)));
    if (tabId != null && context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => NoteGestion(membre: membre, tabId: tabId)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: Requetes.notesDeLaSoiree(),
      builder: (context, snap) {
        final notes = snap.data ?? const [];
        final enCours = notes.where((n) => n['status'] == 'open' || n['status'] == 'to_pay').toList();
        final payees = notes.where((n) => n['status'] == 'paid').toList();
        final annulees = notes.where((n) => n['status'] == 'cancelled').toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          FilledButton.icon(
            onPressed: () => _ouvrirTable(context),
            icon: const Icon(Icons.add),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            label: const Text('Ouvrir une table'),
          ),
          if (snap.hasData && notes.isEmpty) const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Vide('Aucune table ouverte ce soir.', icone: Icons.table_restaurant),
          ),
          if (enCours.isNotEmpty)
          TitreSection('En cours · ${enCours.length}',
              droite: Text(fcfa(enCours.fold<int>(0, (s, n) => s + entier(n['total']))),
                  style: const TextStyle(color: HC.gris))),
          for (final n in enCours) _ligne(context, n),
          if (payees.isNotEmpty) ...[
            TitreSection('Encaissées · ${payees.length}',
                droite: Text(fcfa(payees.fold<int>(0, (s, n) => s + entier(n['total']))),
                    style: const TextStyle(color: HC.vert, fontWeight: FontWeight.w700))),
            for (final n in payees) _ligne(context, n),
          ],
          if (annulees.isNotEmpty) ...[
            TitreSection('Annulées · ${annulees.length}'),
            for (final n in annulees) _ligne(context, n),
          ],
        ]);
      },
    );
  }

  Widget _ligne(BuildContext context, Map<String, dynamic> n) {
    final etat = n['status'] as String?;
    final attente = entier(n['en_attente']);
    final (String libelle, Color couleur, Color fond) = switch (etat) {
      'to_pay' => ('À encaisser', HC.or, HC.fondOr),
      'paid' => ('Encaissée${n['ticket_number'] != null ? ' · n° ${n['ticket_number']}' : ''}', HC.vert, HC.fondVert),
      'cancelled' => ('Annulée', HC.rouge, HC.fondRouge),
      _ => ('En cours', HC.bleu, HC.fondBleu),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          title: Text('${n['table_name'] ?? 'Table'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${n['waitress_name'] ?? ''}'),
              Pastille(libelle, couleur: couleur, fond: fond),
              if (attente > 0) Pastille('$attente au bar', couleur: HC.bleu, fond: HC.fondBleu),
            ]),
          ),
          trailing: Text(fcfa(entier(n['total'])), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => NoteGestion(membre: membre, tabId: n['id'] as String))),
        ),
      ),
    );
  }
}

/// Détail d'une note pour le gérant et le patron.
class NoteGestion extends StatelessWidget {
  const NoteGestion({super.key, required this.membre, required this.tabId});
  final Membre membre;
  final String tabId;

  static String _etat(String? s) => switch (s) {
        'requested' => 'En attente du bar',
        'served' => 'Servie',
        'refused' => 'Refusée',
        'removed' => 'Retirée',
        _ => '',
      };

  Future<void> _retirer(BuildContext context, Map<String, dynamic> i) async {
    var remettre = false;
    final raison = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Retirer ${i['quantity']} × ${i['product_name']}'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, children: [
                for (final s in const ['Bouteille cassée', 'Erreur de commande', 'Client a refusé'])
                  ActionChip(label: Text(s), onPressed: () => set(() => raison.text = s)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: raison, decoration: const InputDecoration(labelText: 'Raison')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: remettre,
                onChanged: (v) => set(() => remettre = v ?? false),
                title: const Text('La boisson revient en stock (pas ouverte)'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await tenter(context,
          () => Club.retirerBoisson(membre, i['id'] as String, raison.text, remettreEnStock: remettre),
          succes: 'Boisson retirée de la note.');
    }
  }

  Future<void> _annuler(BuildContext context, String etat) async {
    final raison = await demanderTexte(context, 'Annuler toute la note ?',
        label: 'Raison', bouton: 'Annuler la note',
        suggestions: const ['Table ouverte par erreur', 'Client parti sans consommer']);
    if (raison == null || raison.isEmpty || !context.mounted) return;
    await tenter(context, () => Club.annulerNote(membre, tabId, raison), succes: 'Note annulée.');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: Requetes.note(tabId),
      builder: (context, noteSnap) {
        final note = (noteSnap.data ?? const []).firstOrNull;
        if (note == null) return Scaffold(appBar: AppBar());
        final etat = '${note['status']}';
        final nomTable = '${note['table_name'] ?? 'Table'}';
        return Scaffold(
          appBar: AppBar(
            title: Text('$nomTable · ${note['waitress_name'] ?? ''}'),
            actions: [
              IconButton(
                tooltip: 'Envoyer par WhatsApp',
                icon: const Icon(Icons.chat, color: HC.vert),
                onPressed: () => Recu.envoyerWhatsApp(context, tabId),
              ),
              IconButton(
                tooltip: 'Imprimer',
                icon: const Icon(Icons.print),
                onPressed: () => tenter(context, () => Recu.imprimer(context, tabId)),
              ),
              if (etat == 'open' || etat == 'to_pay' || (etat == 'paid' && membre.estPatron))
                IconButton(
                  tooltip: 'Annuler la note',
                  icon: const Icon(Icons.delete_outline, color: HC.rouge),
                  onPressed: () => _annuler(context, etat),
                ),
            ],
          ),
          body: StreamBuilder<Lignes>(
            stream: Requetes.boissonsDeLaNote(tabId),
            builder: (context, snap) {
              final items = snap.data ?? const [];
              final attente = items.where((i) => i['status'] == 'requested').length;
              return Column(children: [
                Expanded(
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    for (final i in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Text('${i['quantity']} ×',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: HC.or)),
                        title: Text('${i['product_name']}',
                            style: TextStyle(
                                decoration: i['status'] == 'served' || i['status'] == 'requested'
                                    ? null
                                    : TextDecoration.lineThrough)),
                        subtitle: Text([
                          _etat(i['status'] as String?),
                          if (i['removed_reason'] != null) '${i['removed_reason']}',
                        ].join(' · ')),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(fcfa(entier(i['quantity']) * entier(i['unit_price']))),
                          if (i['status'] == 'served' && (etat == 'open' || etat == 'to_pay'))
                            IconButton(
                              tooltip: 'Retirer de la note',
                              icon: const Icon(Icons.remove_circle_outline, color: HC.rouge),
                              onPressed: () => _retirer(context, i),
                            ),
                          if (i['status'] == 'requested')
                            IconButton(
                              tooltip: 'Servi',
                              icon: const Icon(Icons.check_circle_outline, color: HC.vert),
                              onPressed: () => tenter(context, () => Club.servir(membre, [i['id'] as String])),
                            ),
                        ]),
                      ),
                  ]),
                ),
                Container(
                  decoration: const BoxDecoration(color: HC.surface, border: Border(top: BorderSide(color: HC.bordure))),
                  padding: const EdgeInsets.all(16),
                  child: SafeArea(
                    top: false,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        const Text('Total servi', style: TextStyle(color: HC.gris, fontSize: 16)),
                        const Spacer(),
                        if (entier(note['paid_amount']) > 0)
                          Text('payé ${fcfa(entier(note['paid_amount']))}   ', style: const TextStyle(color: HC.vert)),
                        Text(fcfa(entier(note['total'])),
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: HC.or)),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
                        if (etat == 'open')
                          OutlinedButton.icon(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => Commande(membre: membre, tabId: tabId, nomTable: nomTable))),
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter des boissons'),
                          ),
                        if (etat == 'open')
                          FilledButton.icon(
                            onPressed: attente > 0 || entier(note['total']) == 0
                                ? null
                                : () async {
                                    if (await tenter(context, () => Club.demanderEncaissement(tabId)) && context.mounted) {
                                      await encaisserNote(context, membre, tabId);
                                    }
                                  },
                            icon: const Icon(Icons.point_of_sale),
                            label: const Text('Encaisser'),
                          ),
                        if (etat == 'to_pay') ...[
                          OutlinedButton(
                            onPressed: () => tenter(context, () => Club.rouvrirNote(tabId)),
                            child: const Text('Rouvrir (le client recommande)'),
                          ),
                          FilledButton.icon(
                            onPressed: () => encaisserNote(context, membre, tabId),
                            icon: const Icon(Icons.point_of_sale),
                            label: const Text('Encaisser'),
                          ),
                        ],
                      ]),
                    ]),
                  ),
                ),
              ]);
            },
          ),
        );
      },
    );
  }
}
