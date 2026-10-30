import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../services/erreurs.dart';
import '../../theme/harem_theme.dart';
import '../../utils/format.dart';
import '../../widgets/commun.dart';
import '../../widgets/graphiques.dart';

/// Rapport d'une soirée : chiffre, serveuses, boissons les plus vendues.
/// Calculé par le serveur (il connaît les prix d'achat) : il faut internet.
class RapportsPage extends StatefulWidget {
  const RapportsPage({super.key, required this.membre});
  final Membre membre;

  @override
  State<RapportsPage> createState() => _RapportsPageState();
}

class _RapportsPageState extends State<RapportsPage> {
  String? _soiree;
  Future<Map<String, dynamic>>? _rapport;

  void _charger(String id) {
    setState(() {
      _soiree = id;
      _rapport = Supabase.instance.client
          .rpc('night_report', params: {'p_night_id': id})
          .then((r) => Map<String, dynamic>.from(r as Map));
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: db.watch('SELECT id, status, opened_at FROM nights ORDER BY opened_at DESC LIMIT 60'),
      builder: (context, snap) {
        final soirees = snap.data ?? const [];
        if (snap.hasData && soirees.isEmpty) return const Vide('Aucune soirée pour l\'instant.', icone: Icons.bar_chart);
        if (_soiree == null && soirees.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _soiree == null) _charger(soirees.first['id'] as String);
          });
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          _GraphiqueSoirees(choisie: _soiree, onChoix: _charger),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                initialValue: _soiree,
                key: ValueKey(_soiree),
                decoration: const InputDecoration(labelText: 'Soirée'),
                items: [
                  for (final s in soirees)
                    DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text(_nom(s)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _charger(v);
                },
              ),
            ),
            if (_soiree != null)
              IconButton(tooltip: 'Actualiser', onPressed: () => _charger(_soiree!), icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 16),
          if (_rapport != null)
            FutureBuilder<Map<String, dynamic>>(
              future: _rapport,
              builder: (context, r) {
                if (r.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                }
                if (r.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(messageErreur(r.error!), style: const TextStyle(color: HC.rouge)),
                  );
                }
                return _Rapport(r.data!);
              },
            ),
        ]);
      },
    );
  }

  static String _nom(Map<String, dynamic> s) {
    final d = DateTime.tryParse('${s['opened_at']}')?.toLocal();
    final nom = d == null ? 'Soirée' : 'Soirée du ${dateCourte(d)}';
    return s['status'] == 'open' ? '$nom (en cours)' : nom;
  }
}

class _Rapport extends StatelessWidget {
  const _Rapport(this.r);
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final ca = entier(r['revenue']);
    final paiements = Map<String, dynamic>.from((r['payments'] as Map?) ?? const {});
    final serveuses = [for (final x in (r['by_waitress'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final top = [for (final x in (r['top_products'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _Tuile('Chiffre encaissé', fcfa(ca), accent: true),
        _Tuile('Espèces', fcfa(entier(paiements['cash']))),
        _Tuile('Mobile Money', fcfa(entier(paiements['mobile_money']))),
        _Tuile('Dépenses', fcfa(entier(r['expenses']))),
        _Tuile('Notes encaissées', '${entier(r['tabs_paid'])}'),
        if (entier(r['tabs_open']) > 0) _Tuile('Notes encore ouvertes', '${entier(r['tabs_open'])}'),
        if (entier(r['tabs_cancelled']) > 0) _Tuile('Notes annulées', '${entier(r['tabs_cancelled'])}'),
      ]),
      if (entier(paiements['cash']) + entier(paiements['mobile_money']) > 0) ...[
        const TitreSection('Espèces et Mobile Money'),
        BarrePartagee(
          gauche: Barre('Espèces', entier(paiements['cash'])),
          droite: Barre('Mobile Money', entier(paiements['mobile_money'])),
        ),
      ],
      const TitreSection('Par gérant'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: serveuses.isEmpty
              ? const Text('Aucune note.', style: TextStyle(color: HC.gris))
              : BarresHorizontales(barres: [
                  for (final s in serveuses)
                    Barre(
                      '${s['display_name']}',
                      entier(s['revenue']),
                      detail: '${entier(s['tabs'])} note(s) · ${entier(s['items'])} boisson(s)'
                          '${entier(s['open_tabs']) > 0 ? ' · ${entier(s['open_tabs'])} ouverte(s)' : ''}'
                          '${entier(s['removed_after_service']) > 0 ? ' · ${entier(s['removed_after_service'])} retirée(s)' : ''}',
                    ),
                ]),
        ),
      ),
      const TitreSection('Boissons les plus vendues'),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: top.isEmpty
              ? const Text('Aucune vente.', style: TextStyle(color: HC.gris))
              : BarresHorizontales(
                  couleur: HC.bleu,
                  formater: (q) => '$q vendu${q > 1 ? 's' : ''}',
                  barres: [
                    for (final t in top)
                      Barre('${t['name']}', entier(t['quantity']), detail: fcfa(entier(t['revenue']))),
                  ],
                ),
        ),
      ),
    ]);
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile(this.titre, this.valeur, {this.accent = false});
  final String titre;
  final String valeur;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent ? HC.fondOr : HC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent ? HC.or : HC.bordure),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: const TextStyle(color: HC.gris, fontSize: 12.5)),
        const SizedBox(height: 4),
        Text(valeur, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: accent ? HC.or : HC.texte)),
      ]),
    );
  }
}


/// Chiffre encaissé des 14 dernières soirées (calculé sur l'appareil, sans internet).
class _GraphiqueSoirees extends StatelessWidget {
  const _GraphiqueSoirees({required this.choisie, required this.onChoix});
  final String? choisie;
  final ValueChanged<String> onChoix;

  static const _jours = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: db.watch(
        'SELECT n.id, n.status, n.opened_at, '
        "COALESCE((SELECT SUM(t.total) FROM tabs t WHERE t.night_id = n.id AND t.status = 'paid'), 0) AS ca "
        'FROM nights n ORDER BY n.opened_at DESC LIMIT 14',
      ),
      builder: (context, snap) {
        final lignes = (snap.data ?? const <Map<String, dynamic>>[]).reversed.toList();
        if (lignes.isEmpty) return const SizedBox.shrink();
        final total = lignes.fold<int>(0, (t, l) => t + entier(l['ca']));
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                  child: Text('Chiffre des dernières soirées', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ),
                Text('Total ${fcfa(total)}', style: const TextStyle(color: HC.or, fontWeight: FontWeight.w800)),
              ]),
              const Text('Touchez une barre pour voir le détail de la soirée.', style: TextStyle(color: HC.gris, fontSize: 12.5)),
              const SizedBox(height: 12),
              BarresVerticales(
                barres: [
                  for (final l in lignes)
                    () {
                      final d = DateTime.tryParse('${l['opened_at']}')?.toLocal();
                      return Barre(
                        d == null ? '?' : '${_jours[d.weekday - 1]} ${d.day}',
                        entier(l['ca']),
                        detail: d == null ? 'Soirée' : 'Soirée du ${dateCourte(d)}${l['status'] == 'open' ? ' (en cours)' : ''}',
                        id: l['id'] as String,
                        choisie: l['id'] == choisie,
                        enCours: l['status'] == 'open',
                      );
                    }(),
                ],
                onTap: (b) {
                  if (b.id != null) onChoix(b.id!);
                },
              ),
            ]),
          ),
        );
      },
    );
  }
}
