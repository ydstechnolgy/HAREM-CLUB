import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

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
