import 'package:flutter/material.dart';

import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../theme/harem_theme.dart';
import '../../utils/format.dart';
import '../../widgets/commun.dart';
import '../../widgets/etat_synchro.dart';
import 'choix_table.dart';
import 'note_serveuse.dart';

/// Accueil de la serveuse : ses tables de la soirée.
class AccueilServeuse extends StatelessWidget {
  const AccueilServeuse({super.key, required this.membre});
  final Membre membre;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: Requetes.soireeOuverte(),
      builder: (context, soireeSnap) {
        final soireeOuverte = (soireeSnap.data ?? const []).isNotEmpty;
        return Scaffold(
          appBar: AppBar(
            title: Text('Bonsoir ${membre.nom}'),
            actions: [
              const EtatSynchro(),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'deconnexion') deconnexion(context);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'deconnexion', child: Text('Se déconnecter')),
                ],
              ),
            ],
          ),
          floatingActionButton: soireeOuverte
              ? FloatingActionButton.extended(
                  onPressed: () => _ouvrirTable(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Ouvrir une table', style: TextStyle(fontWeight: FontWeight.w700)),
                )
              : null,
          body: Column(
            children: [
              const BandeauRefus(),
              Expanded(
                child: !soireeSnap.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : !soireeOuverte
                        ? const Vide('La soirée n\'est pas encore ouverte.\n'
                            'Le gérant doit l\'ouvrir sur le PC du bar.', icone: Icons.nightlife)
                        : _MesTables(membre: membre),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _ouvrirTable(BuildContext context) async {
    final tabId = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => ChoixTable(membre: membre)));
    if (tabId != null && context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => NoteServeuse(membre: membre, tabId: tabId)));
    }
  }
}

class _MesTables extends StatelessWidget {
  const _MesTables({required this.membre});
  final Membre membre;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: Requetes.notesDeLaSoiree(serveuseId: membre.id),
      builder: (context, snap) {
        final notes = snap.data ?? const [];
        final enCours = notes.where((n) => n['status'] == 'open' || n['status'] == 'to_pay').toList();
        final payees = notes.where((n) => n['status'] == 'paid').toList();
        final totalPaye = payees.fold<int>(0, (s, n) => s + entier(n['total']));
        if (enCours.isEmpty && payees.isEmpty) {
          return const Vide('Aucune table pour l\'instant.\nAppuyez sur « Ouvrir une table ».',
              icone: Icons.table_restaurant_outlined);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (enCours.isNotEmpty) const TitreSection('Mes tables en cours'),
            for (final n in enCours) ...[
              _CarteNote(note: n, membre: membre),
              const SizedBox(height: 10),
            ],
            if (payees.isNotEmpty) ...[
              TitreSection('Encaissées ce soir · ${payees.length}', droite: Text(fcfa(totalPaye),
                  style: const TextStyle(color: HC.gris, fontWeight: FontWeight.w600))),
              for (final n in payees)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, color: HC.vert),
                  title: Text('${n['table_name'] ?? 'Table'}'),
                  trailing: Text(fcfa(entier(n['total'])), style: const TextStyle(color: HC.gris)),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NoteServeuse(membre: membre, tabId: n['id'] as String))),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _CarteNote extends StatelessWidget {
  const _CarteNote({required this.note, required this.membre});
  final Map<String, dynamic> note;
  final Membre membre;

  @override
  Widget build(BuildContext context) {
    final aPayer = note['status'] == 'to_pay';
    final attente = entier(note['en_attente']);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: aPayer ? HC.or : HC.bordure, width: aPayer ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => NoteServeuse(membre: membre, tabId: note['id'] as String))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${note['table_name'] ?? 'Table'}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (aPayer) const Pastille('Envoyée au gérant'),
                  if (attente > 0)
                    Pastille('$attente en attente du bar', couleur: HC.bleu, fond: HC.fondBleu),
                ]),
              ]),
            ),
            Text(fcfa(entier(note['total'])),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: HC.or)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: HC.gris),
          ]),
        ),
      ),
    );
  }
}
