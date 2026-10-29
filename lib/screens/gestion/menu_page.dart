import 'package:flutter/material.dart';

import '../../data/actions.dart';
import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../theme/harem_theme.dart';
import '../../utils/format.dart';
import '../../widgets/commun.dart';
import '../serveuse/choix_table.dart';

/// Menu (boissons, prix, catégories) et tables du club.
class MenuPage extends StatelessWidget {
  const MenuPage({super.key, required this.membre});
  final Membre membre;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: HC.or,
          labelColor: HC.or,
          unselectedLabelColor: HC.gris,
          tabs: [Tab(text: 'Boissons et prix'), Tab(text: 'Catégories'), Tab(text: 'Tables')],
        ),
        Expanded(
          child: TabBarView(children: [
            _Boissons(membre: membre),
            const _Categories(),
            _Tables(membre: membre),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Boissons

class _Boissons extends StatefulWidget {
  const _Boissons({required this.membre});
  final Membre membre;

  @override
  State<_Boissons> createState() => _BoissonsState();
}

class _BoissonsState extends State<_Boissons> {
  String _recherche = '';

  Future<void> _fiche({Map<String, dynamic>? p}) async {
    final cats = await db.getAll('SELECT id, name FROM categories ORDER BY sort_order, name');
    if (!mounted) return;
    if (cats.isEmpty) return erreur(context, Exception('Créez d\'abord une catégorie.'));
    final nom = TextEditingController(text: '${p?['name'] ?? ''}');
    final prix = TextEditingController(text: p == null ? '' : '${entier(p['sale_price'])}');
    final mini = TextEditingController(text: p == null ? '' : '${entier(p['min_stock'])}');
    var categorie = (p?['category_id'] as String?) ?? cats.first['id'] as String;
    var suivi = p == null ? true : ouiNon(p['track_stock']);
    var actif = p == null ? true : ouiNon(p['active']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(p == null ? 'Nouvelle boisson' : 'Modifier la boisson'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nom')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: categorie,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: [
                    for (final c in cats) DropdownMenuItem(value: c['id'] as String, child: Text('${c['name']}')),
                  ],
                  onChanged: (v) => set(() => categorie = v ?? categorie),
                ),
                const SizedBox(height: 12),
                ChampNombre(controller: prix, label: 'Prix de vente', suffixe: 'FCFA'),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: suivi,
                  onChanged: (v) => set(() => suivi = v),
                  title: const Text('Suivre le stock'),
                  subtitle: const Text('Désactivez pour les cocktails et le café.'),
                ),
                if (suivi) ChampNombre(controller: mini, label: 'Alerte quand le stock descend à'),
                if (p != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: actif,
                    onChanged: (v) => set(() => actif = v),
                    title: const Text('Au menu'),
                    subtitle: const Text('Désactivez pour la retirer du menu des serveuses.'),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await tenter(context, () async {
      if (nom.text.trim().isEmpty) throw Exception('Donnez un nom à la boisson.');
      if (prix.text.trim().isEmpty) throw Exception('Indiquez le prix de vente.');
      if (p == null) {
        final ordre = await db.get('SELECT COALESCE(MAX(sort_order), 0) + 1 AS o FROM products WHERE category_id = ?', [categorie]);
        await db.execute(
          'INSERT INTO products (id, category_id, name, sale_price, track_stock, min_stock, active, sort_order, created_at, updated_at) '
          'VALUES (uuid(), ?, ?, ?, ?, ?, 1, ?, ?, ?)',
          [categorie, nom.text.trim(), lireNombre(prix), suivi ? 1 : 0, lireNombre(mini), entier(ordre['o']),
           maintenantIso(), maintenantIso()],
        );
      } else {
        await db.execute(
          'UPDATE products SET category_id = ?, name = ?, sale_price = ?, track_stock = ?, min_stock = ?, active = ? WHERE id = ?',
          [categorie, nom.text.trim(), lireNombre(prix), suivi ? 1 : 0, lireNombre(mini), actif ? 1 : 0, p['id']],
        );
      }
    }, succes: 'Menu mis à jour.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _fiche(),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle boisson'),
      ),
      body: StreamBuilder<Lignes>(
        stream: Requetes.boissons(toutes: true),
        builder: (context, snap) {
          final liste = (snap.data ?? const [])
              .where((p) => _recherche.isEmpty || '${p['name']}'.toLowerCase().contains(_recherche))
              .toList();
          String? derniere;
          final enfants = <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                decoration: const InputDecoration(hintText: 'Rechercher', prefixIcon: Icon(Icons.search), isDense: true),
                onChanged: (v) => setState(() => _recherche = v.trim().toLowerCase()),
              ),
            ),
          ];
          for (final p in liste) {
            final cat = '${p['category_name'] ?? 'Sans catégorie'}';
            if (cat != derniere) {
              enfants.add(TitreSection(cat));
              derniere = cat;
            }
            final actif = ouiNon(p['active']);
            enfants.add(Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                title: Text('${p['name']}',
                    style: TextStyle(fontWeight: FontWeight.w700, color: actif ? HC.texte : HC.gris)),
                subtitle: Text([
                  if (!ouiNon(p['track_stock'])) 'sans suivi de stock',
                  if (!actif) 'retirée du menu',
                ].join(' · ')),
                trailing: Text(fcfa(entier(p['sale_price'])),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: HC.or)),
                onTap: () => _fiche(p: p),
              ),
            ));
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: enfants);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Catégories

