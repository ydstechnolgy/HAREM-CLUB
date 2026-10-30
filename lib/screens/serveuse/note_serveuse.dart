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

/// La note d'une table, vue par la serveuse.
class NoteServeuse extends StatelessWidget {
  const NoteServeuse({super.key, required this.membre, required this.tabId});
  final Membre membre;
  final String tabId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: Requetes.note(tabId),
      builder: (context, noteSnap) {
        final note = (noteSnap.data ?? const []).firstOrNull;
        if (note == null) {
          return Scaffold(
            appBar: AppBar(),
            body: noteSnap.hasData ? const Vide('Cette note n\'existe plus.') : const SizedBox.shrink(),
          );
        }
        final nomTable = '${note['table_name'] ?? 'Table'}';
        final etat = note['status'] as String?;
        return Scaffold(
          appBar: AppBar(title: Text(nomTable)),
          body: StreamBuilder<Lignes>(
            stream: Requetes.boissonsDeLaNote(tabId),
            builder: (context, snap) {
              final items = snap.data ?? const [];
              final attente = items.where((i) => i['status'] == 'requested').toList();
              final servies = items.where((i) => i['status'] == 'served').toList();
              final refusees = items.where((i) => i['status'] == 'refused').toList();
              final total = servies.fold<int>(0, (s, i) => s + entier(i['quantity']) * entier(i['unit_price']));
              return Column(children: [
                if (etat == 'to_pay') _Bandeau(
                    couleur: HC.or, fond: HC.fondOr, icone: Icons.payments,
                    texte: 'Envoyée au gérant : ${fcfa(entier(note['total']))} à encaisser.'),
                if (etat == 'paid') _Bandeau(
                    couleur: HC.vert, fond: HC.fondVert, icone: Icons.check_circle,
                    texte: 'Encaissée${note['ticket_number'] != null ? ' · reçu n° ${note['ticket_number']}' : ''}.'),
                if (etat == 'cancelled') const _Bandeau(
                    couleur: HC.rouge, fond: HC.fondRouge, icone: Icons.block, texte: 'Note annulée.'),
                Expanded(
                  child: items.isEmpty
                      ? const Vide('Aucune boisson.\nAppuyez sur « Ajouter des boissons ».', icone: Icons.local_bar)
                      : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                          if (attente.isNotEmpty) const TitreSection('En attente du bar'),
                          for (final i in attente)
                            _LigneBoisson(
                              item: i,
                              couleur: HC.bleu,
                              action: etat == 'open'
                                  ? IconButton(
                                      tooltip: 'Annuler cette boisson',
                                      icon: const Icon(Icons.close, color: HC.rouge),
                                      onPressed: () async {
                                        final ok = await confirmer(context, 'Annuler cette boisson ?',
                                            '${i['quantity']} × ${i['product_name']} ne sera pas servi.',
                                            bouton: 'Annuler la boisson', danger: true);
                                        if (ok && context.mounted) {
                                          await tenter(context, () => Club.annulerDemande(i['id'] as String));
                                        }
                                      },
                                    )
                                  : null,
                            ),
                          if (servies.isNotEmpty) const TitreSection('Servies'),
                          for (final i in servies) _LigneBoisson(item: i, couleur: HC.vert),
                          if (refusees.isNotEmpty) const TitreSection('Refusées par le bar'),
                          for (final i in refusees) _LigneBoisson(item: i, couleur: HC.rouge, barre: true),
                        ]),
                ),
                _Pied(
                  membre: membre,
                  tabId: tabId,
                  nomTable: nomTable,
                  etat: etat,
                  total: total,
                  enAttente: attente.length,
                ),
              ]);
            },
          ),
        );
      },
    );
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({required this.couleur, required this.fond, required this.icone, required this.texte});
  final Color couleur;
  final Color fond;
  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: fond,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(icone, color: couleur),
        const SizedBox(width: 10),
        Expanded(child: Text(texte, style: TextStyle(color: couleur, fontWeight: FontWeight.w700, fontSize: 15))),
      ]),
    );
  }
}

class _LigneBoisson extends StatelessWidget {
  const _LigneBoisson({required this.item, required this.couleur, this.action, this.barre = false});
  final Map<String, dynamic> item;
  final Color couleur;
  final Widget? action;
  final bool barre;

  @override
  Widget build(BuildContext context) {
    final q = entier(item['quantity']);
    final prix = entier(item['unit_price']);
    final style = TextStyle(
      fontSize: 16,
      decoration: barre ? TextDecoration.lineThrough : null,
      color: barre ? HC.gris : HC.texte,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(width: 4, height: 34, decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Text('$q ×', style: style.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item['product_name']}', style: style),
            if (barre && item['removed_reason'] != null)
              Text('${item['removed_reason']}', style: const TextStyle(color: HC.rouge, fontSize: 12.5)),
          ]),
        ),
        Text(fcfa(q * prix), style: style.copyWith(color: barre ? HC.gris : HC.gris)),
        ?action,
      ]),
    );
  }
}

class _Pied extends StatelessWidget {
  const _Pied({
    required this.membre,
    required this.tabId,
    required this.nomTable,
    required this.etat,
    required this.total,
    required this.enAttente,
  });
  final Membre membre;
  final String tabId;
  final String nomTable;
  final String? etat;
  final int total;
  final int enAttente;

  Future<void> _encaisser(BuildContext context) async {
    try {
      final montant = await Club.demanderEncaissement(tabId);
      if (context.mounted) await _annoncer(context, montant);
    } catch (e) {
      if (context.mounted) erreur(context, e);
    }
  }

  /// Grand affichage du montant à annoncer au client.
  Future<void> _annoncer(BuildContext context, int montant) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: HC.fond,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Spacer(),
              Text(nomTable, style: const TextStyle(fontSize: 22, color: HC.gris)),
              const SizedBox(height: 12),
              const Text('À payer', style: TextStyle(fontSize: 18, color: HC.gris)),
              FittedBox(
                child: Text(fcfa(montant),
                    style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: HC.or)),
              ),
              const SizedBox(height: 16),
              const Text('Annoncez ce montant au client, puis remettez l\'argent au gérant.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Compris'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: HC.surface,
        border: Border(top: BorderSide(color: HC.bordure)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('Total servi', style: TextStyle(fontSize: 16, color: HC.gris)),
              const Spacer(),
              Text(fcfa(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: HC.or)),
            ]),
            const SizedBox(height: 12),
            if (etat == 'open')
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => Commande(membre: membre, tabId: tabId, nomTable: nomTable))),
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter des boissons'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: total == 0 || enAttente > 0 ? null : () => _encaisser(context),
                    icon: const Icon(Icons.payments),
                    label: Text(enAttente > 0 ? 'Attente du bar' : 'Encaisser'),
                  ),
                ),
              ]),
            if (etat == 'paid')
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54), foregroundColor: HC.vert),
                onPressed: () => Recu.envoyerWhatsApp(context, tabId),
                icon: const Icon(Icons.chat),
                label: const Text('Envoyer le reçu par WhatsApp'),
              ),
            if (etat == 'to_pay')
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: () => tenter(context, () => Club.rouvrirNote(tabId)),
                    icon: const Icon(Icons.replay),
                    label: const Text('Le client recommande'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    onPressed: () => _annoncer(context, total),
                    icon: const Icon(Icons.campaign),
                    label: const Text('Revoir le montant'),
                  ),
                ),
              ]),
          ]),
        ),
      ),
    );
  }
}
