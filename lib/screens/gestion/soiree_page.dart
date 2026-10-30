import 'package:flutter/material.dart';

import '../../data/actions.dart';
import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../theme/harem_theme.dart';
import '../../utils/format.dart';
import '../../widgets/commun.dart';

/// Ouverture et clôture de la soirée, dépenses et mouvements de caisse.
class SoireePage extends StatelessWidget {
  const SoireePage({super.key, required this.membre});
  final Membre membre;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: Requetes.soireeOuverte(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final soiree = snap.data!.firstOrNull;
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (soiree == null) _Ouverture(membre: membre) else _SoireeEnCours(membre: membre, soiree: soiree),
          const SizedBox(height: 24),
          const TitreSection('Dernières soirées'),
          const _Historique(),
        ]);
      },
    );
  }
}

class _Ouverture extends StatefulWidget {
  const _Ouverture({required this.membre});
  final Membre membre;

  @override
  State<_Ouverture> createState() => _OuvertureState();
}

class _OuvertureState extends State<_Ouverture> {
  final _fond = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('La soirée est fermée', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Ouvrez-la pour commencer à ouvrir des tables.', style: TextStyle(color: HC.gris)),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ChampNombre(controller: _fond, label: 'Fond de caisse (monnaie de départ)', suffixe: 'FCFA'),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => tenter(context, () => Club.ouvrirSoiree(widget.membre, lireNombre(_fond)),
                  succes: 'Soirée ouverte. Bonne soirée !'),
              icon: const Icon(Icons.nightlife),
              label: const Text('Ouvrir la soirée'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SoireeEnCours extends StatelessWidget {
  const _SoireeEnCours({required this.membre, required this.soiree});
  final Membre membre;
  final Map<String, dynamic> soiree;

  Stream<Lignes> _chiffres() => db.watch(
        'SELECT '
        "(SELECT COALESCE(SUM(p.amount), 0) FROM payments p WHERE p.night_id = ?1 AND p.method = 'cash') AS especes, "
        "(SELECT COALESCE(SUM(p.amount), 0) FROM payments p WHERE p.night_id = ?1 AND p.method = 'mobile_money') AS momo, "
        "(SELECT COALESCE(SUM(amount), 0) FROM cash_movements WHERE night_id = ?1 AND type = 'in') AS entrees, "
        "(SELECT COALESCE(SUM(amount), 0) FROM cash_movements WHERE night_id = ?1 AND type = 'out') AS sorties, "
        "(SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE night_id = ?1 AND from_till = 1 AND method = 'cash') AS depenses, "
        "(SELECT COUNT(*) FROM tabs WHERE night_id = ?1 AND status IN ('open', 'to_pay')) AS ouvertes, "
        "(SELECT COALESCE(SUM(total), 0) FROM tabs WHERE night_id = ?1 AND status IN ('open', 'to_pay')) AS en_cours, "
        "(SELECT COUNT(*) FROM tabs WHERE night_id = ?1 AND status = 'paid') AS payees",
        parameters: [soiree['id']],
      );

  Future<void> _depense(BuildContext context) async {
    final libelle = TextEditingController();
    final montant = TextEditingController();
    var methode = 'cash';
    var caisse = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nouvelle dépense'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in const ['Glace', 'DJ', 'Sécurité', 'Transport', 'Électricité', 'Achat boissons'])
                  ActionChip(label: Text(s), onPressed: () => set(() => libelle.text = s)),
              ]),
              const SizedBox(height: 12),
              TextField(controller: libelle, decoration: const InputDecoration(labelText: 'Pour quoi ?')),
              const SizedBox(height: 12),
              ChampNombre(controller: montant, label: 'Montant', suffixe: 'FCFA'),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('Espèces')),
                  ButtonSegment(value: 'mobile_money', label: Text('Mobile Money')),
                ],
                selected: {methode},
                onSelectionChanged: (s) => set(() => methode = s.first),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: caisse,
                onChanged: (v) => set(() => caisse = v ?? true),
                title: const Text('Payée avec l\'argent de la caisse'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await tenter(context,
          () => Club.depense(membre, libelle.text, lireNombre(montant), methode: methode, depuisCaisse: caisse),
          succes: 'Dépense enregistrée.');
    }
  }

  Future<void> _mouvement(BuildContext context, String type) async {
    final montant = TextEditingController();
    final raison = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(type == 'in' ? 'Mettre de l\'argent dans la caisse' : 'Retirer de l\'argent de la caisse'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ChampNombre(controller: montant, label: 'Montant', suffixe: 'FCFA', autofocus: true),
            const SizedBox(height: 12),
            TextField(
              controller: raison,
              decoration: InputDecoration(
                  labelText: 'Raison', hintText: type == 'in' ? 'ex. Monnaie ajoutée' : 'ex. Remis au patron'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await tenter(context, () => Club.mouvementCaisse(membre, type, lireNombre(montant), raison.text),
          succes: 'Mouvement enregistré.');
    }
  }

  Future<void> _cloturer(BuildContext context, int attenduEspeces, int attenduMomo) async {
    final especes = TextEditingController();
    final momo = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clôturer la soirée'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Comptez l\'argent avant de saisir. Les montants attendus apparaîtront après la clôture.',
                style: TextStyle(color: HC.gris)),
            const SizedBox(height: 16),
            ChampNombre(controller: especes, label: 'Espèces comptées dans la caisse', suffixe: 'FCFA', autofocus: true),
            const SizedBox(height: 12),
            ChampNombre(controller: momo, label: 'Mobile Money reçu (vérifié sur le téléphone)', suffixe: 'FCFA'),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Remarque (facultatif)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clôturer')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await tenter(
        context,
        () => Club.cloturerSoiree(membre, lireNombre(especes), lireNombre(momo), note.text.trim().isEmpty ? null : note.text.trim()),
        succes: 'Soirée clôturée. Le résultat apparaît dans « Dernières soirées ».',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ouverture = DateTime.tryParse('${soiree['opened_at']}')?.toLocal();
    return StreamBuilder<Lignes>(
      stream: _chiffres(),
      builder: (context, snap) {
        final c = (snap.data ?? const []).firstOrNull ?? const <String, dynamic>{};
        final fond = entier(soiree['opening_float']);
        final attenduEspeces =
            fond + entier(c['especes']) + entier(c['entrees']) - entier(c['sorties']) - entier(c['depenses']);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12), side: const BorderSide(color: HC.vert, width: 1.5)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Pastille('Soirée ouverte', couleur: HC.vert, fond: HC.fondVert),
                  const SizedBox(width: 12),
                  if (ouverture != null)
                    Text('depuis ${dateCourte(ouverture)} à ${ouverture.hour}h${ouverture.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: HC.gris)),
                ]),
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  _Chiffre('Encaissé espèces', fcfa(entier(c['especes']))),
                  _Chiffre('Encaissé Mobile Money', fcfa(entier(c['momo']))),
                  _Chiffre('Tables en cours', '${entier(c['ouvertes'])} · ${fcfa(entier(c['en_cours']))}'),
                  _Chiffre('Notes encaissées', '${entier(c['payees'])}'),
                  _Chiffre('Fond de caisse', fcfa(fond)),
                  _Chiffre('Dépenses (caisse)', fcfa(entier(c['depenses']))),
                  _Chiffre('Espèces attendues dans la caisse', fcfa(attenduEspeces), accent: true),
                ]),
                const SizedBox(height: 20),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => _depense(context), icon: const Icon(Icons.receipt_long), label: const Text('Dépense')),
                  OutlinedButton.icon(
                      onPressed: () => _mouvement(context, 'in'), icon: const Icon(Icons.add), label: const Text('Entrée de caisse')),
                  OutlinedButton.icon(
                      onPressed: () => _mouvement(context, 'out'), icon: const Icon(Icons.remove), label: const Text('Sortie de caisse')),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: HC.rouge),
                    onPressed: () => _cloturer(context, attenduEspeces, entier(c['momo'])),
                    icon: const Icon(Icons.lock),
                    label: const Text('Clôturer la soirée'),
                  ),
                ]),
              ]),
            ),
          ),
          const TitreSection('Dépenses et mouvements de la soirée'),
          _Mouvements(soireeId: soiree['id'] as String),
        ]);
      },
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre(this.titre, this.valeur, {this.accent = false});
  final String titre;
  final String valeur;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent ? HC.fondOr : HC.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent ? HC.or : HC.bordure),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre, style: const TextStyle(color: HC.gris, fontSize: 12.5)),
        const SizedBox(height: 4),
        Text(valeur, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent ? HC.or : HC.texte)),
      ]),
    );
  }
}