class _Categories extends StatelessWidget {
  const _Categories();

  Future<void> _nouvelle(BuildContext context) async {
    final nom = await demanderTexte(context, 'Nouvelle catégorie', label: 'Nom', bouton: 'Créer');
    if (nom == null || nom.isEmpty || !context.mounted) return;
    await tenter(context, () async {
      final ordre = await db.get('SELECT COALESCE(MAX(sort_order), 0) + 1 AS o FROM categories');
      await db.execute('INSERT INTO categories (id, name, sort_order, created_at) VALUES (uuid(), ?, ?, ?)',
          [nom, entier(ordre['o']), maintenantIso()]);
    });
  }

  Future<void> _renommer(BuildContext context, Map<String, dynamic> c) async {
    final nom = await demanderTexte(context, 'Renommer la catégorie', initial: '${c['name']}', label: 'Nom');
    if (nom == null || nom.isEmpty || !context.mounted) return;
    await tenter(context, () => db.execute('UPDATE categories SET name = ? WHERE id = ?', [nom, c['id']]));
  }

  Future<void> _deplacer(Lignes cats, int i, int sens) async {
    final j = i + sens;
    if (j < 0 || j >= cats.length) return;
    await db.writeTransaction((tx) async {
      await tx.execute('UPDATE categories SET sort_order = ? WHERE id = ?', [j, cats[i]['id']]);
      await tx.execute('UPDATE categories SET sort_order = ? WHERE id = ?', [i, cats[j]['id']]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nouvelle(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle catégorie'),
      ),
      body: StreamBuilder<Lignes>(
        stream: Requetes.categories(),
        builder: (context, snap) {
          final cats = snap.data ?? const [];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
            const Text('L\'ordre des catégories est celui du menu des serveuses.', style: TextStyle(color: HC.gris)),
            const SizedBox(height: 8),
            for (var i = 0; i < cats.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  title: Text('${cats[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => _renommer(context, cats[i]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(onPressed: () => _deplacer(cats, i, -1), icon: const Icon(Icons.arrow_upward)),
                    IconButton(onPressed: () => _deplacer(cats, i, 1), icon: const Icon(Icons.arrow_downward)),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Tables

class _Tables extends StatelessWidget {
  const _Tables({required this.membre});
  final Membre membre;

  Future<void> _nouvelle(BuildContext context) async {
    final nom = TextEditingController();
    var zone = 'salle';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nouvelle table fixe'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nom, autofocus: true, decoration: const InputDecoration(labelText: 'Nom (ex. Table 11)')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: zone,
                decoration: const InputDecoration(labelText: 'Espace'),
                items: const [
                  DropdownMenuItem(value: 'salle', child: Text('Salle')),
                  DropdownMenuItem(value: 'vip', child: Text('VIP')),
                  DropdownMenuItem(value: 'terrasse', child: Text('Terrasse')),
                  DropdownMenuItem(value: 'comptoir', child: Text('Comptoir')),
                ],
                onChanged: (v) => set(() => zone = v ?? 'salle'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Créer')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await tenter(context, () => Club.creerTable(membre, nom.text, zone: zone, fixe: true), succes: 'Table créée.');
    }
  }

  Future<void> _modifier(BuildContext context, Map<String, dynamic> t) async {
    final actif = ouiNon(t['active']);
    final choix = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('${t['name']}'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'renommer'), child: const Text('Renommer')),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'actif'),
            child: Text(actif ? 'Retirer (ne plus proposer cette table)' : 'Remettre en service'),
          ),
        ],
      ),
    );
    if (!context.mounted || choix == null) return;
    if (choix == 'renommer') {
      final nom = await demanderTexte(context, 'Renommer la table', initial: '${t['name']}', label: 'Nom');
      if (nom == null || nom.isEmpty || !context.mounted) return;
      await tenter(context, () => db.execute('UPDATE club_tables SET name = ? WHERE id = ?', [nom, t['id']]));
    } else {
      await tenter(context, () => db.execute('UPDATE club_tables SET active = ? WHERE id = ?', [actif ? 0 : 1, t['id']]));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nouvelle(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle table'),
      ),
      body: StreamBuilder<Lignes>(
        stream: db.watch(
          "SELECT * FROM club_tables ORDER BY active DESC, CASE zone WHEN 'salle' THEN 0 WHEN 'vip' THEN 1 "
          "WHEN 'terrasse' THEN 2 ELSE 3 END, sort_order, name",
        ),
        builder: (context, snap) {
          final tables = snap.data ?? const [];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
            const Text('Les tables créées par les serveuses pendant la soirée sont marquées « provisoire ».',
                style: TextStyle(color: HC.gris)),
            const SizedBox(height: 8),
            for (final t in tables)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  title: Text('${t['name']}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: ouiNon(t['active']) ? HC.texte : HC.gris)),
                  subtitle: Text([
                    ChoixTable.nomZone(t['zone'] as String?),
                    if (!ouiNon(t['is_fixed'])) 'provisoire',
                    if (!ouiNon(t['active'])) 'retirée',
                  ].join(' · ')),
                  trailing: const Icon(Icons.edit_outlined, color: HC.gris),
                  onTap: () => _modifier(context, t),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
