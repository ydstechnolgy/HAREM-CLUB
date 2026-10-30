import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/base_locale.dart';
import '../data/membre.dart';
import '../services/erreurs.dart';
import '../theme/harem_theme.dart';
import '../widgets/etat_synchro.dart';
import '../widgets/logo.dart';
import 'connexion.dart';
import 'gestion/gestion.dart';

/// Choisit l'écran : connexion, puis l'espace qui correspond au rôle de la personne.
class Aiguillage extends StatelessWidget {
  const Aiguillage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        final session = auth.currentSession;
        if (session == null) return const EcranConnexion();
        return _Chargement(key: ValueKey(session.user.id));
      },
    );
  }
}

class _Chargement extends StatefulWidget {
  const _Chargement({super.key});

  @override
  State<_Chargement> createState() => _ChargementState();
}

class _ChargementState extends State<_Chargement> {
  late Future<Membre?> _membre = _charger();

  static Future<Membre?> _charger() async {
    await attendrePremiereSynchro();
    var m = await Membre.charger();
    // Juste après la connexion, la fiche peut arriver quelques secondes après le reste.
    for (var i = 0; m == null && i < 10; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      m = await Membre.charger();
    }
    return m;
  }

  void _recharger() => setState(() => _membre = _charger());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Membre?>(
      future: _membre,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Logo(taille: 36, slogan: false),
                SizedBox(height: 32),
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Chargement des données du club…', style: TextStyle(color: HC.gris)),
              ]),
            ),
          );
        }
        final m = snap.data;
        if (snap.hasError || m == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: HC.rouge, size: 44),
                  const SizedBox(height: 16),
                  Text(
                    snap.hasError
                        ? messageErreur(snap.error!)
                        : 'Ce compte n\'est pas reconnu ou a été désactivé. Adressez-vous au patron.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(width: 240, child: FilledButton(onPressed: _recharger, child: const Text('Réessayer'))),
                  TextButton(onPressed: () => deconnexion(context), child: const Text('Se déconnecter')),
                ]),
              ),
            ),
          );
        }
        if (m.estServeuse) {
          // Le rôle serveuse n'existe plus dans l'application : le gérant fait tout.
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.info_outline, color: HC.or, size: 44),
                  const SizedBox(height: 16),
                  const Text(
                    'Ce compte serveuse n\'est plus utilisé. Demandez au patron de le passer en gérant, '
                    'ou connectez-vous avec un compte gérant.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextButton(onPressed: () => deconnexion(context), child: const Text('Se déconnecter')),
                ]),
              ),
            ),
          );
        }
        return EspaceGestion(membre: m);
      },
    );
  }
}