class _Mouvements extends StatelessWidget {
  const _Mouvements({required this.soireeId});
  final String soireeId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: db.watch(
        "SELECT 'depense' AS genre, label AS libelle, amount, method, created_at FROM expenses WHERE night_id = ?1 "
        "UNION ALL SELECT type AS genre, reason AS libelle, amount, 'cash' AS method, created_at FROM cash_movements WHERE night_id = ?1 "
        'ORDER BY created_at DESC',
        parameters: [soireeId],
      ),
      builder: (context, snap) {
        final lignes = snap.data ?? const [];
        if (lignes.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('Rien pour l\'instant.', style: TextStyle(color: HC.gris)));
        return Column(children: [
          for (final l in lignes)
            ListTile(
              dense: true,
              leading: Icon(
                l['genre'] == 'in' ? Icons.add_circle_outline : (l['genre'] == 'out' ? Icons.remove_circle_outline : Icons.receipt_long),
                color: l['genre'] == 'in' ? HC.vert : HC.rouge,
              ),
              title: Text('${l['libelle']}'),
              subtitle: Text(l['genre'] == 'depense' ? 'Dépense' : (l['genre'] == 'in' ? 'Entrée de caisse' : 'Sortie de caisse')),
              trailing: Text(fcfa(entier(l['amount']))),
            ),
        ]);
      },
    );
  }
}

