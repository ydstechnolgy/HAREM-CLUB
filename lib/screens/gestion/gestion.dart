import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../theme/harem_theme.dart';
import '../../widgets/etat_synchro.dart';
import '../../widgets/icone_compteur.dart';
import 'equipe_page.dart';
import 'menu_page.dart';
import 'notes_page.dart';
import 'rapports_page.dart';
import 'reglages_page.dart';
import 'soiree_page.dart';
import 'stock_page.dart';

class _Rubrique {
  const _Rubrique(this.titre, this.icone, this.page, {this.compteur});
  final String titre;
  final IconData icone;
  final Widget Function(Membre) page;

  /// Requête qui compte ce qui attend une action (pastille sur le menu).
  final String? compteur;
}

/// Espace du gérant et du patron : PC du bar, téléphone ou web.
class EspaceGestion extends StatefulWidget {
  const EspaceGestion({super.key, required this.membre});
  final Membre membre;

  @override
  State<EspaceGestion> createState() => _EspaceGestionState();
}

class _EspaceGestionState extends State<EspaceGestion> {
  int _index = 0;

  late final List<_Rubrique> _rubriques = [
    _Rubrique('Tables', Icons.table_restaurant, (m) => NotesPage(membre: m),
        compteur: "SELECT COUNT(*) AS n FROM tabs WHERE status IN ('open', 'to_pay')"),
    _Rubrique('Soirée et caisse', Icons.nightlife, (m) => SoireePage(membre: m)),
    _Rubrique('Stock', Icons.inventory_2_outlined, (m) => StockPage(membre: m)),
    _Rubrique('Menu et tables', Icons.menu_book, (m) => MenuPage(membre: m)),
    _Rubrique('Rapports', Icons.bar_chart, (m) => RapportsPage(membre: m)),
    if (widget.membre.estPatron) _Rubrique('Équipe', Icons.groups, (m) => EquipePage(membre: m)),
    _Rubrique('Réglages', Icons.settings_outlined, (m) => ReglagesPage(membre: m)),
  ];

  /// Compteurs lus une seule fois (partagés par le menu du téléphone et celui du PC).
  final Map<String, ValueNotifier<int>> _compteurs = {};
  final List<StreamSubscription<Object?>> _abonnements = [];

  @override
  void initState() {
    super.initState();
    for (final r in _rubriques) {
      if (r.compteur == null) continue;
      final v = _compteurs[r.titre] = ValueNotifier<int>(0);
      _abonnements.add(db.watch(r.compteur!).listen(
            (rows) => v.value = rows.isEmpty ? 0 : entier(rows.first['n']),
            onError: (_) {}, // un souci de lecture ne doit jamais casser le menu
          ));
    }
  }

  @override
  void dispose() {
    for (final a in _abonnements) {
      a.cancel();
    }
    for (final v in _compteurs.values) {
      v.dispose();
    }
    super.dispose();
  }

  Widget _icone(_Rubrique r) => IconeCompteur(icone: r.icone, compte: _compteurs[r.titre]);

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 900;
    final r = _rubriques[_index];
    final contenu = Column(children: [
      const BandeauRefus(),
      Expanded(child: KeyedSubtree(key: ValueKey(_index), child: r.page(widget.membre))),
    ]);

    final titre = Row(children: [
      Text(r.titre),
      const Spacer(),
      const EtatSynchro(),
    ]);

    if (large) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1150,
            minExtendedWidth: 220,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                const Icon(Icons.star, color: HC.or),
                const Text('HAREM', style: TextStyle(color: HC.or, fontWeight: FontWeight.w900, letterSpacing: 3)),
                Text('${widget.membre.nom} · ${widget.membre.libelleRole}',
                    style: const TextStyle(color: HC.gris, fontSize: 11.5)),
              ]),
            ),
            destinations: [
              for (final x in _rubriques)
                NavigationRailDestination(icon: _icone(x), label: Text(x.titre)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Scaffold(
              appBar: AppBar(title: titre),
              body: contenu,
            ),
          ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: titre),
      drawer: Drawer(
        backgroundColor: HC.surface,
        child: SafeArea(
          child: ListView(children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('HAREM CLUB',
                    style: TextStyle(color: HC.or, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 18)),
                Text('${widget.membre.nom} · ${widget.membre.libelleRole}', style: const TextStyle(color: HC.gris)),
              ]),
            ),
            for (var i = 0; i < _rubriques.length; i++)
              ListTile(
                leading: _icone(_rubriques[i]),
                title: Text(_rubriques[i].titre),
                selected: i == _index,
                selectedColor: HC.or,
                onTap: () {
                  setState(() => _index = i);
                  Navigator.pop(context);
                },
              ),
          ]),
        ),
      ),
      body: contenu,
    );
  }
}
