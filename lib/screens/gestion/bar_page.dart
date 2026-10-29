import 'package:flutter/material.dart';

import '../../data/actions.dart';
import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../theme/harem_theme.dart';
import '../../utils/format.dart';
import '../../widgets/commun.dart';

/// Demandes des serveuses : le gérant donne les boissons et clique « Servi ».
class BarPage extends StatelessWidget {
  const BarPage({super.key, required this.membre});
  final Membre membre;

  static Stream<Lignes> _demandes() => db.watch(
        'SELECT i.*, t.table_id, ct.name AS table_name, m.display_name AS waitress_name, '
        'COALESCE(s.q, 0) AS stock, p.track_stock '
        'FROM tab_items i JOIN tabs t ON t.id = i.tab_id '
        'LEFT JOIN club_tables ct ON ct.id = t.table_id '
        'LEFT JOIN members m ON m.id = t.waitress_id '
        'LEFT JOIN products p ON p.id = i.product_id '
        'LEFT JOIN (SELECT product_id, SUM(quantity) AS q FROM stock_movements GROUP BY product_id) s '
        '  ON s.product_id = i.product_id '
        "WHERE i.status = 'requested' AND t.status = 'open' "
        'ORDER BY i.requested_at',
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: _demandes(),
      builder: (context, snap) {
        final demandes = snap.data ?? const [];
        if (snap.hasData && demandes.isEmpty) {
          return const Vide('Aucune demande en attente.\nLes commandes des serveuses s\'affichent ici.',
              icone: Icons.local_bar);
        }
        // Une carte par note, dans l'ordre d'arrivée de la première demande.
        final parNote = <String, List<Map<String, dynamic>>>{};
        for (final d in demandes) {
          parNote.putIfAbsent(d['tab_id'] as String, () => []).add(d);
        }
        return LayoutBuilder(builder: (context, c) {
          final colonnes = (c.maxWidth / 420).floor().clamp(1, 4);
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: colonnes,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 300,
            ),
            itemCount: parNote.length,
            itemBuilder: (context, i) {
              final lignes = parNote.values.elementAt(i);
              return _CarteDemande(membre: membre, lignes: lignes);
            },
          );
        });
      },
    );
  }
}

class _CarteDemande extends StatelessWidget {
  const _CarteDemande({required this.membre, required this.lignes});
  final Membre membre;
  final List<Map<String, dynamic>> lignes;

  @override
  Widget build(BuildContext context) {
    final premiere = lignes.first;
    final heure = DateTime.tryParse('${premiere['requested_at']}')?.toLocal();
    final montant = lignes.fold<int>(0, (s, l) => s + entier(l['quantity']) * entier(l['unit_price']));
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: const BorderSide(color: HC.bleu, width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('${premiere['table_name'] ?? 'Table'}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (heure != null)
              Text('${heure.hour.toString().padLeft(2, '0')}h${heure.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: HC.gris)),
          ]),
          Text('Serveuse : ${premiere['waitress_name'] ?? ''}', style: const TextStyle(color: HC.gris)),
          const Divider(height: 18),
          Expanded(
            child: ListView(children: [
              for (final l in lignes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Text('${l['quantity']} ×',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: HC.or)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${l['product_name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        if (ouiNon(l['track_stock']) && entier(l['stock']) < entier(l['quantity']))
                          Text('Stock affiché : ${entier(l['stock'])}',
                              style: const TextStyle(color: HC.rouge, fontSize: 12)),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Plus',
                      icon: const Icon(Icons.more_vert, color: HC.gris),
                      onSelected: (v) async {
                        final id = l['id'] as String;
                        if (v == 'servi') {
                          await tenter(context, () => Club.servir(membre, [id]));
                        } else {
                          final raison = await demanderTexte(context, 'Refuser ${l['product_name']}',
                              label: 'Raison', initial: 'Rupture de stock',
                              suggestions: const ['Rupture de stock', 'Erreur de commande']);
                          if (raison != null && context.mounted) {
                            await tenter(context, () => Club.refuser(membre, [id], raison.isEmpty ? 'Rupture de stock' : raison));
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'servi', child: Text('Servi (cette boisson seulement)')),
                        PopupMenuItem(value: 'refus', child: Text('Refuser (rupture…)')),
                      ],
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: HC.vert, minimumSize: const Size.fromHeight(50)),
            onPressed: () => tenter(context, () => Club.servir(membre, [for (final l in lignes) l['id'] as String])),
            icon: const Icon(Icons.check),
            label: Text('Servi · ${fcfa(montant)}'),
          ),
        ]),
      ),
    );
  }
}
