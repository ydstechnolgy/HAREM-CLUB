import 'package:flutter/material.dart';

import '../../data/actions.dart';
import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../theme/harem_theme.dart';
import '../../widgets/commun.dart';

/// Stock des boissons : entrées, pertes, inventaire.
class StockPage extends StatefulWidget {
  const StockPage({super.key, required this.membre});
  final Membre membre;

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String _recherche = '';
  bool _basSeulement = false;

  static Stream<Lignes> _stock() => db.watch(
        'SELECT p.id, p.name, p.min_stock, c.name AS category_name, COALESCE(s.q, 0) AS quantite '
        'FROM products p LEFT JOIN categories c ON c.id = p.category_id '
        'LEFT JOIN (SELECT product_id, SUM(quantity) AS q FROM stock_movements GROUP BY product_id) s ON s.product_id = p.id '
        'WHERE p.active = 1 AND p.track_stock = 1 '
        'ORDER BY c.sort_order, p.sort_order, p.name',
      );

  Future<void> _entree(Map<String, dynamic> p) async {
    final q = TextEditingController();
    final prix = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Arrivée de stock · ${p['name']}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ChampNombre(controller: q, label: 'Nombre reçu', autofocus: true),
            const SizedBox(height: 12),
            ChampNombre(controller: prix, label: 'Prix d\'achat par unité (facultatif)', suffixe: 'FCFA'),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Fournisseur ou remarque (facultatif)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await tenter(
        context,
        () => Club.entreeStock(widget.membre, p['id'] as String, lireNombre(q),
            prixAchat: lireNombre(prix), note: note.text.trim().isEmpty ? null : note.text.trim()),
        succes: 'Stock mis à jour.',
      );
    }
  }

  Future<void> _perte(Map<String, dynamic> p) async {
    final q = TextEditingController();
    final raison = TextEditingController();
    var type = 'loss';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Correction · ${p['name']}'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'loss', label: Text('Perte, casse')),
                  ButtonSegment(value: 'adjustment', label: Text('Correction')),
                ],
                selected: {type},
                onSelectionChanged: (s) => set(() => type = s.first),
              ),
              const SizedBox(height: 12),
              ChampNombre(
                controller: q,
                negatif: type == 'adjustment',
                label: type == 'loss' ? 'Nombre perdu' : 'Nombre à ajouter (ou à retirer avec un -)',
              ),
              const SizedBox(height: 12),
              TextField(controller: raison, decoration: const InputDecoration(labelText: 'Raison')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      await tenter(context, () => Club.ajusterStock(widget.membre, p['id'] as String, lireNombre(q), type, raison.text),
          succes: 'Stock corrigé.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: _stock(),
      builder: (context, snap) {
        final tous = snap.data ?? const [];
        final bas = tous.where((p) => entier(p['quantite']) <= entier(p['min_stock'])).length;
        final liste = tous.where((p) {
          if (_basSeulement && entier(p['quantite']) > entier(p['min_stock'])) return false;
          return _recherche.isEmpty || '${p['name']}'.toLowerCase().contains(_recherche);
        }).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(hintText: 'Rechercher', prefixIcon: Icon(Icons.search), isDense: true),
                  onChanged: (v) => setState(() => _recherche = v.trim().toLowerCase()),
                ),
              ),
              FilterChip(
                label: Text('Stock bas · $bas'),
                selected: _basSeulement,
                onSelected: (v) => setState(() => _basSeulement = v),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => _Inventaire(membre: widget.membre, produits: tous))),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Faire l\'inventaire'),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: liste.length,
              itemBuilder: (context, i) {
                final p = liste[i];
                final q = entier(p['quantite']);
                final faible = q <= entier(p['min_stock']);
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    title: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${p['category_name'] ?? ''}${entier(p['min_stock']) > 0 ? ' · minimum ${p['min_stock']}' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$q', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: faible ? HC.rouge : HC.texte)),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                          tooltip: 'Arrivée de stock', onPressed: () => _entree(p), icon: const Icon(Icons.add)),
                      IconButton(
                          tooltip: 'Perte ou correction', onPressed: () => _perte(p), icon: const Icon(Icons.edit_outlined)),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

/// Comptage de toutes les bouteilles : le logiciel corrige les écarts.
class _Inventaire extends StatefulWidget {
  const _Inventaire({required this.membre, required this.produits});
  final Membre membre;
  final List<Map<String, dynamic>> produits;

  @override
  State<_Inventaire> createState() => _InventaireState();
}

class _InventaireState extends State<_Inventaire> {
  final Map<String, TextEditingController> _champs = {};

  @override
  void dispose() {
    for (final c in _champs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _champ(String id) => _champs.putIfAbsent(id, TextEditingController.new);

  Future<void> _valider() async {
    final comptes = <String, int>{
      for (final e in _champs.entries)
        if (e.value.text.trim().isNotEmpty) e.key: int.tryParse(e.value.text.trim()) ?? 0
    };
    if (comptes.isEmpty) return erreur(context, Exception('Saisissez au moins une quantité comptée.'));
    final ok = await confirmer(context, 'Valider l\'inventaire ?',
        '${comptes.length} boisson${comptes.length > 1 ? 's' : ''} comptée${comptes.length > 1 ? 's' : ''}. '
            'Le stock sera remplacé par vos comptages.',
        bouton: 'Valider');
    if (!ok || !mounted) return;
    try {
      final ecarts = await Club.inventaire(widget.membre, comptes);
      if (!mounted) return;
      info(context, ecarts == 0 ? 'Inventaire validé : aucun écart.' : 'Inventaire validé : $ecarts écart${ecarts > 1 ? 's' : ''} corrigé${ecarts > 1 ? 's' : ''}.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) erreur(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventaire')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Comptez chaque boisson et saisissez le nombre trouvé. Laissez vide ce que vous n\'avez pas compté.',
            style: TextStyle(color: HC.gris)),
        const SizedBox(height: 12),
        for (final p in widget.produits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Dans le logiciel : ${entier(p['quantite'])}', style: const TextStyle(color: HC.gris, fontSize: 12.5)),
                ]),
              ),
              SizedBox(width: 120, child: ChampNombre(controller: _champ(p['id'] as String), label: 'Compté')),
            ]),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(onPressed: _valider, icon: const Icon(Icons.check), label: const Text('Valider l\'inventaire')),
        ),
      ),
    );
  }
}
