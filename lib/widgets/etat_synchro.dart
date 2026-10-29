import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';

import '../data/base_locale.dart';
import '../theme/harem_theme.dart';
import 'commun.dart';

/// Petit indicateur en haut de l'écran : à jour, hors ligne, envois en attente.
class EtatSynchro extends StatefulWidget {
  const EtatSynchro({super.key});

  @override
  State<EtatSynchro> createState() => _EtatSynchroState();
}

class _EtatSynchroState extends State<EtatSynchro> {
  int _enAttente = 0;
  Timer? _minuterie;

  @override
  void initState() {
    super.initState();
    _compter();
    _minuterie = Timer.periodic(const Duration(seconds: 2), (_) => _compter());
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    super.dispose();
  }

  Future<void> _compter() async {
    try {
      final n = await changementsEnAttente();
      if (mounted && n != _enAttente) setState(() => _enAttente = n);
    } catch (_) {
      // Base en cours de fermeture (déconnexion) : on ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: db.statusStream,
      initialData: db.currentStatus,
      builder: (context, snap) {
        final s = snap.data!;
        final (IconData icone, Color couleur, String texte) = !s.connected
            ? (Icons.wifi_off, HC.orClair, _enAttente > 0 ? 'Hors ligne · $_enAttente en attente' : 'Hors ligne')
            : _enAttente > 0
                ? (Icons.sync, HC.gris, 'Envoi…')
                : (Icons.cloud_done_outlined, HC.vert, 'À jour');
        return Tooltip(
          message: s.connected
              ? 'Cet appareil est relié au serveur du club.'
              : 'Pas de connexion : vous pouvez continuer. Tout sera envoyé au retour du Wi-Fi.',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: s.connected ? Colors.transparent : HC.fondOr,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icone, size: 18, color: couleur),
              const SizedBox(width: 6),
              Text(texte, style: TextStyle(fontSize: 13, color: couleur, fontWeight: FontWeight.w600)),
            ]),
          ),
        );
      },
    );
  }
}

/// Bandeau rouge quand le serveur a refusé une action faite sur cet appareil
/// (par exemple : table déjà prise par une collègue, boisson retirée du menu).
class BandeauRefus extends StatelessWidget {
  const BandeauRefus({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.watch('SELECT * FROM envois_refuses ORDER BY created_at DESC'),
      builder: (context, snap) {
        final refus = snap.data ?? const [];
        if (refus.isEmpty) return const SizedBox.shrink();
        return Material(
          color: HC.fondRouge,
          child: InkWell(
            onTap: () => _details(context, [for (final r in refus) Map<String, dynamic>.from(r)]),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                const Icon(Icons.error_outline, color: HC.rouge),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    refus.length == 1
                        ? 'Une action a été refusée par le serveur : ${refus.first['erreur']}'
                        : '${refus.length} actions ont été refusées par le serveur. Appuyez pour voir.',
                    style: const TextStyle(color: HC.texte),
                  ),
                ),
                const Icon(Icons.chevron_right, color: HC.texte),
              ]),
            ),
          ),
        );
      },
    );
  }

  static String _nom(String type) => switch (type) {
        'open_tab' => 'Ouverture de table',
        'add_items' => 'Boissons envoyées au bar',
        'request_payment' => 'Demande d\'encaissement',
        'serve_items' => 'Boissons servies',
        'record_payment' => 'Encaissement',
        'create_table' => 'Nouvelle table',
        'open_night' => 'Ouverture de soirée',
        'close_night' => 'Clôture de soirée',
        'cancel_tab' => 'Annulation de note',
        'receive_stock' => 'Entrée de stock',
        _ => type,
      };

  void _details(BuildContext context, List<Map<String, dynamic>> refus) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Actions refusées'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Le serveur n\'a pas accepté ces actions. Elles n\'ont pas été enregistrées : '
                'refaites-les si besoin.',
                style: TextStyle(color: HC.gris),
              ),
              const SizedBox(height: 12),
              for (final r in refus)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.block, color: HC.rouge),
                  title: Text(_nom('${r['type']}')),
                  subtitle: Text('${r['erreur']}'),
                  onLongPress: () => info(ctx, jsonEncode(r['payload'])),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await db.execute('DELETE FROM envois_refuses');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('J\'ai compris, effacer'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }
}

/// Déconnexion, avec explication si des changements attendent encore d'être envoyés.
Future<void> deconnexion(BuildContext context) async {
  final ok = await confirmer(context, 'Se déconnecter ?',
      'Vous devrez entrer à nouveau votre identifiant et votre code PIN.', bouton: 'Se déconnecter');
  if (!ok) return;
  final message = await seDeconnecter();
  if (message != null && context.mounted) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pas encore'),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }
}
