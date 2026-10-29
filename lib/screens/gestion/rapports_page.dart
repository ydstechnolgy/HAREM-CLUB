import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../services/erreurs.dart';
import '../../theme/harem_theme.dart';
import '../../utils/format.dart';
import '../../widgets/commun.dart';

/// Rapport d'une soirée : chiffre, marge, serveuses, boissons les plus vendues.
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
    final cout = entier(r['cost']);
    final paiements = Map<String, dynamic>.from((r['payments'] as Map?) ?? const {});
    final serveuses = [for (final x in (r['by_waitress'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final top = [for (final x in (r['top_products'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _Tuile('Chiffre encaissé', fcfa(ca), accent: true),
        _Tuile('Marge sur les boissons', fcfa(ca - cout)),
        _Tuile('Espèces', fcfa(entier(paiements['cash']))),
        _Tuile('Mobile Money', fcfa(entier(paiements['mobile_money']))),
        _Tuile('Dépenses', fcfa(entier(r['expenses']))),
        _Tuile('Notes encaissées', '${entier(r['tabs_paid'])}'),
        if (entier(r['tabs_open']) > 0) _Tuile('Notes encore ouvertes', '${entier(r['tabs_open'])}'),
        if (entier(r['tabs_cancelled']) > 0) _Tuile('Notes annulées', '${entier(r['tabs_cancelled'])}'),
      ]),
      if (cout == 0 && ca > 0)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('La marge sera juste quand les prix d\'achat seront saisis (Stock > arrivée de stock).',
              style: TextStyle(color: HC.gris, fontSize: 12.5)),
        ),
      const TitreSection('Par serveuse'),
      Card(
        child: Column(children: [
          for (final s in serveuses)
            ListTile(
              title: Text('${s['display_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${entier(s['tabs'])} note(s) · ${entier(s['items'])} boisson(s)'
                  '${entier(s['open_tabs']) > 0 ? ' · ${entier(s['open_tabs'])} encore ouverte(s)' : ''}'
                  '${entier(s['removed_after_service']) > 0 ? ' · ${entier(s['removed_after_service'])} retirée(s) après service' : ''}'),
              trailing: Text(fcfa(entier(s['revenue'])), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          if (serveuses.isEmpty) const ListTile(title: Text('Aucune note.')),
        ]),
      ),
      const TitreSection('Boissons les plus vendues'),
      Card(
        child: Column(children: [
          for (final t in top)
            ListTile(
              dense: true,
              leading: Text('${entier(t['quantity'])}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: HC.or)),
              title: Text('${t['name']}'),
              subtitle: Text('Marge ${fcfa(entier(t['margin']))}'),
              trailing: Text(fcfa(entier(t['revenue']))),
            ),
          if (top.isEmpty) const ListTile(title: Text('Aucune vente.')),
        ]),
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
