import 'package:flutter/material.dart';

import '../../data/actions.dart';
import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../theme/harem_theme.dart';
import '../../utils/format.dart';
import '../../widgets/commun.dart';

/// Le menu : on appuie sur + devant chaque boisson, puis « Envoyer au bar ».
class Commande extends StatefulWidget {
  const Commande({super.key, required this.membre, required this.tabId, required this.nomTable});
  final Membre membre;
  final String tabId;
  final String nomTable;

  @override
  State<Commande> createState() => _CommandeState();
}

class _CommandeState extends State<Commande> {
  final Map<String, int> _quantites = {};
  final Map<String, int> _prix = {};
  String? _categorie; // null = toutes
  String _recherche = '';
  bool _envoi = false;

  int get _nombre => _quantites.values.fold(0, (s, q) => s + q);
  int get _montant => _quantites.entries.fold(0, (s, e) => s + e.value * (_prix[e.key] ?? 0));

  void _changer(String id, int prix, int delta) {
    setState(() {
      _prix[id] = prix;
      final q = (_quantites[id] ?? 0) + delta;
      if (q <= 0) {
        _quantites.remove(id);
      } else {
        _quantites[id] = q;
      }
    });
  }

  Future<void> _envoyer() async {
    setState(() => _envoi = true);
    final ok = await tenter(context, () => Club.envoyerAuBar(widget.membre, widget.tabId, _quantites));
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok) {
      info(context, 'Envoyé au bar : $_nombre boisson${_nombre > 1 ? 's' : ''}');
      Navigator.pop(context, true);
    }
  }

  Future<bool> _quitter() async {
    if (_nombre == 0) return true;
    return confirmer(context, 'Abandonner la commande ?',
        'Les $_nombre boissons choisies ne seront pas envoyées au bar.', bouton: 'Abandonner', danger: true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _nombre == 0,
      onPopInvokedWithResult: (fait, _) async {
        if (fait) return;
        if (await _quitter() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: Text('Commande · ${widget.nomTable}')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Rechercher une boisson',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _recherche = v.trim().toLowerCase()),
            ),
          ),
          StreamBuilder<Lignes>(
            stream: Requetes.categories(),
            builder: (context, snap) {
              final cats = snap.data ?? const [];
              return SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _puce('Tout', null),
                    for (final c in cats) _puce('${c['name']}', c['id'] as String),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<Lignes>(
              stream: Requetes.boissons(),
              builder: (context, snap) {
                final toutes = snap.data ?? const [];
                final liste = toutes.where((p) {
                  if (_recherche.isNotEmpty) return '${p['name']}'.toLowerCase().contains(_recherche);
                  return _categorie == null || p['category_id'] == _categorie;
                }).toList();
                if (snap.hasData && liste.isEmpty) return const Vide('Aucune boisson trouvée.');
                String? derniere;
                final enfants = <Widget>[];
                for (final p in liste) {
                  final cat = '${p['category_name'] ?? ''}';
                  if (_categorie == null && _recherche.isEmpty && cat != derniere) {
                    enfants.add(TitreSection(cat));
                    derniere = cat;
                  }
                  enfants.add(_ligne(p));
                }
                return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: enfants);
              },
            ),
          ),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _nombre == 0 || _envoi ? null : _envoyer,
              icon: const Icon(Icons.local_bar),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              label: Text(_nombre == 0
                  ? 'Choisissez des boissons'
                  : 'Envoyer au bar · $_nombre · ${fcfa(_montant)}'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _puce(String texte, String? id) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: ChoiceChip(
          label: Text(texte),
          selected: _categorie == id && _recherche.isEmpty,
          onSelected: (_) => setState(() => _categorie = id),
        ),
      );

  Widget _ligne(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final prix = entier(p['sale_price']);
    final q = _quantites[id] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: q > 0 ? HC.fondOr : HC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: q > 0 ? HC.or : HC.bordure),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _changer(id, prix, 1),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(fcfa(prix), style: const TextStyle(color: HC.gris)),
              ]),
            ),
            if (q > 0) ...[
              IconButton.filledTonal(
                onPressed: () => _changer(id, prix, -1),
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 36,
                child: Text('$q', textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: HC.or)),
              ),
            ],
            IconButton.filled(
              onPressed: () => _changer(id, prix, 1),
              icon: const Icon(Icons.add),
            ),
          ]),
        ),
      ),
    );
  }
}
