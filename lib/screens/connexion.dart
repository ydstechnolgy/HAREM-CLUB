import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/erreurs.dart';
import '../theme/harem_theme.dart';
import '../widgets/logo.dart';

/// Connexion avec l'identifiant et le code PIN à 6 chiffres.
class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion> {
  final _identifiant = TextEditingController();
  final _pin = TextEditingController();
  bool _envoi = false;
  bool _voirPin = false;
  String? _erreur;

  @override
  void dispose() {
    _identifiant.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    final id = _identifiant.text.trim().toLowerCase();
    final pin = _pin.text.trim();
    if (id.isEmpty) return setState(() => _erreur = 'Entrez votre identifiant.');
    if (pin.length != 6) return setState(() => _erreur = 'Le code PIN contient 6 chiffres.');
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: HaremConfig.emailInterne(id), password: pin);
    } catch (e) {
      if (mounted) setState(() => _erreur = messageErreur(e));
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Logo(taille: 46),
                    const SizedBox(height: 40),
                    TextField(
                      controller: _identifiant,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Identifiant',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pin,
                      obscureText: !_voirPin,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _connecter(),
                      style: const TextStyle(fontSize: 22, letterSpacing: 8),
                      decoration: InputDecoration(
                        labelText: 'Code PIN',
                        counterText: '',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_voirPin ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _voirPin = !_voirPin),
                        ),
                      ),
                    ),
                    if (_erreur != null) ...[
                      const SizedBox(height: 12),
                      Text(_erreur!, style: const TextStyle(color: HC.rouge)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _envoi ? null : _connecter,
                      child: _envoi
                          ? const SizedBox(
                              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const Text('Se connecter'),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Pas encore de compte ? Demandez au patron de vous en créer un.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: HC.gris),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