class _Historique extends StatelessWidget {
  const _Historique();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: db.watch(
        'SELECT n.*, g.display_name AS closed_by_name, o.display_name AS opened_by_name '
        'FROM nights n LEFT JOIN members g ON g.id = n.closed_by LEFT JOIN members o ON o.id = n.opened_by '
        "WHERE n.status = 'closed' ORDER BY n.opened_at DESC LIMIT 15",
      ),
      builder: (context, snap) {
        final soirees = snap.data ?? const [];
        if (soirees.isEmpty) return const Text('Aucune soirée clôturée.', style: TextStyle(color: HC.gris));
        return Column(children: [
          for (final s in soirees) _SoireeFermee(s),
        ]);
      },
    );
  }
}

class _SoireeFermee extends StatelessWidget {
  const _SoireeFermee(this.s);
  final Map<String, dynamic> s;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse('${s['opened_at']}')?.toLocal();
    final calcule = s['expected_cash'] != null;
    final ecart = entier(s['difference_cash']) + entier(s['difference_momo']);
    final gerant = '${s['closed_by_name'] ?? ''}'.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(date == null ? 'Soirée' : 'Soirée du ${dateCourte(date)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(calcule
            ? '${gerant.isEmpty ? '' : 'Clôturée par $gerant\n'}'
                'Espèces : attendu ${fcfa(entier(s['expected_cash']))}, compté ${fcfa(entier(s['counted_cash']))}\n'
                'Mobile Money : attendu ${fcfa(entier(s['expected_momo']))}, compté ${fcfa(entier(s['counted_momo']))}'
            : 'Calcul en cours… (envoi au serveur)'),
        isThreeLine: calcule,
        trailing: calcule
            ? Pastille(
                ecart == 0 ? 'Juste' : 'Écart ${ecart > 0 ? '+' : ''}${fcfa(ecart)}',
                couleur: ecart == 0 ? HC.vert : (ecart > 0 ? HC.or : HC.rouge),
                fond: ecart == 0 ? HC.fondVert : (ecart > 0 ? HC.fondOr : HC.fondRouge),
              )
            : null,
      ),
    );
  }
}
