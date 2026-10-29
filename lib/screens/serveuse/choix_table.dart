import 'package:flutter/material.dart';

import '../../data/actions.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../theme/harem_theme.dart';
import '../../widgets/commun.dart';

/// Choix de la table à ouvrir. Renvoie l'identifiant de la nouvelle note.
class ChoixTable extends StatelessWidget {
  const ChoixTable({super.key, required this.membre});
  final Membre membre;

  static String nomZone(String? z) => switch (z) {
        'vip' => 'VIP',
        'comptoir' => 'Comptoir',
        'terrasse' => 'Terrasse',
        _ => 'Salle',
      };

  Future<void> _ouvrir(BuildContext context, String tableId) async {
    try {
      final id = await Club.ouvrirNote(membre, tableId);
      if (context.mounted) Navigator.pop(context, id);
    } catch (e) {
      if (context.mounted) erreur(context, e);
    }
  }

  Future<void> _nouvelleTable(BuildContext context) async {
    final nom = await demanderTexte(context, 'Nouvelle table',
        label: 'Nom de la table (ex. Table 11, Terrasse 2)', bouton: 'Créer et ouvrir');
    if (nom == null || nom.isEmpty || !context.mounted) return;
    try {
      final tableId = await Club.creerTable(membre, nom);
      if (context.mounted) await _ouvrir(context, tableId);
    } catch (e) {
      if (context.mounted) erreur(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quelle table ?')),
      body: StreamBuilder<Lignes>(
        stream: Requetes.tablesLibres(),
        builder: (context, snap) {
          final tables = snap.data ?? const [];
          final zones = <String, List<Map<String, dynamic>>>{};
          for (final t in tables) {
            zones.putIfAbsent(nomZone(t['zone'] as String?), () => []).add(t);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              OutlinedButton.icon(
                onPressed: () => _nouvelleTable(context),
                icon: const Icon(Icons.add),
                label: const Text('Créer une autre table'),
              ),
              if (tables.isEmpty && snap.hasData)
                const Vide('Toutes les tables sont occupées.\nCréez une nouvelle table.'),
              for (final z in zones.entries) ...[
                TitreSection(z.key),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final t in z.value)
                      SizedBox(
                        width: 104,
                        height: 72,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: HC.surface2,
                            foregroundColor: HC.texte,
                            side: const BorderSide(color: HC.bordure),
                            padding: const EdgeInsets.all(6),
                          ),
                          onPressed: () => _ouvrir(context, t['id'] as String),
                          child: Text('${t['name']}', textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
