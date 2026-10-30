import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/base_locale.dart';
import '../../data/membre.dart';
import '../../data/requetes.dart';
import '../../services/recu.dart';
import '../../theme/harem_theme.dart';
import '../../widgets/commun.dart';
import '../../widgets/etat_synchro.dart';

/// Réglages : reçu, imprimante de ce PC, déconnexion.
class ReglagesPage extends StatefulWidget {
  const ReglagesPage({super.key, required this.membre});
  final Membre membre;

  @override
  State<ReglagesPage> createState() => _ReglagesPageState();
}

class _ReglagesPageState extends State<ReglagesPage> {
  Printer? _imprimante;

  @override
  void initState() {
    super.initState();
    Recu.imprimante().then((p) {
      if (mounted) setState(() => _imprimante = p);
    });
  }

  Future<void> _modifier(Map<String, dynamic> r, String colonne, String titre) async {
    final v = await demanderTexte(context, titre, initial: '${r[colonne] ?? ''}');
    if (v == null || !mounted) return;
    await tenter(context, () => db.execute('UPDATE settings SET $colonne = ? WHERE id = ?', [v, r['id']]),
        succes: 'Enregistré.');
  }

  Future<void> _remiseAZero() async {
    final confirmation = TextEditingController();
    var stock = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Remettre à zéro ?'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Seront effacés définitivement :', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('• toutes les soirées et leurs clôtures\n• toutes les notes, boissons servies et paiements\n'
                  '• les dépenses et mouvements de caisse\n• les tables provisoires\nLes reçus repartent au n° 1.'),
              const SizedBox(height: 12),
              const Text('Toujours gardés : menu, prix, tables fixes, équipe, réglages.', style: TextStyle(color: HC.vert)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: stock,
                onChanged: (v) => set(() => stock = v ?? false),
                title: const Text('Remettre aussi le stock à zéro'),
                subtitle: const Text('Efface les arrivées, pertes et inventaires : toutes les boissons repartent à 0.'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmation,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Pour confirmer, tapez EFFACER'),
                onChanged: (_) => set(() {}),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: HC.rouge),
              onPressed: confirmation.text.trim().toUpperCase() == 'EFFACER' ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Tout effacer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await tenter(
      context,
      () => Supabase.instance.client
          .rpc('reset_club', params: {'p_confirmation': confirmation.text.trim(), 'p_stock': stock}),
      succes: 'Remise à zéro faite. Les autres appareils se mettent à jour en quelques secondes.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Lignes>(
      stream: Requetes.reglages(),
      builder: (context, snap) {
        final r = (snap.data ?? const []).firstOrNull;
        return ListView(padding: const EdgeInsets.all(16), children: [
          const TitreSection('Reçu'),
          if (r != null)
            Card(
              child: Column(children: [
                ListTile(
                  title: const Text('Titre du reçu'),
                  subtitle: Text('${r['ticket_header'] ?? ''}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _modifier(r, 'ticket_header', 'Titre du reçu'),
                ),
                ListTile(
                  title: const Text('Téléphones affichés'),
                  subtitle: Text('${r['phone'] ?? ''}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _modifier(r, 'phone', 'Téléphones affichés sur le reçu'),
                ),
                ListTile(
                  title: const Text('Message en bas du reçu'),
                  subtitle: Text('${r['ticket_footer'] ?? ''}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _modifier(r, 'ticket_footer', 'Message en bas du reçu'),
                ),
              ]),
            ),
          if (!kIsWeb) ...[
            const TitreSection('Imprimante de cet appareil'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.print, color: HC.or),
                title: Text(_imprimante?.name ?? 'Aucune imprimante choisie'),
                subtitle: Text(_imprimante == null
                    ? 'Le logiciel demandera l\'imprimante à chaque reçu.'
                    : 'Les reçus partent directement sur cette imprimante.'),
                trailing: Wrap(spacing: 8, children: [
                  if (_imprimante != null)
                    TextButton(
                      onPressed: () async {
                        await Recu.oublierImprimante();
                        if (mounted) setState(() => _imprimante = null);
                      },
                      child: const Text('Oublier'),
                    ),
                  FilledButton(
                    onPressed: () async {
                      final p = await Recu.choisirImprimante(context);
                      if (p != null && mounted) setState(() => _imprimante = p);
                    },
                    child: const Text('Choisir'),
                  ),
                ]),
              ),
            ),
          ],
          if (widget.membre.estPatron) ...[
            const TitreSection('Remise à zéro'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.restart_alt, color: HC.rouge),
                title: const Text('Remettre le logiciel à zéro'),
                subtitle: const Text('Efface les soirées, notes, paiements et dépenses (par exemple après les essais). '
                    'Le menu, les prix, les tables et l\'équipe sont gardés.'),
                onTap: _remiseAZero,
              ),
            ),
          ],
          const TitreSection('Compte'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: HC.rouge),
              title: Text('Se déconnecter (${widget.membre.nom})'),
              onTap: () => deconnexion(context),
            ),
          ),
        ]);
      },
    );
  }
}
