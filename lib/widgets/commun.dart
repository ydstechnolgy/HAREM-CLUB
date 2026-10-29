import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/erreurs.dart';
import '../theme/harem_theme.dart';

/// Petit message en bas de l'écran.
void info(BuildContext context, String texte) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texte)));
}

/// Message d'erreur en bas de l'écran.
void erreur(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: HC.fondRouge,
      content: Text(messageErreur(e), style: const TextStyle(color: HC.texte)),
    ));
}

/// Lance une action et affiche l'erreur éventuelle. Renvoie vrai si tout s'est bien passé.
Future<bool> tenter(BuildContext context, Future<void> Function() action, {String? succes}) async {
  try {
    await action();
    if (succes != null && context.mounted) info(context, succes);
    return true;
  } catch (e) {
    if (context.mounted) erreur(context, e);
    return false;
  }
}

/// Fenêtre « Êtes-vous sûr ? ».
Future<bool> confirmer(BuildContext context, String titre, String texte,
    {String bouton = 'Confirmer', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titre),
      content: Text(texte),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: HC.rouge) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(bouton),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Demande un texte (raison, nom…). Renvoie null si annulé.
Future<String?> demanderTexte(BuildContext context, String titre,
    {String? label, String initial = '', String bouton = 'Valider', List<String> suggestions = const []}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titre),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (suggestions.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in suggestions)
                    ActionChip(label: Text(s), onPressed: () => Navigator.pop(ctx, s)),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: ctrl,
              autofocus: suggestions.isEmpty,
              decoration: InputDecoration(labelText: label),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(bouton)),
      ],
    ),
  );
}

/// Champ de saisie d'un montant ou d'une quantité (chiffres uniquement).
class ChampNombre extends StatelessWidget {
  const ChampNombre({
    super.key,
    required this.controller,
    required this.label,
    this.suffixe,
    this.autofocus = false,
    this.negatif = false,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? suffixe;
  final bool autofocus;
  final bool negatif;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(signed: negatif),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(negatif ? r'[-0-9]' : r'[0-9]'))],
      decoration: InputDecoration(labelText: label, suffixText: suffixe),
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      onSubmitted: onSubmitted,
      onChanged: onChanged,
    );
  }
}

/// Lit un nombre saisi (0 si vide).
int lireNombre(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

/// Pastille de couleur (état d'une boisson, d'une note…).
class Pastille extends StatelessWidget {
  const Pastille(this.texte, {super.key, this.couleur = HC.or, this.fond = HC.fondOr});
  final String texte;
  final Color couleur;
  final Color fond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(20)),
      child: Text(texte, style: TextStyle(color: couleur, fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// Message centré quand une liste est vide.
class Vide extends StatelessWidget {
  const Vide(this.texte, {super.key, this.icone = Icons.inbox_outlined});
  final String texte;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: HC.bordure),
            const SizedBox(height: 12),
            Text(texte, textAlign: TextAlign.center, style: const TextStyle(color: HC.gris, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

/// Titre de section.
class TitreSection extends StatelessWidget {
  const TitreSection(this.texte, {super.key, this.droite});
  final String texte;
  final Widget? droite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(texte.toUpperCase(),
                style: const TextStyle(color: HC.or, fontSize: 12.5, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          ),
          ?droite,
        ],
      ),
    );
  }
}
